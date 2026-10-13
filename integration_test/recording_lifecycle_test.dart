import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:video_diary/features/diary/view/diary_page.dart';
import 'package:video_diary/features/diary/viewmodel/diary_view_model.dart';
import 'package:video_diary/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('background finalizes and resume continues one diary video', (
    tester,
  ) async {
    if (!Platform.isAndroid) {
      markTestSkipped('The recording lifecycle flow is Android-only.');
      return;
    }
    if (!await Permission.camera.isGranted ||
        !await Permission.microphone.isGranted) {
      markTestSkipped(
        'Grant camera and microphone permissions before running this test.',
      );
      return;
    }

    await app.main();
    await _waitForNativeWork(tester, const Duration(seconds: 2));

    final diaryContext = tester.element(find.byType(DiaryPage));
    final diaryViewModel = Provider.of<DiaryViewModel>(
      diaryContext,
      listen: false,
    );
    final initialCount = diaryViewModel.entries.length;

    await tester.tap(find.byKey(const ValueKey('record_fab')));
    await _waitForNativeWork(tester, const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('record_button')), findsOneWidget);

    final continuePortrait = find.byKey(
      const ValueKey('continue_portrait_button'),
    );
    if (continuePortrait.evaluate().isNotEmpty) {
      await tester.tap(continuePortrait);
      await tester.pump();
    }

    await _waitForWidget(
      tester,
      find.byKey(const ValueKey('camera_ready')),
      const Duration(seconds: 15),
    );

    await tester.tap(find.byKey(const ValueKey('record_button')));
    await _waitForNativeWork(tester, const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('recording_timer')), findsOneWidget);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _waitForNativeWork(tester, const Duration(seconds: 3));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _waitForNativeWork(tester, const Duration(seconds: 3));

    expect(find.byKey(const ValueKey('recording_timer')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('record_button')));
    await _waitForNativeWork(tester, const Duration(seconds: 5));

    expect(diaryViewModel.entries.length, initialCount + 1);
    final entry = diaryViewModel.entries.first;
    final video = File(entry.path);
    expect(await video.exists(), isTrue);
    expect(await video.length(), greaterThan(0));
    expect(
      diaryViewModel.entries.where((item) => item.path == entry.path),
      hasLength(1),
    );
  });
}

Future<void> _waitForNativeWork(WidgetTester tester, Duration duration) async {
  await Future<void>.delayed(duration);
  await tester.pump();
}

Future<void> _waitForWidget(
  WidgetTester tester,
  Finder finder,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await _waitForNativeWork(tester, const Duration(milliseconds: 250));
  }
  expect(finder, findsOneWidget);
}
