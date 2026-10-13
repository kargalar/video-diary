import 'package:permission_handler/permission_handler.dart';

typedef PermissionRequest = Future<bool> Function();

class PermissionGateway {
  PermissionGateway({
    PermissionRequest? requestCamera,
    PermissionRequest? requestMicrophone,
  }) : _requestCamera = requestCamera ?? _requestCameraPermission,
       _requestMicrophone = requestMicrophone ?? _requestMicrophonePermission;

  final PermissionRequest _requestCamera;
  final PermissionRequest _requestMicrophone;

  Future<bool> requestRecordingPermissions() async {
    final results = await Future.wait([_requestCamera(), _requestMicrophone()]);
    return results.every((granted) => granted);
  }
}

Future<bool> _requestCameraPermission() async =>
    (await Permission.camera.request()).isGranted;

Future<bool> _requestMicrophonePermission() async =>
    (await Permission.microphone.request()).isGranted;
