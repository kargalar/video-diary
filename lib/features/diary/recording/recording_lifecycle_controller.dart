import 'package:flutter/widgets.dart';

typedef RecordingLifecycleCheck = bool Function();
typedef RecordingLifecycleAction = Future<void> Function();

class RecordingLifecycleController {
  RecordingLifecycleController({
    required RecordingLifecycleCheck isRecording,
    required RecordingLifecycleCheck shouldResume,
    required RecordingLifecycleAction stopForBackground,
    required RecordingLifecycleAction resumeRecording,
  }) : _isRecording = isRecording,
       _shouldResume = shouldResume,
       _stopForBackground = stopForBackground,
       _resumeRecording = resumeRecording;

  final RecordingLifecycleCheck _isRecording;
  final RecordingLifecycleCheck _shouldResume;
  final RecordingLifecycleAction _stopForBackground;
  final RecordingLifecycleAction _resumeRecording;

  bool _wasBackgrounded = false;
  bool _backgroundStopRequested = false;
  bool _resumeInProgress = false;

  Future<void> onLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        await _handleBackground();
      case AppLifecycleState.resumed:
        await _handleResume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        return;
    }
  }

  Future<void> _handleBackground() async {
    _wasBackgrounded = true;
    if (_backgroundStopRequested || !_isRecording()) return;

    _backgroundStopRequested = true;
    try {
      await _stopForBackground();
    } catch (_) {
      _backgroundStopRequested = false;
      rethrow;
    }
  }

  Future<void> _handleResume() async {
    if (!_wasBackgrounded || !_shouldResume() || _resumeInProgress) return;

    _resumeInProgress = true;
    try {
      await _resumeRecording();
      _wasBackgrounded = false;
      _backgroundStopRequested = false;
    } finally {
      _resumeInProgress = false;
    }
  }
}
