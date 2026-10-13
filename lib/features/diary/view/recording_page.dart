import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/widgets/swipe_to_pop.dart';
import '../recording/recording_lifecycle_controller.dart';
import '../viewmodel/diary_view_model.dart';
import '../viewmodel/record_state.dart';
import '../viewmodel/record_view_model.dart';
import 'recording_timer.dart';

class RecordingPage extends StatefulWidget {
  static const route = '/record';
  const RecordingPage({super.key});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage>
    with WidgetsBindingObserver {
  bool _isStopping = false;
  CameraState? _cameraState;
  Completer<void>? _videoModeCompleter;
  late final RecordingLifecycleController _lifecycleController;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _discardAfterFinalize = false;
  bool _startInProgress = false;
  bool _isLensReady = false;
  Object? _startFailure;
  BuildContext? _landscapeDialogContext;
  StreamSubscription? _accelSubscription;
  bool _isLandscapeDetected = false;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleController = RecordingLifecycleController(
      isRecording: () =>
          mounted && context.read<RecordViewModel>().state.isRecording,
      shouldResume: () =>
          mounted && context.read<RecordViewModel>().shouldAutoResume,
      stopForBackground: _stopForBackground,
      resumeRecording: _resumeAfterBackground,
    );
    WakelockPlus.enable();
    _initPreferences();

    _accelSubscription = accelerometerEventStream().listen((event) {
      if (!mounted) return;

      // If phone is mostly upright
      if (event.y.abs() > 6.0) {
        if (_isLandscapeDetected || _landscapeDialogContext == null) {
          _isLandscapeDetected = false;
          _showLandscapeWarningIfNeeded();
        }
      }
      // If phone is mostly horizontal
      else if (event.x.abs() > 6.0) {
        if (!_isLandscapeDetected) {
          _isLandscapeDetected = true;
          if (_landscapeDialogContext != null) {
            Navigator.of(_landscapeDialogContext!).pop();
            _landscapeDialogContext = null;
          }
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _accelSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (Platform.isAndroid) {
      unawaited(_handleLifecycleState(state));
    }
  }

  Future<void> _handleLifecycleState(AppLifecycleState state) async {
    try {
      await _lifecycleController.onLifecycleState(state);
    } catch (error) {
      await _handleCaptureFailure(error);
    }
  }

  void _dismissLandscapeDialog() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
    if (_landscapeDialogContext != null) {
      Navigator.of(_landscapeDialogContext!).pop();
      _landscapeDialogContext = null;
      _isDialogShowing = false;
    }
  }

  void _showLandscapeWarningIfNeeded() {
    if (_isDialogShowing) return; // dialog already showing or requested
    _isDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _landscapeDialogContext = ctx;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.elasticOut,
                    builder: (_, value, child) => Transform.rotate(
                      angle: (1.0 - value) * (3.14159 / 2),
                      child: child,
                    ),
                    child: const Icon(
                      Icons.stay_primary_landscape_rounded,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Rotate Your Phone',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'For best results, hold your phone horizontally (landscape mode) while recording.',
                    style: TextStyle(
                      color: Colors.white.withAlpha(178),
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    key: const ValueKey('continue_portrait_button'),
                    onPressed: _dismissLandscapeDialog,
                    child: const Text('Continue anyway'),
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      _isDialogShowing = false;
      _landscapeDialogContext = null;
    });
  }

  Future<void> _initPreferences() async {
    final vm = context.read<RecordViewModel>();
    try {
      await vm.ensurePreferredLensLoaded();
    } finally {
      if (mounted) setState(() => _isLensReady = true);
    }
  }

  Future<void> _stopForBackground() async {
    if (!mounted) return;
    final vm = context.read<RecordViewModel>();
    if (!await vm.requestLifecycleFinalize()) return;
    if (mounted) setState(() => _isStopping = true);
    await _stopNativeRecording();
  }

  Future<void> _resumeAfterBackground() async {
    if (!mounted) return;
    final vm = context.read<RecordViewModel>();
    if (!await vm.beginResumedSegment()) return;
    await _waitForVideoMode();
    await _startNativeSegment(vm);
    if (mounted) setState(() => _isStopping = false);
  }

  Future<void> _waitForVideoMode() async {
    if (_isCameraInVideoMode()) return;
    final completer = _videoModeCompleter ??= Completer<void>();
    await completer.future.timeout(const Duration(seconds: 5));
  }

  bool _isCameraInVideoMode() {
    var isVideoMode = false;
    _cameraState?.when(onVideoMode: (_) => isVideoMode = true);
    return isVideoMode;
  }

  void _setCameraState(CameraState cameraState) {
    _cameraState = cameraState;
    cameraState.when(
      onVideoMode: (_) {
        final completer = _videoModeCompleter;
        if (completer != null && !completer.isCompleted) completer.complete();
        _videoModeCompleter = null;
      },
    );
  }

  Future<void> _startNativeSegment(RecordViewModel vm) async {
    Future<CaptureRequest>? startOperation;
    _startFailure = null;
    _startInProgress = true;
    _cameraState?.when(
      onVideoMode: (videoState) {
        startOperation = videoState.startRecording();
      },
    );

    try {
      final operation = startOperation;
      if (operation == null) {
        throw StateError('Camera is not ready to record.');
      }
      final request = await operation;
      if (_startFailure != null) return;
      final path = request.path;
      if (path == null || path.isEmpty) {
        throw StateError('Camera did not provide a recording path.');
      }
      await vm.registerActiveSegment(path);
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> _stopNativeRecording() async {
    Future<void>? stopOperation;
    _cameraState?.when(
      onVideoRecordingMode: (recordingState) {
        stopOperation = recordingState.stopRecording();
      },
    );
    final operation = stopOperation;
    if (operation == null) {
      throw StateError('Camera is not currently recording.');
    }
    await operation;
  }

  Future<void> _handleCaptureFailure(Object error) async {
    if (_startInProgress) _startFailure = error;
    if (!mounted) return;
    final vm = context.read<RecordViewModel>();
    await vm.handleCaptureFailure(error);
    if (!mounted) return;
    setState(() => _isStopping = false);
    _showRecordingError(vm.state.errorMessage ?? error.toString());
  }

  Future<void> _handleSegmentSuccess(MediaCapture event) async {
    final savedPath = event.captureRequest.path;
    if (savedPath == null || !mounted) {
      if (mounted) {
        await _handleCaptureFailure(
          StateError('Camera completed without a saved video path.'),
        );
      }
      return;
    }

    final vm = context.read<RecordViewModel>();
    try {
      final entry = await vm.handleSegmentSaved(savedPath);
      if (!mounted || entry == null) return;

      if (_discardAfterFinalize) {
        _discardAfterFinalize = false;
        await _discardAndExit(entry.path);
        return;
      }

      final diaryViewModel = context.read<DiaryViewModel>();
      await diaryViewModel.upsertEntry(entry);
      await vm.confirmEntryPersisted();
      if (!mounted) return;
      setState(() => _isStopping = false);

      if (vm.state.status == RecordStatus.waitingForResume) {
        if (_lifecycleState == AppLifecycleState.resumed) {
          await _lifecycleController.onLifecycleState(
            AppLifecycleState.resumed,
          );
        }
        return;
      }

      if (vm.state.status == RecordStatus.completed) {
        _dismissLandscapeDialog();
        Navigator.of(context).pop(entry.path);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isStopping = false);
      _showRecordingError(error.toString());
    }
  }

  void _showRecordingError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message.replaceFirst('Exception: ', ''),
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _startNewSession(RecordViewModel vm) async {
    try {
      final path = await vm.beginSession();
      if (path == null) {
        _showRecordingError(
          vm.state.errorMessage ?? 'Camera permission was not granted.',
        );
        return;
      }
      await _waitForVideoMode();
      await _startNativeSegment(vm);
      if (mounted) setState(() {});
    } catch (error) {
      await vm.handleCaptureFailure(error);
      _showRecordingError(error.toString());
    }
  }

  Future<void> _handleSwipeBack() async {
    if (_isStopping) return;
    final vm = context.read<RecordViewModel>();
    if (vm.state.sessionId != null) {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete video?'),
          content: const Text('The recorded video will be deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (shouldDelete == true && mounted) {
        if (vm.state.isRecording) {
          _discardAfterFinalize = true;
          if (await vm.requestUserFinalize()) {
            setState(() => _isStopping = true);
            await _stopNativeRecording();
          }
        } else {
          await _discardAndExit(vm.state.videoPath);
        }
      }
    } else {
      if (!mounted) return;
      _dismissLandscapeDialog();
      Navigator.of(context).pop();
    }
  }

  Future<void> _discardAndExit(String? videoPath) async {
    final vm = context.read<RecordViewModel>();
    final path = videoPath ?? vm.state.videoPath;
    await vm.discardSession();
    if (path != null && mounted) {
      await context.read<DiaryViewModel>().deleteByPath(path);
    }
    if (!mounted) return;
    _dismissLandscapeDialog();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RecordViewModel>();

    return SafeArea(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_isStopping) return;
          _handleSwipeBack();
        },
        child: SwipeToPop(
          direction: SwipeDirection.leftToRight,
          onSwipe: _handleSwipeBack,
          child: Scaffold(
            appBar: null,
            backgroundColor: Colors.black,
            resizeToAvoidBottomInset: false,
            body: Column(
              children: [
                // Camera preview
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 35,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20.0),
                        child: _buildCameraPreview(vm),
                      ),
                    ),
                  ),
                ),

                // Controls at the bottom
                _buildControls(vm),

                SizedBox(height: 25),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview(RecordViewModel vm) {
    if (!_isLensReady) {
      return const Center(child: CircularProgressIndicator());
    }
    return CameraAwesomeBuilder.custom(
      previewFit: CameraPreviewFit.cover,
      saveConfig: SaveConfig.video(
        mirrorFrontCamera: true,
        videoOptions: VideoOptions(enableAudio: true),
      ),
      sensorConfig: SensorConfig.single(
        sensor: vm.state.isFrontCamera
            ? Sensor.position(SensorPosition.front)
            : Sensor.position(SensorPosition.back),
        aspectRatio: CameraAspectRatios.ratio_16_9,
      ),
      onMediaCaptureEvent: (event) {
        if (!event.isVideo) return;
        switch (event.status) {
          case MediaCaptureStatus.capturing:
            return;
          case MediaCaptureStatus.failure:
            unawaited(
              _handleCaptureFailure(
                event.exception ?? Exception('Camera recording failed.'),
              ),
            );
          case MediaCaptureStatus.success:
            unawaited(_handleSegmentSuccess(event));
        }
      },
      builder: (cameraState, preview) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _cameraState != cameraState) {
            setState(() {
              _setCameraState(cameraState);
            });
          }
        });
        return const SizedBox.shrink(key: ValueKey('camera_ready'));
      },
    );
  }

