package app.videodiary

import android.media.MediaExtractor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VideoSegmentMergerTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val assetContext = instrumentation.context
    private val fileContext = instrumentation.targetContext
    private val createdFiles = mutableListOf<File>()

    @After
    fun cleanUp() {
        createdFiles.forEach { it.delete() }
    }

    @Test
    fun mergesTwoSegmentsWithMonotonicAudioAndVideoSamples() {
        val output = trackedFile("merged.mp4")
        val inputs = listOf(copyAsset("segment_a.mp4"), copyAsset("segment_b.mp4"))

        VideoSegmentMerger().merge(inputs, output)

        assertTrue(output.length() > inputs.maxOf { it.length() })
        assertTrackSamplesAreMonotonic(output, "video/")
        assertTrackSamplesAreMonotonic(output, "audio/")
        inputs.forEach { assertTrue(it.exists()) }
    }

    @Test
    fun invalidInputKeepsSourcesAndRemovesPartialOutput() {
        val source = copyAsset("segment_a.mp4")
        val invalid = trackedFile("invalid.mp4").apply { writeText("invalid") }
        val output = trackedFile("failed.mp4")
        var didThrow = false

        try {
            VideoSegmentMerger().merge(listOf(source, invalid), output)
        } catch (_: IllegalArgumentException) {
            didThrow = true
        }

        assertTrue(didThrow)
        assertTrue(source.exists())
        assertTrue(invalid.exists())
        assertFalse(output.exists())
    }

    private fun copyAsset(name: String): File {
        val output = trackedFile(name)
        assetContext.assets.open(name).use { input ->
            output.outputStream().use { destination -> input.copyTo(destination) }
        }
        return output
    }

    private fun trackedFile(name: String): File =
        File(fileContext.cacheDir.apply { mkdirs() }, "${System.nanoTime()}-$name").also {
            createdFiles.add(it)
        }

    private fun assertTrackSamplesAreMonotonic(file: File, mimePrefix: String) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.absolutePath)
            val trackIndex = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString("mime")?.startsWith(mimePrefix) == true
            }
            extractor.selectTrack(trackIndex)
            var previousTimestamp = -1L
            var sampleCount = 0
            while (true) {
                val timestamp = extractor.sampleTime
                if (timestamp < 0) break
                assertTrue("sample timestamps must not move backwards", timestamp >= previousTimestamp)
                previousTimestamp = timestamp
                sampleCount++
                extractor.advance()
            }
            assertTrue("expected samples for $mimePrefix", sampleCount > 0)
        } finally {
            extractor.release()
        }
    }
}
