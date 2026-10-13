import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../../../services/storage_service.dart';
import '../../../services/video_service.dart';
import '../../settings/data/settings_repository.dart';
import '../model/diary_entry.dart';
import '../recording/camera_lens_gateway.dart';
import '../recording/permission_gateway.dart';
import '../recording/recording_consolidator.dart';
import '../recording/recording_diagnostics.dart';
import '../recording/recording_recovery_service.dart';
import '../recording/recording_session.dart';
import '../recording/recording_session_store.dart';
import '../recording/video_segment_merger.dart';
import 'record_state.dart';

typedef SegmentDurationProbe = Future<int> Function(String path);
typedef RecordingClock = DateTime Function();
typedef SessionIdFactory = String Function(DateTime createdAt);

class RecordViewModel extends ChangeNotifier {
  RecordViewModel(
    this._videoService,
    SettingsRepository _,
    this._storageService, {
    PermissionGateway? permissionGateway,
    CameraLensGateway? cameraLensGateway,
    RecordingSessionStore? sessionStore,
    RecordingConsolidator? consolidator,
    RecordingDiagnostics? diagnostics,
    RecordingMediaProbe? mediaProbe,
    SegmentDurationProbe? segmentDurationProbe,
    RecordingClock? now,
    SessionIdFactory? sessionIdFactory,
  }) : _permissionGateway = permissionGateway ?? PermissionGateway(),
       _cameraLensGateway = cameraLensGateway ?? CameraLensGateway(),
       _now = now ?? DateTime.now,
       _sessionIdFactory = sessionIdFactory ?? _defaultSessionId {
    _sessionStore =
        sessionStore ??
        RecordingSessionStore(rootProvider: _defaultSessionRootProvider);
    _consolidator =
        consolidator ??
        RecordingConsolidator(
          store: _sessionStore,
          merger: const MethodChannelVideoSegmentMerger(),
        );
    _diagnostics =
        diagnostics ??
        RecordingDiagnostics(
          androidSdk: null,
          deviceModel: 'uninitialized',
          sink: (line) => debugPrint(line),
        );
    _mediaProbe = mediaProbe ?? _probeMedia;
    _segmentDurationProbe = segmentDurationProbe ?? _probeSegmentDuration;
  }

  static const String _preferredCameraLensKey = 'preferred_camera_lens';

  final VideoService _videoService;
  final StorageService _storageService;
  final PermissionGateway _permissionGateway;
  final CameraLensGateway _cameraLensGateway;
  final RecordingClock _now;
  final SessionIdFactory _sessionIdFactory;

  late final RecordingSessionStore _sessionStore;
  late final RecordingConsolidator _consolidator;
  late final RecordingDiagnostics _diagnostics;
  late final RecordingMediaProbe _mediaProbe;
  late final SegmentDurationProbe _segmentDurationProbe;

  RecordState _state = const RecordState();
  RecordingSession? _session;
  DateTime? _recordingStartedAt;
  bool _preferredLensLoaded = false;
  bool _stopRequested = false;
  Future<DiaryEntry?>? _segmentOperation;

  RecordState get state => _state;
  DateTime? get recordingStartedAt => _recordingStartedAt;
  bool get shouldAutoResume =>
      _state.status == RecordStatus.waitingForResume &&
      (_session?.resumePending ?? false);

  @visibleForTesting
  RecordingSessionStore get sessionStore => _sessionStore;

  void _updateState(RecordState newState) {
    _state = newState;
    notifyListeners();
  }

  Future<void> ensurePreferredLensLoaded() async {
    if (_preferredLensLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_preferredCameraLensKey);
    final preferred = stored == 'back' ? 'back' : 'front';
    final resolved = await _cameraLensGateway.resolvePreferred(preferred);
    _updateState(_state.copyWith(preferredLensDirection: resolved));
    _preferredLensLoaded = true;
  }

