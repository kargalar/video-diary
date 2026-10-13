import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_diary/features/diary/view/recording_timer.dart';

void main() {
  testWidgets('timer adds active segment time to recorded duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingTimer(
            recordedDuration: const Duration(seconds: 10),
            activeSegmentStartedAt: DateTime(2026, 8, 1, 12),
            now: () => DateTime(2026, 8, 1, 12, 0, 5),
          ),
        ),
      ),
    );

    expect(find.text('00:15'), findsOneWidget);
  });

  testWidgets('timer excludes time spent without an active segment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingTimer(
            recordedDuration: const Duration(seconds: 10),
            activeSegmentStartedAt: null,
            now: () => DateTime(2026, 8, 1, 12, 10),
          ),
        ),
      ),
    );

    expect(find.text('00:10'), findsOneWidget);
  });

  testWidgets('timer refreshes while the active segment is recording', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 1, 12, 0, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordingTimer(
            recordedDuration: Duration.zero,
            activeSegmentStartedAt: DateTime(2026, 8, 1, 12),
            now: () => now,
          ),
        ),
      ),
    );
    expect(find.text('00:01'), findsOneWidget);

    now = DateTime(2026, 8, 1, 12, 0, 2);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:02'), findsOneWidget);
  });
}
