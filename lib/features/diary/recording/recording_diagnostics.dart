import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'recording_session.dart';

typedef RecordingDiagnosticSink = void Function(String line);

class RecordingDiagnostics {
  const RecordingDiagnostics({
    required this.androidSdk,
    required this.deviceModel,
    required RecordingDiagnosticSink sink,
  }) : _sink = sink;

  final int? androidSdk;
  final String deviceModel;
  final RecordingDiagnosticSink _sink;

  static Future<RecordingDiagnostics> createDefault() async {
    if (!Platform.isAndroid) {
      return RecordingDiagnostics(
        androidSdk: null,
        deviceModel: Platform.operatingSystem,
        sink: (line) => debugPrint(line),
      );
    }

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return RecordingDiagnostics(
        androidSdk: info.version.sdkInt,
        deviceModel: '${info.manufacturer} ${info.model}'.trim(),
        sink: (line) => debugPrint(line),
      );
    } catch (error) {
      return RecordingDiagnostics(
        androidSdk: null,
        deviceModel: 'android-unknown',
        sink: (line) => debugPrint(line),
      );
    }
  }

  void log(
    String event, {
    RecordingSession? session,
    String? lifecycleReason,
    Object? error,
  }) {
    final fields = <String>[
      'VideoDiaryRecording',
      'event=${_singleLine(event)}',
      'sdk=${androidSdk ?? 'unknown'}',
      'model=${_singleLine(deviceModel)}',
      if (session != null) 'session=${_singleLine(session.sessionId)}',
      if (lifecycleReason != null) 'reason=${_singleLine(lifecycleReason)}',
      if (session != null) 'lens=${_singleLine(session.lensDirection)}',
      if (session != null) 'output=${_singleLine(session.finalPath)}',
      if (error != null) 'error=${_singleLine(error.toString())}',
    ];
    _sink(fields.join(' '));
  }
}

String _singleLine(String value) =>
    value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
