import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/recording/camera_lens_gateway.dart';

void main() {
  test(
    'falls back to back camera when preferred front is unavailable',
    () async {
      final gateway = CameraLensGateway(loadAvailable: () async => {'back'});

      expect(await gateway.resolvePreferred('front'), 'back');
    },
  );

  test('keeps front preference when both lenses exist', () async {
    final gateway = CameraLensGateway(
      loadAvailable: () async => {'front', 'back'},
    );

    expect(await gateway.resolvePreferred('front'), 'front');
  });

  test('keeps stored preference when the native query fails', () async {
    final gateway = CameraLensGateway(
      loadAvailable: () async => throw Exception('camera service unavailable'),
    );

    expect(await gateway.resolvePreferred('front'), 'front');
  });

  test('keeps stored preference when no lenses are reported', () async {
    final gateway = CameraLensGateway(loadAvailable: () async => const {});

    expect(await gateway.resolvePreferred('back'), 'back');
  });
}
