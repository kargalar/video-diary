import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/recording/permission_gateway.dart';

void main() {
  test('recording access depends only on camera and microphone', () async {
    var cameraRequests = 0;
    var microphoneRequests = 0;
    final gateway = PermissionGateway(
      requestCamera: () async {
        cameraRequests++;
        return true;
      },
      requestMicrophone: () async {
        microphoneRequests++;
        return true;
      },
    );

    expect(await gateway.requestRecordingPermissions(), isTrue);
    expect(cameraRequests, 1);
    expect(microphoneRequests, 1);
  });

  test('denied microphone blocks recording', () async {
    final gateway = PermissionGateway(
      requestCamera: () async => true,
      requestMicrophone: () async => false,
    );

    expect(await gateway.requestRecordingPermissions(), isFalse);
  });

  test('both permissions are requested when camera is denied', () async {
    var microphoneRequested = false;
    final gateway = PermissionGateway(
      requestCamera: () async => false,
      requestMicrophone: () async {
        microphoneRequested = true;
        return true;
      },
    );

    expect(await gateway.requestRecordingPermissions(), isFalse);
    expect(microphoneRequested, isTrue);
  });
}
