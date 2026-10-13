package app.videodiary

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

class VideoSegmentMerger {
    fun merge(inputs: List<File>, output: File) {
        validatePaths(inputs, output)

        val segmentInfo = inputs.map { inspectSegment(it) }
        validateCompatibleFormats(segmentInfo)
        output.parentFile?.mkdirs()
        if (output.exists() && !output.delete()) {
            throw IllegalArgumentException("Existing merge output cannot be replaced: ${output.path}")
        }

        var muxer: MediaMuxer? = null
        var muxerStarted = false
        var muxerStopped = false
        var wroteVideoSample = false
        var succeeded = false

        try {
            muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            segmentInfo.first().rotationDegrees?.let(muxer::setOrientationHint)

            val muxerTracks = segmentInfo.first().tracks.mapValues { (_, track) ->
                muxer.addTrack(track.format)
            }
            muxer.start()
            muxerStarted = true

            val largestSample = segmentInfo
                .flatMap { it.tracks.values }
                .maxOfOrNull { track ->
                    if (track.format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                        track.format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                    } else {
                        0
                    }
                } ?: 0
            val buffer = ByteBuffer.allocateDirect(maxOf(DEFAULT_BUFFER_SIZE, largestSample))
            val bufferInfo = MediaCodec.BufferInfo()
            var segmentOffsetUs = 0L

            inputs.zip(segmentInfo).forEach { (input, info) ->
                val copyResult = copySegment(
                    input = input,
                    info = info,
                    muxer = muxer,
                    muxerTracks = muxerTracks,
                    buffer = buffer,
                    bufferInfo = bufferInfo,
                    segmentOffsetUs = segmentOffsetUs,
                )
                wroteVideoSample = wroteVideoSample || copyResult.wroteVideoSample
                segmentOffsetUs += maxOf(
                    1L,
                    info.durationUs,
                    copyResult.lastSampleTimeUs + 1L,
                )
            }

            require(wroteVideoSample) { "No video samples were found in the input segments" }
            muxer.stop()
            muxerStopped = true
            succeeded = true
        } finally {
            if (muxerStarted && !muxerStopped && wroteVideoSample) {
                try {
                    muxer?.stop()
                } catch (_: RuntimeException) {
                    // The partial output is deleted below; keep the original failure.
                }
            }
            try {
                muxer?.release()
            } finally {
                if (!succeeded) output.delete()
            }
        }
    }

    private fun validatePaths(inputs: List<File>, output: File) {
        require(inputs.size >= 2) { "At least two input segments are required" }
        inputs.forEach { input ->
            require(input.isFile && input.length() > 0L) {
                "Input segment is missing or empty: ${input.path}"
            }
        }
        val outputPath = output.canonicalFile
        require(inputs.none { it.canonicalFile == outputPath }) {
            "Merge output must be distinct from every input"
        }
    }

    private fun inspectSegment(file: File): SegmentInfo {
        val extractor = MediaExtractor()
        try {
            try {
                extractor.setDataSource(file.absolutePath)
            } catch (error: Exception) {
                throw IllegalArgumentException("Input is not a readable media file: ${file.path}", error)
            }

            val tracks = linkedMapOf<TrackKind, TrackInfo>()
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                val kind = when {
                    mime.startsWith("video/") -> TrackKind.VIDEO
                    mime.startsWith("audio/") -> TrackKind.AUDIO
                    else -> null
                } ?: continue
                tracks.putIfAbsent(kind, TrackInfo(index, format))
            }
            require(tracks.containsKey(TrackKind.VIDEO)) {
                "Input contains no video track: ${file.path}"
            }

            return SegmentInfo(
                tracks = tracks,
                durationUs = readDurationUs(file),
                rotationDegrees = readRotation(file),
            )
        } finally {
            extractor.release()
        }
    }

    private fun validateCompatibleFormats(segments: List<SegmentInfo>) {
        val expected = segments.first()
        segments.drop(1).forEachIndexed { index, segment ->
            require(segment.tracks.keys == expected.tracks.keys) {
                "Segment ${index + 2} has a different audio/video track set"
            }
            expected.tracks.forEach { (kind, expectedTrack) ->
                val actualTrack = requireNotNull(segment.tracks[kind])
                require(formatsMatch(kind, expectedTrack.format, actualTrack.format)) {
                    "Segment ${index + 2} has an incompatible ${kind.name.lowercase()} format"
                }
            }
        }
    }

    private fun formatsMatch(kind: TrackKind, expected: MediaFormat, actual: MediaFormat): Boolean {
        if (expected.getString(MediaFormat.KEY_MIME) != actual.getString(MediaFormat.KEY_MIME)) {
            return false
        }
        val keys = when (kind) {
            TrackKind.VIDEO -> listOf(MediaFormat.KEY_WIDTH, MediaFormat.KEY_HEIGHT)
            TrackKind.AUDIO -> listOf(MediaFormat.KEY_SAMPLE_RATE, MediaFormat.KEY_CHANNEL_COUNT)
        }
        return keys.all { key ->
            expected.containsKey(key) &&
                actual.containsKey(key) &&
                expected.getInteger(key) == actual.getInteger(key)
        }
    }

    private fun copySegment(
        input: File,
        info: SegmentInfo,
        muxer: MediaMuxer,
        muxerTracks: Map<TrackKind, Int>,
        buffer: ByteBuffer,
        bufferInfo: MediaCodec.BufferInfo,
        segmentOffsetUs: Long,
    ): CopyResult {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(input.absolutePath)
            val inputTrackKinds = info.tracks.entries.associate { (kind, track) ->
                extractor.selectTrack(track.index)
                track.index to kind
            }
            var lastSampleTimeUs = 0L
            var wroteVideo = false

            while (true) {
                val inputTrackIndex = extractor.sampleTrackIndex
                if (inputTrackIndex < 0) break
                val kind = inputTrackKinds[inputTrackIndex]
                    ?: throw IllegalArgumentException("Unexpected selected track in ${input.path}")
                buffer.clear()
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                val sourceTimeUs = maxOf(0L, extractor.sampleTime)
                val adjustedTimeUs = segmentOffsetUs + sourceTimeUs
                bufferInfo.set(
                    0,
                    sampleSize,
                    adjustedTimeUs,
                    extractor.sampleFlags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG.inv(),
                )
                muxer.writeSampleData(requireNotNull(muxerTracks[kind]), buffer, bufferInfo)
                lastSampleTimeUs = maxOf(lastSampleTimeUs, sourceTimeUs)
                if (kind == TrackKind.VIDEO) wroteVideo = true
                extractor.advance()
            }
            return CopyResult(lastSampleTimeUs, wroteVideo)
        } finally {
            extractor.release()
        }
    }

    private fun readDurationUs(file: File): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            durationMs * 1_000L
        } finally {
            retriever.release()
        }
    }

    private fun readRotation(file: File): Int? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull()
        } finally {
            retriever.release()
        }
    }

    private enum class TrackKind { VIDEO, AUDIO }

    private data class TrackInfo(val index: Int, val format: MediaFormat)

    private data class SegmentInfo(
        val tracks: Map<TrackKind, TrackInfo>,
        val durationUs: Long,
        val rotationDegrees: Int?,
    )

    private data class CopyResult(
        val lastSampleTimeUs: Long,
        val wroteVideoSample: Boolean,
    )

    private companion object {
        const val DEFAULT_BUFFER_SIZE = 4 * 1024 * 1024
    }
}
