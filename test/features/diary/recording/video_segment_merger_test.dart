import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/recording/video_segment_merger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.videodiary/recording');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sends ordered absolute paths to Android', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    await const MethodChannelVideoSegmentMerger().merge(
      inputs: const ['/a.mp4', '/b.mp4'],
      outputPath: '/merged.mp4',
    );

    expect(calls.single.method, 'mergeVideoSegments');
    expect(calls.single.arguments, {
      'inputs': ['/a.mp4', '/b.mp4'],
      'outputPath': '/merged.mp4',
    });
  });

  test('rejects fewer than two input paths without channel call', () async {
    var wasCalled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          wasCalled = true;
          return null;
        });

    await expectLater(
      const MethodChannelVideoSegmentMerger().merge(
        inputs: const ['/a.mp4'],
        outputPath: '/merged.mp4',
      ),
      throwsArgumentError,
    );
    expect(wasCalled, isFalse);
  });

  test('preserves native platform error code', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'VIDEO_MERGE_INVALID_INPUT',
            message: 'Track formats differ',
          );
        });

    await expectLater(
      const MethodChannelVideoSegmentMerger().merge(
        inputs: const ['/a.mp4', '/b.mp4'],
        outputPath: '/merged.mp4',
      ),
      throwsA(
        isA<VideoMergeException>()
            .having((error) => error.code, 'code', 'VIDEO_MERGE_INVALID_INPUT')
            .having(
              (error) => error.message,
              'message',
              'Track formats differ',
            ),
      ),
    );
  });
}
