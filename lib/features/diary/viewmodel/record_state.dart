const _notProvided = Object();

enum RecordStatus {
  initial,
  initializing,
  ready,
  recording,
  paused,
  saving,
  finalizing,
  waitingForResume,
  completed,
  error,
}

class RecordState {
  const RecordState({
    this.status = RecordStatus.initial,
    this.preferredLensDirection = 'front',
    this.hasPermission = true,
    this.remainingSeconds = 0,
    this.videoPath,
    this.errorMessage,
    this.sessionId,
    this.recordedDurationMs = 0,
    this.resumePending = false,
  });

  final RecordStatus status;
  final String preferredLensDirection;
  final bool hasPermission;
  final int remainingSeconds;
  final String? videoPath;
  final String? errorMessage;
  final String? sessionId;
  final int recordedDurationMs;
  final bool resumePending;

  bool get isRecording => status == RecordStatus.recording;
  bool get isPaused => status == RecordStatus.paused;
  bool get isReady => status == RecordStatus.ready;
  bool get isFrontCamera => preferredLensDirection == 'front';

  RecordState copyWith({
    RecordStatus? status,
    String? preferredLensDirection,
    bool? hasPermission,
    int? remainingSeconds,
    Object? videoPath = _notProvided,
    Object? errorMessage = _notProvided,
    Object? sessionId = _notProvided,
    int? recordedDurationMs,
    bool? resumePending,
  }) {
    return RecordState(
      status: status ?? this.status,
      preferredLensDirection:
          preferredLensDirection ?? this.preferredLensDirection,
      hasPermission: hasPermission ?? this.hasPermission,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      videoPath: identical(videoPath, _notProvided)
          ? this.videoPath
          : videoPath as String?,
      errorMessage: identical(errorMessage, _notProvided)
          ? this.errorMessage
          : errorMessage as String?,
      sessionId: identical(sessionId, _notProvided)
          ? this.sessionId
          : sessionId as String?,
      recordedDurationMs: recordedDurationMs ?? this.recordedDurationMs,
      resumePending: resumePending ?? this.resumePending,
    );
  }
}
