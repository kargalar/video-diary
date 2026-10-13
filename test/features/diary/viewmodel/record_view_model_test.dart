import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/recording/permission_gateway.dart';
import 'package:video_diary/features/diary/recording/recording_consolidator.dart';
import 'package:video_diary/features/diary/recording/recording_diagnostics.dart';
import 'package:video_diary/features/diary/recording/recording_recovery_service.dart';
import 'package:video_diary/features/diary/recording/recording_session_store.dart';
import 'package:video_diary/features/diary/recording/video_segment_merger.dart';
import 'package:video_diary/features/diary/viewmodel/record_state.dart';
import 'package:video_diary/features/diary/viewmodel/record_view_model.dart';
import 'package:video_diary/features/settings/data/settings_repository.dart';
import 'package:video_diary/services/storage_service.dart';
import 'package:video_diary/services/video_service.dart';

void main() {
  late Directory root;
  late RecordingSessionStore store;
  late RecordViewModel viewModel;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'video_diary_record_view_model_test_',
    );
    final storage = _TestStorageService(root);
    store = RecordingSessionStore(
      rootProvider: () async => Directory('${root.path}/recording_sessions'),
    );
    final consolidator = RecordingConsolidator(
      store: store,
      merger: _ConcatenatingMerger(),
    );
    viewModel = RecordViewModel(
      VideoService(),
      SettingsRepository(),
      storage,
      sessionStore: store,
      consolidator: consolidator,
      permissionGateway: PermissionGateway(
        requestCamera: () async => true,
        requestMicrophone: () async => true,
      ),
      diagnostics: RecordingDiagnostics(
        androidSdk: 36,
        deviceModel: 'test',
        sink: (_) {},
      ),
      mediaProbe: (path) async => RecordingMediaMetadata(
        thumbnailPath: null,
        durationMs: 500,
        fileBytes: await File(path).length(),
      ),
      segmentDurationProbe: (_) async => 500,
      now: () => DateTime.utc(2026, 8, 1, 12),
      sessionIdFactory: (_) => 'session-1',
    );
  });

  tearDown(() async {
    viewModel.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('duplicate paused and hidden events request one stop', () async {
    await viewModel.beginSession();
    await viewModel.registerActiveSegment('${root.path}/part-1.mp4');

    expect(await viewModel.requestLifecycleFinalize(), isTrue);
    expect(await viewModel.requestLifecycleFinalize(), isFalse);
  });

  test(
    'saved background segment becomes resumable provisional entry',
    () async {
      final finalPath = await viewModel.beginSession();
      final segment = File('${root.path}/part-1.mp4');
      await segment.writeAsBytes([1, 2, 3], flush: true);
      await viewModel.registerActiveSegment(segment.path);
      await viewModel.requestLifecycleFinalize();

      final entry = await viewModel.handleSegmentSaved(segment.path);

      expect(entry?.path, finalPath);
      expect(viewModel.state.status, RecordStatus.waitingForResume);
      expect(viewModel.shouldAutoResume, isTrue);
      expect(viewModel.state.recordedDurationMs, 500);
      expect(await File(finalPath!).readAsBytes(), [1, 2, 3]);

      await viewModel.confirmEntryPersisted();
      expect(await store.load('session-1'), isNotNull);
      expect(await viewModel.beginResumedSegment(), isTrue);
      expect(viewModel.shouldAutoResume, isFalse);
    },
  );

  test('capture failure resets controls and preserves pending files', () async {
    await viewModel.beginSession();
    final segment = File('${root.path}/part-1.mp4');
    await segment.writeAsBytes([4, 5, 6], flush: true);
    await viewModel.registerActiveSegment(segment.path);

    await viewModel.handleCaptureFailure(Exception('encoder failed'));

    expect(viewModel.state.status, RecordStatus.error);
    expect(viewModel.state.isRecording, isFalse);
    expect(await segment.exists(), isTrue);
    expect(viewModel.state.errorMessage, contains('encoder failed'));
    expect(await store.load('session-1'), isNotNull);
  });

  test('user finalize completes instead of scheduling resume', () async {
    final finalPath = await viewModel.beginSession();
    final segment = File('${root.path}/part-1.mp4');
    await segment.writeAsBytes([7, 8], flush: true);
    await viewModel.registerActiveSegment(segment.path);

    expect(await viewModel.requestUserFinalize(), isTrue);
    final entry = await viewModel.handleSegmentSaved(segment.path);

    expect(entry?.path, finalPath);
    expect(viewModel.state.status, RecordStatus.completed);
    expect(viewModel.shouldAutoResume, isFalse);

    await viewModel.confirmEntryPersisted();
    expect(await store.load('session-1'), isNull);
    expect(await File(finalPath!).exists(), isTrue);
  });

  test('resumed segments are published as one final video path', () async {
    final finalPath = await viewModel.beginSession();
    final first = File('${root.path}/part-1.mp4');
    await first.writeAsBytes([1], flush: true);
    await viewModel.registerActiveSegment(first.path);
    await viewModel.requestLifecycleFinalize();
    final provisional = await viewModel.handleSegmentSaved(first.path);
    await viewModel.confirmEntryPersisted();

    expect(await viewModel.beginResumedSegment(), isTrue);
    final second = File('${root.path}/part-2.mp4');
    await second.writeAsBytes([2], flush: true);
    await viewModel.registerActiveSegment(second.path);
    await viewModel.requestUserFinalize();
    final completed = await viewModel.handleSegmentSaved(second.path);

    expect(provisional?.path, finalPath);
    expect(completed?.path, finalPath);
    expect(await File(finalPath!).readAsBytes(), [1, 2]);
    expect(viewModel.state.recordedDurationMs, 1000);
    expect(viewModel.state.status, RecordStatus.completed);
  });
}

class _TestStorageService extends StorageService {
  _TestStorageService(this.root);

  final Directory root;

  @override
  Future<Directory> getInternalDiaryFolder() => ensureDiaryFolder(root.path);
}

class _ConcatenatingMerger implements VideoSegmentMerger {
  @override
  Future<void> merge({
    required List<String> inputs,
    required String outputPath,
  }) async {
    final output = File(outputPath).openWrite();
    try {
      for (final input in inputs) {
        output.add(await File(input).readAsBytes());
      }
      await output.flush();
    } finally {
      await output.close();
    }
  }
}
