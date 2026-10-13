Future<bool> startVideoRecordingSafely({
  required Future<void> Function() startNative,
  required void Function(Exception error) onFailure,
  required void Function() onStarted,
}) async {
  try {
    await startNative();
  } on Exception catch (error) {
    onFailure(error);
    return false;
  }

  onStarted();
  return true;
}