  Future<void> savePreferredLens(String direction) async {
    final resolved = await _cameraLensGateway.resolvePreferred(direction);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredCameraLensKey, resolved);
    _updateState(_state.copyWith(preferredLensDirection: resolved));
  }

  Future<bool> requestAndCheckPermissions() =>
      _permissionGateway.requestRecordingPermissions();

  Future<String?> beginSession() async {
    final existing = _session;
    if (existing != null) return existing.finalPath;

    _updateState(
      _state.copyWith(status: RecordStatus.initializing, errorMessage: null),
    );
    final hasPermissions = await requestAndCheckPermissions();
    if (!hasPermissions) {
      _updateState(
        _state.copyWith(
          status: RecordStatus.error,
          hasPermission: false,
          errorMessage: 'Camera and microphone permissions are required.',
        ),
      );
      return null;
    }

    final createdAt = _now();
    final sessionId = _sessionIdFactory(createdAt);
    final diaryRoot = await _storageService.getInternalDiaryFolder();
    final finalPath = _join(
      _join(diaryRoot.path, 'videos'),
      _fileNameFor(createdAt, sessionId),
    );
    final session = RecordingSession.create(
      sessionId: sessionId,
      createdAt: createdAt,
      finalPath: finalPath,
      lensDirection: _state.preferredLensDirection,
    );
    await _sessionStore.save(session);
    _session = session;
    _stopRequested = false;
    _recordingStartedAt = null;
    _updateState(
      _state.copyWith(
        status: RecordStatus.ready,
        hasPermission: true,
        videoPath: finalPath,
        errorMessage: null,
        sessionId: sessionId,
        recordedDurationMs: 0,
        resumePending: false,
      ),
    );
    _diagnostics.log('session_started', session: session);
    return finalPath;
  }

  Future<void> registerActiveSegment(String path) async {
    final session = _requireSession();
    if (session.activeSegmentPath != null &&
        session.activeSegmentPath != path) {
      throw StateError('Another recording segment is already active');
    }

    final updated = session.copyWith(
      activeSegmentPath: path,
      resumePending: false,
    );
    await _sessionStore.save(updated);
    _session = updated;
    _stopRequested = false;
    _recordingStartedAt = _now();
    _updateState(
      _state.copyWith(
        status: RecordStatus.recording,
        videoPath: updated.finalPath,
        errorMessage: null,
        sessionId: updated.sessionId,
        recordedDurationMs: updated.accumulatedDurationMs,
        resumePending: false,
      ),
    );
    _diagnostics.log('native_recording_started', session: updated);
  }

  Future<bool> requestLifecycleFinalize() =>
      _requestFinalize(resumePending: true, reason: 'background');

  Future<bool> requestUserFinalize() =>
      _requestFinalize(resumePending: false, reason: 'user');

  Future<bool> _requestFinalize({
    required bool resumePending,
    required String reason,
  }) async {
    final session = _session;
    if (session == null ||
        session.activeSegmentPath == null ||
        _stopRequested ||
        _state.status != RecordStatus.recording) {
      return false;
    }

    _stopRequested = true;
    final updated = session.copyWith(resumePending: resumePending);
    try {
      await _sessionStore.save(updated);
    } catch (_) {
      _stopRequested = false;
      rethrow;
    }
    _session = updated;
    _updateState(
      _state.copyWith(
        status: RecordStatus.finalizing,
        resumePending: resumePending,
      ),
    );
    _diagnostics.log(
      resumePending ? 'lifecycle_finalize_requested' : 'user_stop_requested',
      session: updated,
      lifecycleReason: reason,
    );
    return true;
  }

  Future<DiaryEntry?> handleSegmentSaved(String path) {
    final running = _segmentOperation;
    if (running != null) return running;

    final operation = _handleSegmentSaved(path);
    _segmentOperation = operation;
    return operation.whenComplete(() {
      if (identical(_segmentOperation, operation)) {
        _segmentOperation = null;
      }
    });
  }

  Future<DiaryEntry?> _handleSegmentSaved(String path) async {
    var session = _requireSession();
    if (session.activeSegmentPath != path) {
      throw StateError('Saved segment does not match the active recording');
    }

    _updateState(_state.copyWith(status: RecordStatus.saving));
    final segmentDurationMs = await _safeSegmentDuration(path);
    final pending = List<String>.from(session.pendingSegmentPaths);
    if (!pending.contains(path)) pending.add(path);
    session = session.copyWith(
      pendingSegmentPaths: pending,
      activeSegmentPath: null,
      accumulatedDurationMs: session.accumulatedDurationMs + segmentDurationMs,
    );
    await _sessionStore.save(session);
    _session = session;
    _recordingStartedAt = null;

    try {
      session = await _consolidator.consolidate(session);
      _session = session;
      final metadata = await _mediaProbe(session.finalPath);
      final entry = DiaryEntry(
        path: session.finalPath,
        date: session.createdAt,
        thumbnailPath: metadata.thumbnailPath,
        durationMs: metadata.durationMs,
        fileBytes: metadata.fileBytes,
        lensDirection: session.lensDirection,
      );
      final waitingForResume = session.resumePending;
      _stopRequested = false;
      _updateState(
        _state.copyWith(
          status: waitingForResume
              ? RecordStatus.waitingForResume
              : RecordStatus.completed,
          videoPath: session.finalPath,
          errorMessage: null,
          sessionId: session.sessionId,
          recordedDurationMs: session.accumulatedDurationMs,
          resumePending: waitingForResume,
        ),
      );
      _diagnostics.log('segment_saved', session: session);
      return entry;
    } catch (error) {
      _stopRequested = false;
      _updateState(
        _state.copyWith(
          status: RecordStatus.error,
          errorMessage: error.toString(),
          recordedDurationMs: session.accumulatedDurationMs,
        ),
      );
      _diagnostics.log('merge_failed', session: session, error: error);
      rethrow;
    }
  }

  Future<bool> beginResumedSegment() async {
    final session = _session;
    if (session == null || !shouldAutoResume) return false;

    final updated = session.copyWith(resumePending: false);
    await _sessionStore.save(updated);
    _session = updated;
    _stopRequested = false;
    _updateState(
      _state.copyWith(
        status: RecordStatus.ready,
        resumePending: false,
        errorMessage: null,
      ),
    );
    _diagnostics.log('resume_prepared', session: updated);
    return true;
  }

  Future<void> handleCaptureFailure(Object error) async {
    final session = _session;
    _stopRequested = false;
    _recordingStartedAt = null;
    _updateState(
      _state.copyWith(
        status: RecordStatus.error,
        errorMessage: error.toString(),
        resumePending: session?.resumePending ?? false,
      ),
    );
    _diagnostics.log('capture_failed', session: session, error: error);
  }

  Future<void> confirmEntryPersisted() async {
    final session = _session;
    if (session == null) return;

    final updated = session.copyWith(entryRegistered: true);
    await _sessionStore.save(updated);
    _session = updated;
    if (_state.status == RecordStatus.completed) {
      await _sessionStore.delete(updated.sessionId);
      _session = null;
    }
  }

  Future<String?> discardSession() async {
    final session = _session;
    if (session == null) return null;
    _diagnostics.log('session_discarded', session: session);

    final paths = <String>{
      session.finalPath,
      '${session.finalPath}.merging',
      ...session.pendingSegmentPaths,
      if (session.activeSegmentPath != null) session.activeSegmentPath!,
    };
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } on FileSystemException {
          // Recovery metadata is still removed only after owned files are tried.
        }
      }
    }
    await _sessionStore.delete(session.sessionId);
    _session = null;
    _stopRequested = false;
    _recordingStartedAt = null;
    _updateState(
      _state.copyWith(
        status: RecordStatus.ready,
        videoPath: null,
        errorMessage: null,
        sessionId: null,
        recordedDurationMs: 0,
        resumePending: false,
      ),
    );
    return session.finalPath;
  }

  // Compatibility wrappers used by the current recording page until its
  // lifecycle adapter is switched to the session API.
  Future<String?> prepareRecording({
    required Future<bool> Function() onRequireStorageLocation,
  }) async {
    final path = await beginSession();
    if (path != null) {
      _recordingStartedAt = _now();
      _updateState(_state.copyWith(status: RecordStatus.recording));
    }
    return path;
  }

  Future<DiaryEntry?> onVideoSaved(String savedFilePath) async {
    final session = _requireSession();
    if (session.activeSegmentPath == null) {
      await registerActiveSegment(savedFilePath);
    }
    if (!_stopRequested) await requestUserFinalize();
    return handleSegmentSaved(savedFilePath);
  }

  void setRecordingStarted() {
    _recordingStartedAt = _now();
    _updateState(_state.copyWith(status: RecordStatus.recording));
  }

  void setReady() {
    _recordingStartedAt = null;
    _updateState(_state.copyWith(status: RecordStatus.ready));
  }

  RecordingSession _requireSession() {
    final session = _session;
    if (session == null) throw StateError('No recording session is active');
    return session;
  }

  Future<Directory> _defaultSessionRootProvider() async {
    final root = await _storageService.getInternalDiaryFolder();
    return Directory(_join(root.path, 'recording_sessions'));
  }

  Future<int> _safeSegmentDuration(String path) async {
    try {
      return await _segmentDurationProbe(path);
    } catch (_) {
      final startedAt = _recordingStartedAt;
      if (startedAt == null) return 0;
      return _now().difference(startedAt).inMilliseconds.clamp(0, 1 << 31);
    }
  }

  Future<int> _probeSegmentDuration(String path) async =>
      await _probeDurationMs(path) ?? 0;

  Future<RecordingMediaMetadata> _probeMedia(String path) async {
    final root = await _storageService.getInternalDiaryFolder();
    final thumbnailPath = await vt.VideoThumbnail.thumbnailFile(
      video: path,
      thumbnailPath: _join(root.path, 'thumbnails'),
      imageFormat: vt.ImageFormat.PNG,
      maxHeight: 200,
      quality: 70,
    );
    return RecordingMediaMetadata(
      thumbnailPath: thumbnailPath,
      durationMs: await _probeDurationMs(path) ?? 0,
      fileBytes: await File(path).length(),
    );
  }

  Future<int?> _probeDurationMs(String path) async {
    try {
      final player = await _videoService.createPlayer(path);
      try {
        return player.value.duration.inMilliseconds;
      } finally {
        await player.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}

String _defaultSessionId(DateTime createdAt) =>
    'recording-${createdAt.microsecondsSinceEpoch}';

String _fileNameFor(DateTime date, String sessionId) {
  final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(date);
  final safeSessionId = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return 'diary_${timestamp}_$safeSessionId.mp4';
}

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';
