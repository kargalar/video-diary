import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/recording/recording_session.dart';
import 'package:video_diary/features/diary/recording/recording_session_store.dart';

void main() {
  group('RecordingSession', () {
    test('round-trips every recovery field through JSON', () {
      final session = RecordingSession(
        sessionId: 'session-42',
        createdAt: DateTime.utc(2026, 8, 1, 12, 30),
        finalPath: '/recordings/2026-08-01.mp4',
        pendingSegmentPaths: const [
          '/segments/segment-0001.mp4',
          '/segments/segment-0002.mp4',
        ],
        activeSegmentPath: '/segments/segment-0003.mp4',
        lensDirection: 'back',
        resumePending: true,
        entryRegistered: true,
        accumulatedDurationMs: 12345,
      );

      expect(RecordingSession.fromJson(session.toJson()), session);
    });

    test('rejects incomplete recovery data', () {
      expect(
        () => RecordingSession.fromJson(const {'sessionId': 'broken'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RecordingSessionStore', () {
    late Directory temporaryDirectory;
    late RecordingSessionStore store;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'video_diary_recording_session_test_',
      );
      store = RecordingSessionStore(
        rootProvider: () async => temporaryDirectory,
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('saves atomically and loads all valid manifests', () async {
      final session =
          RecordingSession.create(
            sessionId: 'session-a',
            createdAt: DateTime.utc(2026, 8, 1),
            finalPath: '/recordings/final.mp4',
            lensDirection: 'front',
          ).copyWith(
            pendingSegmentPaths: const ['/segments/segment-0001.mp4'],
            accumulatedDurationMs: 750,
          );

      await store.save(session);

      final sessionDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}${session.sessionId}',
      );
      expect(
        await File('${sessionDirectory.path}/session.json').exists(),
        isTrue,
      );
      expect(
        await File('${sessionDirectory.path}/session.json.tmp').exists(),
        isFalse,
      );

      await File(
        '${temporaryDirectory.path}/unrelated.tmp',
      ).writeAsString('not a manifest');
      final brokenDirectory = Directory(
        '${temporaryDirectory.path}/broken-session',
      );
      await brokenDirectory.create();
      await File('${brokenDirectory.path}/session.json').writeAsString('{');

      expect(await store.load(session.sessionId), session);
      expect(await store.loadAll(), [session]);
    });

    test('deletes only the requested session directory', () async {
      final first = RecordingSession.create(
        sessionId: 'first',
        createdAt: DateTime.utc(2026, 8, 1),
        finalPath: '/recordings/first.mp4',
        lensDirection: 'back',
      );
      final second = RecordingSession.create(
        sessionId: 'second',
        createdAt: DateTime.utc(2026, 8, 1),
        finalPath: '/recordings/second.mp4',
        lensDirection: 'front',
      );
      await store.save(first);
      await store.save(second);

      await store.delete(first.sessionId);

      expect(await store.load(first.sessionId), isNull);
      expect(await store.load(second.sessionId), second);
    });
  });
}
