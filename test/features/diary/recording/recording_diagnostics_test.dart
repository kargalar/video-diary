import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/recording/recording_diagnostics.dart';
import 'package:video_diary/features/diary/recording/recording_session.dart';

void main() {
  test('diagnostic line contains device and session context', () {
    final lines = <String>[];
    final diagnostics = RecordingDiagnostics(
      androidSdk: 36,
      deviceModel: 'test-device',
      sink: lines.add,
    );
    final session = RecordingSession.create(
      sessionId: 's1',
      createdAt: DateTime.utc(2026, 8, 1),
      finalPath: '/private/final.mp4',
      lensDirection: 'back',
    );

    diagnostics.log(
      'capture_failed',
      session: session,
      lifecycleReason: 'paused',
      error: Exception('encoder'),
    );

    expect(
      lines.single,
      allOf(<Matcher>[
        contains('event=capture_failed'),
        contains('sdk=36'),
        contains('model=test-device'),
        contains('session=s1'),
        contains('reason=paused'),
        contains('lens=back'),
        contains('output=/private/final.mp4'),
        contains('encoder'),
      ]),
    );
  });

  test('diagnostics do not read video contents', () {
    final lines = <String>[];
    final session = RecordingSession.create(
      sessionId: 'missing-file-session',
      createdAt: DateTime.utc(2026, 8, 1),
      finalPath: '/path/that/does/not/exist.mp4',
      lensDirection: 'front',
    );

    RecordingDiagnostics(
      androidSdk: 24,
      deviceModel: 'old-device',
      sink: lines.add,
    ).log('session_started', session: session);

    expect(lines.single, contains('session=missing-file-session'));
  });
}
