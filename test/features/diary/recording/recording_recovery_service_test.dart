import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:video_diary/features/diary/data/diary_repository.dart';
import 'package:video_diary/features/diary/model/diary_entry.dart';
import 'package:video_diary/features/diary/recording/recording_consolidator.dart';
import 'package:video_diary/features/diary/recording/recording_recovery_service.dart';
import 'package:video_diary/features/diary/recording/recording_session.dart';
import 'package:video_diary/features/diary/recording/recording_session_store.dart';
import 'package:video_diary/features/diary/recording/video_segment_merger.dart';

void main() {
  late Directory root;
  late DiaryRepository repository;
  late RecordingSessionStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('video_diary_recovery_test_');
    repository = DiaryRepository(
      hiveInitializer: () async => Hive.init('${root.path}/hive'),
      boxName: 'diary_entries_test',
    );
    store = RecordingSessionStore(
      rootProvider: () async => Directory('${root.path}/sessions'),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('upsert replaces an existing path instead of duplicating it', () async {
    final path = '${root.path}/video.mp4';
    final oldEntry = DiaryEntry(
      path: path,
      date: DateTime.utc(2026, 8, 1),
      fileBytes: 10,
    );
    final updatedEntry = DiaryEntry(
      path: path,
      date: DateTime.utc(2026, 8, 1, 1),
      fileBytes: 20,
      durationMs: 500,
    );
    await repository.save([oldEntry]);

    await repository.upsertByPath(updatedEntry);

    final entries = await repository.load();
    expect(entries.where((entry) => entry.path == path), hasLength(1));
    expect(entries.single.fileBytes, 20);
    expect(entries.single.durationMs, 500);
  });

  test('removeByPath removes metadata without deleting the video', () async {
    final video = File('${root.path}/video.mp4');
    await video.writeAsBytes([1], flush: true);
    await repository.save([
      DiaryEntry(path: video.path, date: DateTime.utc(2026, 8, 1)),
    ]);

    await repository.removeByPath(video.path);

    expect(await repository.load(), isEmpty);
    expect(await video.exists(), isTrue);
  });

  test('recovery is idempotent and publishes one stable entry', () async {
    final activeSegment = File('${root.path}/active.mp4');
    await activeSegment.writeAsBytes([1, 2, 3], flush: true);
    final interruptedSession =
        RecordingSession.create(
          sessionId: 'interrupted',
          createdAt: DateTime.utc(2026, 8, 1, 12),
          finalPath: '${root.path}/final.mp4',
          lensDirection: 'front',
        ).copyWith(
          activeSegmentPath: activeSegment.path,
          resumePending: true,
          accumulatedDurationMs: 900,
        );
    await store.save(interruptedSession);
    var probeCalls = 0;
    final recovery = RecordingRecoveryService(
      store: store,
      consolidator: RecordingConsolidator(
        store: store,
        merger: _UnexpectedMerger(),
      ),
      diaryRepository: repository,
      mediaProbe: (videoPath) async {
        probeCalls++;
        expect(videoPath, interruptedSession.finalPath);
        final thumbnail = File('${root.path}/thumbnail.png');
        await thumbnail.writeAsBytes([9], flush: true);
        return RecordingMediaMetadata(
          thumbnailPath: thumbnail.path,
          durationMs: 900,
          fileBytes: await File(videoPath).length(),
        );
      },
    );

    final firstReport = await recovery.recover();
    final secondReport = await recovery.recover();

    expect(firstReport.recoveredSessionIds, ['interrupted']);
    expect(firstReport.failures, isEmpty);
    expect(secondReport.recoveredSessionIds, isEmpty);
    expect(probeCalls, 1);
    final entries = await repository.load();
    expect(
      entries.where((entry) => entry.path == interruptedSession.finalPath),
      hasLength(1),
    );
    expect(entries.single.lensDirection, 'front');
    expect(entries.single.durationMs, 900);
    expect(await store.loadAll(), isEmpty);
    expect(await activeSegment.exists(), isFalse);
    expect(await File(interruptedSession.finalPath).readAsBytes(), [1, 2, 3]);
  });

  test('recovery failure retains manifest and source footage', () async {
    final segment = File('${root.path}/active.mp4');
    await segment.writeAsBytes([1], flush: true);
    final session = RecordingSession.create(
      sessionId: 'failed-session',
      createdAt: DateTime.utc(2026, 8, 1),
      finalPath: '${root.path}/final.mp4',
      lensDirection: 'back',
    ).copyWith(activeSegmentPath: segment.path);
    await store.save(session);
    final recovery = RecordingRecoveryService(
      store: store,
      consolidator: RecordingConsolidator(
        store: store,
        merger: _UnexpectedMerger(),
      ),
      diaryRepository: repository,
      mediaProbe: (_) async => throw Exception('probe failed'),
    );

    final report = await recovery.recover();

    expect(report.failures.keys, ['failed-session']);
    expect(await store.load('failed-session'), isNotNull);
    expect(await File(session.finalPath).exists(), isTrue);
  });
}

class _UnexpectedMerger implements VideoSegmentMerger {
  @override
  Future<void> merge({
    required List<String> inputs,
    required String outputPath,
  }) {
    throw StateError('Native merge was not expected');
  }
}
