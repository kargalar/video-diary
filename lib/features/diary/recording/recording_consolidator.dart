import 'dart:io';

import 'recording_session.dart';
import 'recording_session_store.dart';
import 'video_segment_merger.dart';

class RecordingConsolidator {
  RecordingConsolidator({
    required RecordingSessionStore store,
    required VideoSegmentMerger merger,
  }) : _store = store,
       _merger = merger;

  final RecordingSessionStore _store;
  final VideoSegmentMerger _merger;

  Future<RecordingSession> consolidate(RecordingSession session) async {
    var current = session;
    if (current.pendingSegmentPaths.isEmpty) return current;

    final stableFile = File(current.finalPath);
    if (!await stableFile.exists()) {
      current = await _promoteFirstSegment(current);
    } else if (await stableFile.length() == 0) {
      throw StateError('Stable recording file is empty: ${stableFile.path}');
    }

    if (current.pendingSegmentPaths.isEmpty) return current;
    return _mergePendingSegments(current);
  }

  Future<RecordingSession> _promoteFirstSegment(
    RecordingSession session,
  ) async {
    final firstSegment = File(session.pendingSegmentPaths.first);
    await _requireReadable(firstSegment);
    final mergingFile = File('${session.finalPath}.merging');

    try {
      await _removeIfPresent(mergingFile);
      await _copyAndFlush(firstSegment, mergingFile);
      await _requireReadable(mergingFile);
      await _replaceStableFile(mergingFile, File(session.finalPath));

      final updated = session.copyWith(
        pendingSegmentPaths: session.pendingSegmentPaths.skip(1).toList(),
      );
      await _store.save(updated);
      await _removeIfPresent(firstSegment);
      return updated;
    } catch (_) {
      await _removeIfPresent(mergingFile);
      rethrow;
    }
  }

  Future<RecordingSession> _mergePendingSegments(
    RecordingSession session,
  ) async {
    final stableFile = File(session.finalPath);
    final pendingFiles = session.pendingSegmentPaths.map(File.new).toList();
    for (final segment in pendingFiles) {
      await _requireReadable(segment);
    }

    final mergingFile = File('${session.finalPath}.merging');
    try {
      await _removeIfPresent(mergingFile);
      await _merger.merge(
        inputs: [stableFile.path, ...session.pendingSegmentPaths],
        outputPath: mergingFile.path,
      );
      await _requireReadable(mergingFile);
      await _replaceStableFile(mergingFile, stableFile);

      final updated = session.copyWith(pendingSegmentPaths: const []);
      await _store.save(updated);
      for (final segment in pendingFiles) {
        await _removeIfPresent(segment);
      }
      return updated;
    } catch (_) {
      await _removeIfPresent(mergingFile);
      rethrow;
    }
  }
}

Future<void> _copyAndFlush(File source, File destination) async {
  await destination.parent.create(recursive: true);
  final input = await source.open();
  final output = await destination.open(mode: FileMode.write);
  try {
    const chunkSize = 1024 * 1024;
    while (true) {
      final chunk = await input.read(chunkSize);
      if (chunk.isEmpty) break;
      await output.writeFrom(chunk);
    }
    await output.flush();
  } finally {
    await input.close();
    await output.close();
  }
}

Future<void> _replaceStableFile(File replacement, File stable) async {
  await stable.parent.create(recursive: true);
  await replacement.rename(stable.path);
}

Future<void> _requireReadable(File file) async {
  if (!await file.exists() || await file.length() == 0) {
    throw StateError('Recording segment is missing or empty: ${file.path}');
  }
}

Future<void> _removeIfPresent(File file) async {
  if (await file.exists()) await file.delete();
}
