import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/core/di/recording_dependencies.dart';
import 'package:video_diary/features/diary/data/diary_repository.dart';
import 'package:video_diary/features/diary/recording/permission_gateway.dart';
import 'package:video_diary/features/diary/recording/recording_recovery_service.dart';
import 'package:video_diary/features/diary/recording/video_segment_merger.dart';
import 'package:video_diary/services/storage_service.dart';
import 'package:video_diary/services/video_service.dart';

void main() {
  test('recording dependencies share one durable session store', () async {
    final root = await Directory.systemTemp.createTemp(
      'video_diary_dependency_test_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final graph = await buildRecordingDependencies(
      storageService: _TestStorageService(root),
      diaryRepository: DiaryRepository(),
      videoService: VideoService(),
      merger: _FakeMerger(),
      permissionGateway: PermissionGateway(
        requestCamera: () async => true,
        requestMicrophone: () async => true,
      ),
      mediaProbe: (_) async => const RecordingMediaMetadata(
        thumbnailPath: null,
        durationMs: 0,
        fileBytes: 1,
      ),
    );

    expect(graph.recordViewModel, isNotNull);
    expect(graph.recoveryService, isNotNull);
    expect(
      identical(graph.sessionStore, graph.recordViewModel.sessionStore),
      isTrue,
    );
  });
}

class _TestStorageService extends StorageService {
  _TestStorageService(this.root);

  final Directory root;

  @override
  Future<Directory> getInternalDiaryFolder() => ensureDiaryFolder(root.path);
}

class _FakeMerger implements VideoSegmentMerger {
  @override
  Future<void> merge({
    required List<String> inputs,
    required String outputPath,
  }) async {}
}
