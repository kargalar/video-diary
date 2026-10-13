import 'package:camerawesome/src/orchestrator/video_recording_starter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not call onStarted when native start fails', () async {
    var started = false;
    Exception? failure;

    final result = await startVideoRecordingSafely(
      startNative: () async => throw Exception('encoder'),
      onFailure: (error) => failure = error,
      onStarted: () => started = true,
    );

    expect(result, isFalse);
    expect(started, isFalse);
    expect(failure.toString(), contains('encoder'));
  });

  test('calls onStarted only after native start succeeds', () async {
    final events = <String>[];

    final result = await startVideoRecordingSafely(
      startNative: () async => events.add('native'),
      onFailure: (_) => events.add('failure'),
      onStarted: () => events.add('started'),
    );

    expect(result, isTrue);
    expect(events, ['native', 'started']);
  });
}
