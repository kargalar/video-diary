import 'dart:io';

import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../../features/diary/data/diary_repository.dart';
import '../../features/diary/recording/camera_lens_gateway.dart';
import '../../features/diary/recording/permission_gateway.dart';
import '../../features/diary/recording/recording_consolidator.dart';
import '../../features/diary/recording/recording_diagnostics.dart';
import '../../features/diary/recording/recording_recovery_service.dart';
import '../../features/diary/recording/recording_session_store.dart';
import '../../features/diary/recording/video_segment_merger.dart';
import '../../features/diary/viewmodel/record_view_model.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';

class RecordingDependencies {
  const RecordingDependencies({
    required this.sessionStore,
    required this.consolidator,
    required this.recoveryService,
    required this.recordViewModel,
    required this.diagnostics,
  });

  final RecordingSessionStore sessionStore;
  final RecordingConsolidator consolidator;
  final RecordingRecoveryService recoveryService;
  final RecordViewModel recordViewModel;
  final RecordingDiagnostics diagnostics;
}

Future<RecordingDependencies> buildRecordingDependencies({
  required StorageService storageService,
  required DiaryRepository diaryRepository,
  required VideoService videoService,
  SettingsRepository? settingsRepository,
  VideoSegmentMerger? merger,
  PermissionGateway? permissionGateway,
  CameraLensGateway? cameraLensGateway,
  RecordingDiagnostics? diagnostics,
  RecordingMediaProbe? mediaProbe,
}) async {
  final resolvedSettings = settingsRepository ?? SettingsRepository();
  final resolvedMerger = merger ?? const MethodChannelVideoSegmentMerger();
  final resolvedPermissions = permissionGateway ?? PermissionGateway();
  final resolvedLenses = cameraLensGateway ?? CameraLensGateway();
  final resolvedDiagnostics =
      diagnostics ?? await RecordingDiagnostics.createDefault();
  final resolvedProbe =
      mediaProbe ??
      _defaultMediaProbe(
        storageService: storageService,
        videoService: videoService,
      );
  final sessionStore = RecordingSessionStore(
    rootProvider: () async {
      final root = await storageService.getInternalDiaryFolder();
      return Directory(_join(root.path, 'recording_sessions'));
    },
  );
  final consolidator = RecordingConsolidator(
    store: sessionStore,
    merger: resolvedMerger,
  );
  final recoveryService = RecordingRecoveryService(
    store: sessionStore,
    consolidator: consolidator,
    diaryRepository: diaryRepository,
    mediaProbe: resolvedProbe,
  );
  final recordViewModel = RecordViewModel(
    videoService,
    resolvedSettings,
    storageService,
    permissionGateway: resolvedPermissions,
    cameraLensGateway: resolvedLenses,
    sessionStore: sessionStore,
    consolidator: consolidator,
    diagnostics: resolvedDiagnostics,
    mediaProbe: resolvedProbe,
  );

  return RecordingDependencies(
    sessionStore: sessionStore,
    consolidator: consolidator,
    recoveryService: recoveryService,
    recordViewModel: recordViewModel,
    diagnostics: resolvedDiagnostics,
  );
}

RecordingMediaProbe _defaultMediaProbe({
  required StorageService storageService,
  required VideoService videoService,
}) {
  return (videoPath) async {
    final root = await storageService.getInternalDiaryFolder();
    final thumbnailPath = await vt.VideoThumbnail.thumbnailFile(
      video: videoPath,
      thumbnailPath: _join(root.path, 'thumbnails'),
      imageFormat: vt.ImageFormat.PNG,
      maxHeight: 200,
      quality: 70,
    );
    var durationMs = 0;
    try {
      final player = await videoService.createPlayer(videoPath);
      try {
        durationMs = player.value.duration.inMilliseconds;
      } finally {
        await player.dispose();
      }
    } catch (_) {
      // A playable stable file is still published with an unknown duration.
    }
    return RecordingMediaMetadata(
      thumbnailPath: thumbnailPath,
      durationMs: durationMs,
      fileBytes: await File(videoPath).length(),
    );
  };
}

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';
