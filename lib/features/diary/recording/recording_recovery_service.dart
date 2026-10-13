import 'dart:io';

import '../data/diary_repository.dart';
import '../model/diary_entry.dart';
import 'recording_consolidator.dart';
import 'recording_session.dart';
import 'recording_session_store.dart';

typedef RecordingMediaProbe =
    Future<RecordingMediaMetadata> Function(String videoPath);

class RecordingMediaMetadata {
  const RecordingMediaMetadata({
    required this.thumbnailPath,
    required this.durationMs,
    required this.fileBytes,
  });

  final String? thumbnailPath;
  final int durationMs;
  final int fileBytes;
}

class RecordingRecoveryReport {
  RecordingRecoveryReport({
    required List<String> recoveredSessionIds,
    required Map<String, String> failures,
  }) : recoveredSessionIds = List.unmodifiable(recoveredSessionIds),
       failures = Map.unmodifiable(failures);

  final List<String> recoveredSessionIds;
  final Map<String, String> failures;
}

class RecordingRecoveryService {
  RecordingRecoveryService({
    required RecordingSessionStore store,
    required RecordingConsolidator consolidator,
    required DiaryRepository diaryRepository,
    required RecordingMediaProbe mediaProbe,
  }) : _store = store,
       _consolidator = consolidator,
       _diaryRepository = diaryRepository,
       _mediaProbe = mediaProbe;

  final RecordingSessionStore _store;
  final RecordingConsolidator _consolidator;
  final DiaryRepository _diaryRepository;
  final RecordingMediaProbe _mediaProbe;

  Future<RecordingRecoveryReport> recover() async {
    final recovered = <String>[];
    final failures = <String, String>{};
    final sessions = await _store.loadAll();

    for (final session in sessions) {
      try {
        await _recoverSession(session);
        recovered.add(session.sessionId);
      } catch (error) {
        failures[session.sessionId] = error.toString();
      }
    }

    return RecordingRecoveryReport(
      recoveredSessionIds: recovered,
      failures: failures,
    );
  }

  Future<void> _recoverSession(RecordingSession session) async {
    var current = await _recoverActiveSegment(session);
    current = await _consolidator.consolidate(current);

    final stableFile = File(current.finalPath);
    if (!await stableFile.exists() || await stableFile.length() == 0) {
      throw StateError('Recovered recording is missing: ${current.finalPath}');
    }

    final metadata = await _mediaProbe(current.finalPath);
    await _diaryRepository.upsertByPath(
      DiaryEntry(
        path: current.finalPath,
        date: current.createdAt,
        thumbnailPath: metadata.thumbnailPath,
        durationMs: metadata.durationMs,
        fileBytes: metadata.fileBytes,
        lensDirection: current.lensDirection,
      ),
    );

    current = current.copyWith(entryRegistered: true, resumePending: false);
    await _store.save(current);
    await _store.delete(current.sessionId);
  }

  Future<RecordingSession> _recoverActiveSegment(
    RecordingSession session,
  ) async {
    final activePath = session.activeSegmentPath;
    if (activePath == null) return session;

    final activeFile = File(activePath);
    if (!await activeFile.exists() || await activeFile.length() == 0) {
      final stableFile = File(session.finalPath);
      if (!await stableFile.exists() || await stableFile.length() == 0) {
        throw StateError(
          'Interrupted recording segment is missing: $activePath',
        );
      }
      final updated = session.copyWith(activeSegmentPath: null);
      await _store.save(updated);
      return updated;
    }

    final pending = List<String>.from(session.pendingSegmentPaths);
    if (!pending.contains(activePath)) pending.add(activePath);
    final updated = session.copyWith(
      pendingSegmentPaths: pending,
      activeSegmentPath: null,
    );
    await _store.save(updated);
    return updated;
  }
}
