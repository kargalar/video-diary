import 'package:flutter/services.dart';

typedef AvailableLensLoader = Future<Set<String>> Function();

class CameraLensGateway {
  CameraLensGateway({AvailableLensLoader? loadAvailable})
    : _loadAvailable = loadAvailable ?? _loadAvailableFromPlatform;

  final AvailableLensLoader _loadAvailable;

  Future<String> resolvePreferred(String preferred) async {
    final normalizedPreferred = preferred == 'back' ? 'back' : 'front';
    try {
      final available = await _loadAvailable();
      if (available.isEmpty || available.contains(normalizedPreferred)) {
        return normalizedPreferred;
      }
      if (available.contains('back')) return 'back';
      if (available.contains('front')) return 'front';
      return normalizedPreferred;
    } catch (_) {
      return normalizedPreferred;
    }
  }
}

Future<Set<String>> _loadAvailableFromPlatform() async {
  const channel = MethodChannel('app.videodiary/recording');
  final values = await channel.invokeListMethod<String>(
    'availableCameraLenses',
  );
  return (values ?? const <String>[])
      .where((lens) => lens == 'front' || lens == 'back')
      .toSet();
}
