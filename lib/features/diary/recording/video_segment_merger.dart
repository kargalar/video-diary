import 'package:flutter/services.dart';

abstract interface class VideoSegmentMerger {
  Future<void> merge({
    required List<String> inputs,
    required String outputPath,
  });
}

class MethodChannelVideoSegmentMerger implements VideoSegmentMerger {
  const MethodChannelVideoSegmentMerger();

  static const _channel = MethodChannel('app.videodiary/recording');

  @override
  Future<void> merge({
    required List<String> inputs,
    required String outputPath,
  }) async {
    if (inputs.length < 2) {
      throw ArgumentError.value(
        inputs,
        'inputs',
        'At least two video segments are required',
      );
    }
    if (outputPath.isEmpty) {
      throw ArgumentError.value(outputPath, 'outputPath', 'must not be empty');
    }

    try {
      await _channel.invokeMethod<void>('mergeVideoSegments', {
        'inputs': List<String>.unmodifiable(inputs),
        'outputPath': outputPath,
      });
    } on PlatformException catch (error) {
      throw VideoMergeException(
        error.code,
        error.message ?? 'Video segments could not be merged',
      );
    }
  }
}

class VideoMergeException implements Exception {
  const VideoMergeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'VideoMergeException($code): $message';
}
