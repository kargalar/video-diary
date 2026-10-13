import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/recording/recording_lifecycle_controller.dart';

void main() {
  test('inactive does not finalize but paused does', () async {
    var stops = 0;
    final controller = RecordingLifecycleController(
      isRecording: () => true,
      shouldResume: () => false,
      stopForBackground: () async => stops++,
      resumeRecording: () async {},
    );

    await controller.onLifecycleState(AppLifecycleState.inactive);
    await controller.onLifecycleState(AppLifecycleState.paused);
    await controller.onLifecycleState(AppLifecycleState.hidden);

    expect(stops, 1);
  });

  test('resumed invokes continuation once after segment finalizes', () async {
    var resumes = 0;
    var resumable = false;
    final controller = RecordingLifecycleController(
      isRecording: () => true,
      shouldResume: () => resumable,
      stopForBackground: () async {},
      resumeRecording: () async => resumes++,
    );

    await controller.onLifecycleState(AppLifecycleState.paused);
    await controller.onLifecycleState(AppLifecycleState.resumed);
    expect(resumes, 0);

    resumable = true;
    await controller.onLifecycleState(AppLifecycleState.resumed);
    await controller.onLifecycleState(AppLifecycleState.resumed);

    expect(resumes, 1);
  });

  test('resumed without a prior background transition does nothing', () async {
    var resumes = 0;
    final controller = RecordingLifecycleController(
      isRecording: () => true,
      shouldResume: () => true,
      stopForBackground: () async {},
      resumeRecording: () async => resumes++,
    );

    await controller.onLifecycleState(AppLifecycleState.resumed);

    expect(resumes, 0);
  });
}
