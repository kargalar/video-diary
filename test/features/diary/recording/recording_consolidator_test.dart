import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/recording/recording_consolidator.dart';
import 'package:video_diary/features/diary/recording/recording_session.dart';
import 'package:video_diary/features/diary/recording/recording_session_store.dart';
import 'package:video_diary/features/diary/recording/video_segment_merger.dart';

void main() {
  late Directory root;
  late RecordingSessionStore store;
  late _FakeVideoSegmentMerger merger;
  late RecordingConsolidator consolidator;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'video_diary_consolidator_test_',
    );
    store = RecordingSessionStore(
      rootProvider: () async => Directory('${root.path}/sessions'),
    );
    merger = _FakeVideoSegmentMerger();
    consolidator = RecordingConsolidator(store: store, merger: merger);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('promotes first segment without invoking native merge', () async {
    final segment = File('${root.path}/part-1.mp4');
    await segment.writeAsBytes([1, 2, 3], flush: true);
    final session = _session(
      finalPath: '${root.path}/final.mp4',
      pending: [segment.path],
    );
    await store.save(session);

    final result = await consolidator.consolidate(session);

    expect(await File(result.finalPath).readAsBytes(), [1, 2, 3]);
    expect(result.pendingSegmentPaths, isEmpty);
    expect(merger.calls, isEmpty);
    expect(await segment.exists(), isFalse);
    expect(await store.load(session.sessionId), result);
  });

  test('merge failure preserves stable file, segment, and manifest', () async {
    final stable = File('${root.path}/final.mp4');
    final segment = File('${root.path}/part-2.mp4');
    await stable.writeAsBytes([1, 2, 3], flush: true);
    await segment.writeAsBytes([4, 5, 6], flush: true);
    final session = _session(finalPath: stable.path, pending: [segment.path]);
    await store.save(session);
    merger.error = const VideoMergeException('failed', 'boom');

    await expectLater(
      consolidator.consolidate(session),
      throwsA(isA<VideoMergeException>()),
    );

    expect(await stable.readAsBytes(), [1, 2, 3]);
    expect(await segment.readAsBytes(), [4, 5, 6]);
    expect(await File('${stable.path}.merging').exists(), isFalse);
    expect(await store.load(session.sessionId), session);
  });

  test(
    'successful merge replaces stable file before deleting segments',
    () async {
      final stable = File('${root.path}/final.mp4');
      final first = File('${root.path}/part-2.mp4');
      final second = File('${root.path}/part-3.mp4');
      await stable.writeAsBytes([1], flush: true);
      await first.writeAsBytes([2], flush: true);
      await second.writeAsBytes([3], flush: true);
      final session = _session(
        finalPath: stable.path,
        pending: [first.path, second.path],
      );
      await store.save(session);

      final result = await consolidator.consolidate(session);

      expect(merger.calls.single.inputs, [
        stable.path,
        first.path,
        second.path,
      ]);
      expect(await stable.readAsBytes(), [1, 2, 3]);
      expect(await first.exists(), isFalse);
      expect(await second.exists(), isFalse);
      expect(result.pendingSegmentPaths, isEmpty);
    },
  );
}

RecordingSession _session({
  required String finalPath,
  required List<String> pending,
}) {
  return RecordingSession.create(
    sessionId: 'session-1',
    createdAt: DateTime.utc(2026, 8, 1),
    finalPath: finalPath,
    lensDirection: 'back',
  ).copyWith(pendingSegmentPaths: pending);
}

class _MergeCall {
  const _MergeCall(this.inputs, this.outputPath);

  final List<String> inputs;
  final String outputPath;
}

class _FakeVideoSegmentMerger implements VideoSegmentMerger {
  final calls = <_MergeCall>[];
  VideoMergeException? error;

  @override
  Future<void> merge({
    required List<String> inputs,
    required String outputPath,
  }) async {
    calls.add(_MergeCall(List.of(inputs), outputPath));
    final failure = error;
    if (failure != null) throw failure;

    final output = File(outputPath);
    final sink = output.openWrite();
    try {
      for (final input in inputs) {
        sink.add(await File(input).readAsBytes());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}