  Widget _buildControls(RecordViewModel vm) {
    final showTimer =
        vm.state.status == RecordStatus.recording ||
        vm.state.status == RecordStatus.finalizing ||
        vm.state.status == RecordStatus.saving;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // Left spacer (balances the right side)
          const Expanded(child: SizedBox()),

          // Record button — always centered
          _buildRecordButton(vm),

          // Right side: switch camera or timer
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 50),
                child: RotatedBox(
                  quarterTurns: 1,
                  child: !showTimer
                      ? Material(
                          color: Colors.black45,
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Switch camera',
                            icon: const Icon(
                              Icons.cameraswitch,
                              color: Colors.white,
                            ),
                            iconSize: 28,
                            onPressed: _isStopping || _cameraState == null
                                ? null
                                : () async {
                                    final oldDir =
                                        vm.state.preferredLensDirection;
                                    final newDir = vm.state.isFrontCamera
                                        ? 'back'
                                        : 'front';
                                    await vm.savePreferredLens(newDir);
                                    if (!mounted || _cameraState == null) {
                                      return;
                                    }
                                    if (vm.state.preferredLensDirection !=
                                        oldDir) {
                                      _cameraState!.switchCameraSensor();
                                    }
                                  },
                          ),
                        )
                      : RecordingTimer(
                          recordedDuration: Duration(
                            milliseconds: vm.state.recordedDurationMs,
                          ),
                          activeSegmentStartedAt: vm.recordingStartedAt,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordButton(RecordViewModel vm) {
    final isRec = vm.state.isRecording;
    final controlsLocked =
        vm.state.status == RecordStatus.finalizing ||
        vm.state.status == RecordStatus.saving ||
        vm.state.status == RecordStatus.waitingForResume;
    return GestureDetector(
      key: const ValueKey('record_button'),
      onTap: _isStopping || controlsLocked || _cameraState == null
          ? null
          : () async {
              if (!isRec) {
                await _startNewSession(vm);
              } else {
                if (!await vm.requestUserFinalize()) return;
                setState(() => _isStopping = true);
                try {
                  await _stopNativeRecording();
                } catch (error) {
                  await _handleCaptureFailure(error);
                }
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 4),
          borderRadius: BorderRadius.circular(isRec ? 16 : 36),
        ),
        padding: const EdgeInsets.all(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(isRec ? 8 : 30),
          ),
        ),
      ),
    );
  }
}
