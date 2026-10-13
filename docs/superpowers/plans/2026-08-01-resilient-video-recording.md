# Resilient Android Video Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve all Android footage when the app backgrounds, automatically continue the same live session on resume, and publish the result as one recoverable diary video.

**Architecture:** Recording becomes a durable session state machine. CameraX writes short finalized segments; a Dart session/consolidation layer persists progress and invokes a small native Android `MediaExtractor`/`MediaMuxer` bridge to maintain one stable MP4. The page reacts to lifecycle and capture events, while startup recovery reconciles any session interrupted by process death.

**Tech Stack:** Flutter/Dart, Provider/ChangeNotifier, Hive, CamerAwesome/CameraX 1.4.2, Android Kotlin, `MediaExtractor`, `MediaMuxer`, Flutter method channels, `flutter_test`, AndroidX instrumentation tests.

## Global Constraints

- Android `minSdkVersion` remains 24 and `targetSdkVersion` remains Flutter's current target (36 in the verified merged manifest).
- No camera or microphone recording continues while the app is backgrounded.
- Camera and microphone are the only runtime permissions that may block recording.
- Do not add FFmpeg or another transcoding dependency.
- Use app-specific storage; never require shared-storage permission to record.
- Never delete the only readable video or segment before a consolidated replacement and diary entry are confirmed.
- Existing iOS recording behavior remains unchanged.
- A process recreated from disk recovers footage but never starts the camera automatically.

---

## File Map

- `lib/features/diary/recording/recording_session.dart`: immutable durable session model.
- `lib/features/diary/recording/recording_session_store.dart`: atomic JSON manifest persistence.
- `lib/features/diary/recording/video_segment_merger.dart`: platform-neutral merge interface and method-channel implementation.
- `lib/features/diary/recording/recording_consolidator.dart`: safe first-segment promotion and atomic multi-segment replacement.
- `lib/features/diary/recording/recording_recovery_service.dart`: startup reconciliation and diary upsert.
- `lib/features/diary/recording/permission_gateway.dart`: testable camera/microphone policy.
- `lib/features/diary/recording/camera_lens_gateway.dart`: preferred-lens availability and fallback.
- `lib/features/diary/recording/recording_diagnostics.dart`: structured, injectable recording diagnostics.
- `android/app/src/main/kotlin/com/example/video_diary/VideoSegmentMerger.kt`: native MP4 track copy.
- `android/app/src/main/kotlin/com/example/video_diary/MainActivity.kt`: platform channel and lens query.
- `lib/features/diary/viewmodel/record_view_model.dart`: session state machine orchestration.
- `lib/features/diary/view/recording_page.dart`: lifecycle and capture-event UI adapter.
- `lib/features/diary/view/recording_timer.dart`: accumulated captured-time display.
- `lib/features/diary/data/diary_repository.dart`: path-based durable upsert/remove.
- `lib/features/diary/viewmodel/diary_view_model.dart`: in-memory path-based upsert.
- `lib/core/di/service_locator.dart`: dependency wiring and recovery.
- `lib/core/di/recording_dependencies.dart`: testable construction of the shared recording service graph.

---

### Task 1: Durable Recording Session and Atomic Store

**Files:**
- Create: `lib/features/diary/recording/recording_session.dart`
- Create: `lib/features/diary/recording/recording_session_store.dart`
- Create: `test/features/diary/recording/recording_session_store_test.dart`

**Interfaces:**
- Consumes: `dart:io`, `dart:convert`.
- Produces:
  - `RecordingSession.create(...)`
  - `RecordingSession.copyWith(...)`
  - `RecordingSession.toJson()` / `RecordingSession.fromJson(...)`
  - `RecordingSessionStore.save(...)`, `load(...)`, `loadAll()`, `delete(...)`

- [ ] **Step 1: Write the failing model/store tests**

```dart
test('round-trips every recovery field', () {
  final session = RecordingSession(
    sessionId: 's1',
    createdAt: DateTime.utc(2026, 8, 1, 12),
    finalPath: '/data/final.mp4',
    pendingSegmentPaths: const ['/data/part-1.mp4'],
    activeSegmentPath: '/cache/active.mp4',
    lensDirection: 'front',
    resumePending: true,
    entryRegistered: false,
    accumulatedDurationMs: 1234,
  );

  expect(RecordingSession.fromJson(session.toJson()), session);
});

test('save is atomic and loadAll ignores merging temp files', () async {
  final root = await Directory.systemTemp.createTemp('recording-store-');
  addTearDown(() => root.delete(recursive: true));
  final store = RecordingSessionStore(rootProvider: () async => root);
  final session = RecordingSession.create(
    sessionId: 's1',
    createdAt: DateTime.utc(2026, 8, 1),
    finalPath: '${root.path}/final.mp4',
    lensDirection: 'back',
  );

  await store.save(session);
  await File('${root.path}/ignored.tmp').writeAsString('{broken');

  expect(await store.load('s1'), session);
  expect(await store.loadAll(), [session]);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/features/diary/recording/recording_session_store_test.dart`

Expected: FAIL because `RecordingSession` and `RecordingSessionStore` do not exist.

- [ ] **Step 3: Implement the immutable session model**

```dart
class RecordingSession {
  const RecordingSession({
    required this.sessionId,
    required this.createdAt,
    required this.finalPath,
    required this.pendingSegmentPaths,
    required this.activeSegmentPath,
    required this.lensDirection,
    required this.resumePending,
    required this.entryRegistered,
    required this.accumulatedDurationMs,
  });

  factory RecordingSession.create({
    required String sessionId,
    required DateTime createdAt,
    required String finalPath,
    required String lensDirection,
  }) => RecordingSession(
    sessionId: sessionId,
    createdAt: createdAt,
    finalPath: finalPath,
    pendingSegmentPaths: const [],
    activeSegmentPath: null,
    lensDirection: lensDirection,
    resumePending: false,
    entryRegistered: false,
    accumulatedDurationMs: 0,
  );

  final String sessionId;
  final DateTime createdAt;
  final String finalPath;
  final List<String> pendingSegmentPaths;
  final String? activeSegmentPath;
  final String lensDirection;
  final bool resumePending;
  final bool entryRegistered;
  final int accumulatedDurationMs;
}
```

Implement value equality manually so tests do not add another dependency. `copyWith` must support clearing `activeSegmentPath` with a private sentinel rather than `value ?? oldValue`.

- [ ] **Step 4: Implement atomic manifest storage**

Store each manifest at `<root>/<sessionId>/session.json`. Write `<session.json.tmp>`, flush, then rename to `session.json`. `loadAll()` enumerates only directories containing a valid `session.json`; it catches malformed JSON per session and leaves the directory untouched for diagnostics.

- [ ] **Step 5: Run Task 1 tests and verify GREEN**

Run: `flutter test test/features/diary/recording/recording_session_store_test.dart`

Expected: PASS, with no temp manifest remaining after `save`.

- [ ] **Step 6: Commit Task 1**

```bash
git add lib/features/diary/recording/recording_session.dart lib/features/diary/recording/recording_session_store.dart test/features/diary/recording/recording_session_store_test.dart
git commit -m "feat: persist recording sessions atomically"
```

---

### Task 2: Native Android MP4 Segment Merger

**Files:**
- Create: `lib/features/diary/recording/video_segment_merger.dart`
- Create: `test/features/diary/recording/video_segment_merger_test.dart`
- Create: `android/app/src/main/kotlin/com/example/video_diary/VideoSegmentMerger.kt`
- Modify: `android/app/src/main/kotlin/com/example/video_diary/MainActivity.kt`
- Modify: `android/app/build.gradle.kts`
- Create: `android/app/src/androidTest/kotlin/app/videodiary/VideoSegmentMergerTest.kt`
- Create: `android/app/src/androidTest/assets/segment_a.mp4`
- Create: `android/app/src/androidTest/assets/segment_b.mp4`

**Interfaces:**
- Consumes: absolute readable MP4 input paths and a distinct output path.
- Produces:
  - `abstract interface class VideoSegmentMerger { Future<void> merge({required List<String> inputs, required String outputPath}); }`
  - `MethodChannelVideoSegmentMerger` using channel `app.videodiary/recording` and method `mergeVideoSegments`.
  - `VideoSegmentMerger.merge(inputs: List<File>, output: File)` in Kotlin.

- [ ] **Step 1: Write the failing Dart channel contract test**

```dart
TestWidgetsFlutterBinding.ensureInitialized();

test('sends ordered absolute paths to Android', () async {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('app.videodiary/recording'), (call) async {
    calls.add(call);
    return null;
  });

  await const MethodChannelVideoSegmentMerger().merge(
    inputs: const ['/a.mp4', '/b.mp4'],
    outputPath: '/merged.mp4',
  );

  expect(calls.single.method, 'mergeVideoSegments');
  expect(calls.single.arguments, {
    'inputs': ['/a.mp4', '/b.mp4'],
    'outputPath': '/merged.mp4',
  });
});
```

- [ ] **Step 2: Run the Dart test and verify RED**

Run: `flutter test test/features/diary/recording/video_segment_merger_test.dart`

Expected: FAIL because the merger interface does not exist.

- [ ] **Step 3: Implement the Dart interface and channel adapter**

Reject fewer than two inputs with `ArgumentError`; allow the consolidation layer to promote a single file without invoking native code. Convert `PlatformException` to `VideoMergeException(code, message)` while preserving the native error code.

- [ ] **Step 4: Generate deterministic test fixtures**

Run these commands from the repository root:

```powershell
New-Item -ItemType Directory -Force android/app/src/androidTest/assets | Out-Null
ffmpeg -y -f lavfi -i color=c=red:s=320x240:d=0.5 -f lavfi -i sine=frequency=440:duration=0.5 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest android/app/src/androidTest/assets/segment_a.mp4
ffmpeg -y -f lavfi -i color=c=blue:s=320x240:d=0.5 -f lavfi -i sine=frequency=660:duration=0.5 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest android/app/src/androidTest/assets/segment_b.mp4
```

The fixtures are short, contain H.264 video plus AAC audio, and have identical track formats.

- [ ] **Step 5: Write the failing Android instrumentation tests**

```kotlin
@RunWith(AndroidJUnit4::class)
class VideoSegmentMergerTest {
    @Test
    fun mergesTwoSegmentsWithMonotonicAudioAndVideoSamples() {
        val context = InstrumentationRegistry.getInstrumentation().context
        val output = File(context.cacheDir, "merged.mp4")
        val inputs = listOf(copyAsset("segment_a.mp4"), copyAsset("segment_b.mp4"))

        VideoSegmentMerger().merge(inputs, output)

        assertTrue(output.length() > inputs.maxOf { it.length() })
        assertTrackSamplesAreMonotonic(output, "video/")
        assertTrackSamplesAreMonotonic(output, "audio/")
    }

    @Test
    fun incompatibleInputKeepsSourcesAndRemovesPartialOutput() {
        val source = copyAsset("segment_a.mp4")
        val invalid = File(context.cacheDir, "invalid.mp4").apply { writeText("invalid") }
        val output = File(context.cacheDir, "failed.mp4")

        assertThrows(IllegalArgumentException::class.java) {
            VideoSegmentMerger().merge(listOf(source, invalid), output)
        }

        assertTrue(source.exists())
        assertTrue(invalid.exists())
        assertFalse(output.exists())
    }
}
```

Test helpers copy assets into the instrumentation cache, enumerate tracks with `MediaExtractor`, and assert each selected track's `sampleTime` is strictly non-decreasing.

- [ ] **Step 6: Configure instrumentation and verify RED**

Add to `defaultConfig`:

```kotlin
testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
```

Add dependencies:

```kotlin
androidTestImplementation("androidx.test:runner:1.6.2")
androidTestImplementation("androidx.test.ext:junit:1.2.1")
androidTestImplementation("junit:junit:4.13.2")
```

Run: `cd android; ./gradlew.bat app:connectedDebugAndroidTest --tests app.videodiary.VideoSegmentMergerTest`

Expected: FAIL because the native merger is missing.

- [ ] **Step 7: Implement track-safe native merging**

`VideoSegmentMerger.kt` must:

1. Validate at least two non-empty input files and a distinct output.
2. Read video/audio formats from the first input and add matching tracks to `MediaMuxer`.
3. Require matching MIME, video width/height, and audio sample-rate/channel-count in later inputs.
4. Copy samples with a reusable direct `ByteBuffer`, clearing codec-config flags and adding a cumulative segment time offset.
5. Preserve rotation with `MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION` and `muxer.setOrientationHint(...)`.
6. Call `stop()` only after at least one video sample is written.
7. Release every extractor/muxer in `finally`; delete partial output on failure; never delete inputs.

Use the following timestamp rule:

```kotlin
val adjustedTimeUs = segmentOffsetUs + maxOf(0L, extractor.sampleTime)
bufferInfo.set(0, sampleSize, adjustedTimeUs, extractor.sampleFlags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG.inv())
segmentDurationUs = maxOf(segmentDurationUs, extractor.sampleTime)
// After all tracks in the segment:
segmentOffsetUs += maxOf(1L, metadataDurationMs * 1000L, segmentDurationUs + 1L)
```

- [ ] **Step 8: Register the method channel**

Override `configureFlutterEngine` in `MainActivity` and dispatch `mergeVideoSegments` on `Dispatchers.IO`. Return `result.success(null)` on the main thread; map validation errors to `VIDEO_MERGE_INVALID_INPUT` and other failures to `VIDEO_MERGE_FAILED`.

- [ ] **Step 9: Run Dart and Android merger tests and verify GREEN**

Run:

```powershell
flutter test test/features/diary/recording/video_segment_merger_test.dart
Set-Location android
./gradlew.bat app:connectedDebugAndroidTest --tests app.videodiary.VideoSegmentMergerTest
```

Expected: all merger tests PASS and both source fixtures still exist after each test.

- [ ] **Step 10: Commit Task 2**

```bash
git add lib/features/diary/recording/video_segment_merger.dart test/features/diary/recording/video_segment_merger_test.dart android/app/src/main/kotlin/com/example/video_diary/MainActivity.kt android/app/src/main/kotlin/com/example/video_diary/VideoSegmentMerger.kt android/app/src/androidTest android/app/build.gradle.kts
git commit -m "feat: merge Android recording segments"
```

---

### Task 3: Safe Consolidation, Diary Upsert, and Startup Recovery

**Files:**
- Create: `lib/features/diary/recording/recording_consolidator.dart`
- Create: `lib/features/diary/recording/recording_recovery_service.dart`
- Modify: `lib/features/diary/data/diary_repository.dart`
- Modify: `lib/features/diary/viewmodel/diary_view_model.dart`
- Create: `test/features/diary/recording/recording_consolidator_test.dart`
- Create: `test/features/diary/recording/recording_recovery_service_test.dart`

**Interfaces:**
- Consumes: `RecordingSessionStore`, `VideoSegmentMerger`, `DiaryRepository`, `VideoService`, and a thumbnail/duration probe callback.
- Produces:
  - `RecordingConsolidator.consolidate(RecordingSession session) -> Future<RecordingSession>`
  - `RecordingRecoveryService.recover() -> Future<RecordingRecoveryReport>`
  - `DiaryRepository.upsertByPath(DiaryEntry entry)` and `removeByPath(String path)`
  - `DiaryViewModel.upsertEntry(DiaryEntry entry)`

- [ ] **Step 1: Write failing consolidation safety tests**

```dart
test('promotes first segment without native merge', () async {
  final session = sessionWithSegments(['/tmp/part1.mp4']);
  await File('/tmp/part1.mp4').writeAsBytes([1, 2, 3]);

  final result = await consolidator.consolidate(session);

  expect(await File(result.finalPath).readAsBytes(), [1, 2, 3]);
  expect(result.pendingSegmentPaths, isEmpty);
  expect(fakeMerger.calls, isEmpty);
});

test('merge failure preserves stable file, segment, and manifest', () async {
  fakeMerger.error = const VideoMergeException('failed', 'boom');
  final session = sessionWithStableAndPending();

  await expectLater(
    consolidator.consolidate(session),
    throwsA(isA<VideoMergeException>()),
  );
  expect(File(session.finalPath).existsSync(), isTrue);
  expect(File(session.pendingSegmentPaths.single).existsSync(), isTrue);
  expect(await store.load(session.sessionId), isNotNull);
});
```

Use `Directory.systemTemp` paths created per test; do not use literal `/tmp` on Windows in the final test implementation.

- [ ] **Step 2: Run consolidation tests and verify RED**

Run: `flutter test test/features/diary/recording/recording_consolidator_test.dart`

Expected: FAIL because `RecordingConsolidator` does not exist.

- [ ] **Step 3: Implement safe consolidation**

For the first segment, copy to `<finalPath>.merging`, flush, validate non-zero length, then replace `finalPath`. For later segments, call the native merger with `[finalPath, ...pending]` and the merging path. Only after replacement succeeds may pending source files be deleted and the manifest updated with an empty pending list.

- [ ] **Step 4: Write failing repository/recovery tests**

```dart
test('upsert replaces an existing path instead of duplicating it', () async {
  await repository.save([oldEntry]);
  await repository.upsertByPath(updatedEntry);
  final entries = await repository.load();
  expect(entries.where((entry) => entry.path == oldEntry.path), hasLength(1));
  expect(entries.single.fileBytes, updatedEntry.fileBytes);
});

test('recovery is idempotent and publishes one stable entry', () async {
  await store.save(interruptedSession);
  await recovery.recover();
  await recovery.recover();

  final entries = await repository.load();
  expect(entries.where((entry) => entry.path == interruptedSession.finalPath), hasLength(1));
  expect((await store.loadAll()), isEmpty);
});
```

Use a Hive test directory via `Hive.init(temp.path)` and close/delete boxes in teardown.

- [ ] **Step 5: Run recovery tests and verify RED**

Run: `flutter test test/features/diary/recording/recording_recovery_service_test.dart`

Expected: FAIL because path upsert and recovery do not exist.

- [ ] **Step 6: Implement repository upsert/remove and view-model upsert**

`DiaryRepository.upsertByPath` loads, replaces the matching path or inserts once, sorts descending by date, saves, and awaits persistence. `DiaryViewModel.upsertEntry` mirrors this behavior in memory and awaits the repository call before returning.

- [ ] **Step 7: Implement idempotent startup recovery**

For each manifest:

1. If `activeSegmentPath` exists and is non-zero, move it into `pendingSegmentPaths` and clear the active field.
2. Consolidate pending segments.
3. Probe final file size/duration and regenerate its thumbnail.
4. Upsert the stable `DiaryEntry` using `createdAt` and `lensDirection`.
5. Set `entryRegistered`, save, then delete the manifest only after repository persistence succeeds.
6. On any error, retain the manifest and source files and include the session ID/error in `RecordingRecoveryReport.failures`.

- [ ] **Step 8: Run all Task 3 tests and verify GREEN**

Run:

```powershell
flutter test test/features/diary/recording/recording_consolidator_test.dart
flutter test test/features/diary/recording/recording_recovery_service_test.dart
```

Expected: PASS; the second recovery run performs no duplicate insert or merge.

- [ ] **Step 9: Commit Task 3**

```bash
git add lib/features/diary/recording lib/features/diary/data/diary_repository.dart lib/features/diary/viewmodel/diary_view_model.dart test/features/diary/recording
git commit -m "feat: recover interrupted recording sessions"
```

---

### Task 4: Minimal Permissions, Foreground-Service Removal, and Lens Fallback

**Files:**
- Create: `lib/features/diary/recording/permission_gateway.dart`
- Create: `lib/features/diary/recording/camera_lens_gateway.dart`
- Create: `test/features/diary/recording/permission_gateway_test.dart`
- Create: `test/features/diary/recording/camera_lens_gateway_test.dart`
- Create: `lib/features/diary/recording/recording_diagnostics.dart`
- Create: `test/features/diary/recording/recording_diagnostics_test.dart`
- Modify: `android/app/src/main/kotlin/com/example/video_diary/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `lib/features/diary/viewmodel/record_view_model.dart`
- Modify: `lib/features/diary/view/recording_page.dart`

**Interfaces:**
- Produces:
  - `PermissionGateway.requestRecordingPermissions() -> Future<bool>`
  - `CameraLensGateway.resolvePreferred(String preferred) -> Future<String>`
  - `RecordingDiagnostics.log(String event, {RecordingSession? session, String? lifecycleReason, Object? error})`
  - Platform method `availableCameraLenses -> List<String>` containing `front` and/or `back`.

- [ ] **Step 1: Write failing permission tests**

```dart
test('recording access depends only on camera and microphone', () async {
  final gateway = PermissionGateway(
    requestCamera: () async => true,
    requestMicrophone: () async => true,
  );
  expect(await gateway.requestRecordingPermissions(), isTrue);
});

test('denied microphone blocks recording', () async {
  final gateway = PermissionGateway(
    requestCamera: () async => true,
    requestMicrophone: () async => false,
  );
  expect(await gateway.requestRecordingPermissions(), isFalse);
});
```

- [ ] **Step 2: Run permission tests and verify RED**

Run: `flutter test test/features/diary/recording/permission_gateway_test.dart`

Expected: FAIL because the gateway does not exist.

- [ ] **Step 3: Implement permission gateway and remove media requests**

The default gateway wraps `Permission.camera.request()` and `Permission.microphone.request()`. Delete `Permission.videos`, `Permission.photos`, and `Permission.storage` calls from `RecordViewModel`; do not add notification permission to this decision.

- [ ] **Step 4: Write failing lens fallback tests**

```dart
test('falls back to back camera when preferred front is unavailable', () async {
  final gateway = CameraLensGateway(loadAvailable: () async => {'back'});
  expect(await gateway.resolvePreferred('front'), 'back');
});

test('keeps front preference when both lenses exist', () async {
  final gateway = CameraLensGateway(loadAvailable: () async => {'front', 'back'});
  expect(await gateway.resolvePreferred('front'), 'front');
});
```

- [ ] **Step 5: Implement native lens query and Dart gateway**

Use Android `CameraManager.cameraIdList` and `CameraCharacteristics.LENS_FACING` in `MainActivity`. Return a de-duplicated list. If the platform call fails or returns empty, the gateway keeps the stored preference and lets CameraAwesome surface a visible initialization failure.

- [ ] **Step 6: Remove recording-only foreground service and fixed FHD**

Delete `startForegroundService`/`stopForegroundService` code from `RecordViewModel`, remove `FOREGROUND_SERVICE_CAMERA`, `FOREGROUND_SERVICE_MICROPHONE`, and the custom notification `ForegroundService` declaration from the app manifest. Keep reminder-related notification permissions. Replace:

```dart
VideoOptions(enableAudio: true, quality: VideoRecordingQuality.fhd)
```

with:

```dart
VideoOptions(enableAudio: true)
```

so CameraX selects its adaptive default quality.

- [ ] **Step 7: Write the failing structured diagnostics test**

```dart
test('diagnostic line contains device and session context', () {
  final lines = <String>[];
  final diagnostics = RecordingDiagnostics(
    androidSdk: 36,
    deviceModel: 'test-device',
    sink: lines.add,
  );

  diagnostics.log(
    'capture_failed',
    session: session,
    lifecycleReason: 'paused',
    error: Exception('encoder'),
  );

  expect(lines.single, allOf(
    contains('sdk=36'),
    contains('model=test-device'),
    contains('session=s1'),
    contains('reason=paused'),
    contains('encoder'),
  ));
});
```

- [ ] **Step 8: Run diagnostics test and verify RED**

Run: `flutter test test/features/diary/recording/recording_diagnostics_test.dart`

Expected: FAIL because `RecordingDiagnostics` does not exist.

- [ ] **Step 9: Implement diagnostics without media-content access**

Create the default instance once using `DeviceInfoPlugin().androidInfo`; inject `debugPrint` as the sink. Log only event name, SDK, model, session ID, lifecycle reason, lens, output path, and exception text. Never open or hash video contents for logging.

- [ ] **Step 10: Run Task 4 tests and manifest check**

Run:

```powershell
flutter test test/features/diary/recording/permission_gateway_test.dart test/features/diary/recording/camera_lens_gateway_test.dart test/features/diary/recording/recording_diagnostics_test.dart
flutter build apk --debug
rg "FOREGROUND_SERVICE_(CAMERA|MICROPHONE)|foregroundServiceType=\"camera" build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml
```

Expected: tests PASS, APK builds, and the final `rg` returns no match.

- [ ] **Step 11: Commit Task 4**

```bash
git add lib/features/diary/recording lib/features/diary/viewmodel/record_view_model.dart lib/features/diary/view/recording_page.dart android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/example/video_diary/MainActivity.kt test/features/diary/recording
git commit -m "fix: minimize Android recording permissions"
```

---

### Task 5: RecordViewModel Session State Machine

**Files:**
- Modify: `lib/features/diary/viewmodel/record_state.dart`
- Modify: `lib/features/diary/viewmodel/record_view_model.dart`
- Create: `test/features/diary/viewmodel/record_view_model_test.dart`

**Interfaces:**
- Consumes: `RecordingSessionStore`, `RecordingConsolidator`, `PermissionGateway`, `RecordingDiagnostics`, `StorageService`, `VideoService`.
- Produces:
  - `beginSession() -> Future<String?>` returning stable final path.
  - `registerActiveSegment(String path)` after CameraAwesome start.
  - `requestLifecycleFinalize() -> Future<bool>` returning whether native stop should be called.
  - `requestUserFinalize() -> Future<bool>` returning whether native stop should be called.
  - `handleSegmentSaved(String path) -> Future<DiaryEntry?>`.
  - `shouldAutoResume` and `beginResumedSegment()`.
  - `handleCaptureFailure(Object error)`.
  - `confirmEntryPersisted()` and `discardSession()`.
  - `@visibleForTesting RecordingSessionStore get sessionStore` for dependency graph verification.

- [ ] **Step 1: Write failing state-machine tests**

```dart
test('duplicate paused and hidden events request one stop', () async {
  await vm.beginSession();
  await vm.registerActiveSegment('/cache/part1.mp4');
  expect(await vm.requestLifecycleFinalize(), isTrue);
  expect(await vm.requestLifecycleFinalize(), isFalse);
});

test('saved background segment becomes resumable provisional entry', () async {
  await vm.beginSession();
  await vm.registerActiveSegment(segment.path);
  await vm.requestLifecycleFinalize();

  final entry = await vm.handleSegmentSaved(segment.path);

  expect(entry?.path, finalPath);
  expect(vm.state.status, RecordStatus.waitingForResume);
  expect(vm.shouldAutoResume, isTrue);
});

test('capture failure resets controls and preserves pending files', () async {
  await vm.beginSession();
  await vm.registerActiveSegment(segment.path);
  await vm.handleCaptureFailure(Exception('encoder failed'));

  expect(vm.state.status, RecordStatus.error);
  expect(vm.state.isRecording, isFalse);
  expect(segment.existsSync(), isTrue);
  expect(vm.state.errorMessage, contains('encoder failed'));
});

test('user finalize completes instead of scheduling resume', () async {
  await vm.beginSession();
  await vm.registerActiveSegment(segment.path);
  expect(await vm.requestUserFinalize(), isTrue);

  final entry = await vm.handleSegmentSaved(segment.path);

  expect(entry?.path, finalPath);
  expect(vm.state.status, RecordStatus.completed);
  expect(vm.shouldAutoResume, isFalse);
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/features/diary/viewmodel/record_view_model_test.dart`

Expected: FAIL because the durable session methods/statuses are absent.

- [ ] **Step 3: Extend `RecordState`**

Add `finalizing`, `waitingForResume`, and `completed` statuses plus `sessionId`, `recordedDurationMs`, and `resumePending`. Preserve explicit nullable clearing through sentinel parameters in `copyWith`.

- [ ] **Step 4: Implement one-operation-at-a-time orchestration**

Use a private `Future<void>? _finalizeOperation`/boolean guard so lifecycle, user stop, and capture events cannot race. `requestLifecycleFinalize` sets `resumePending=true` and persists before returning true. `requestUserFinalize` sets it false and persists before returning true. `handleSegmentSaved` verifies the path matches the active segment, moves it to pending, clears active, consolidates, probes metadata, and returns the stable-path entry. It enters `waitingForResume` when `resumePending` is true and `completed` otherwise.

After every `DiaryViewModel.upsertEntry` completes, the page calls `confirmEntryPersisted()`. That method marks `entryRegistered`; it retains the manifest for `waitingForResume` sessions and removes it only for `completed` sessions. `discardSession` deletes all session-owned files but never files from another session.

Emit diagnostics at session start, native start, lifecycle finalize request, segment success, merge success/failure, user stop, discard, and capture failure. Each call includes the current session and lifecycle reason when available.

- [ ] **Step 5: Run state-machine tests and verify GREEN**

Run: `flutter test test/features/diary/viewmodel/record_view_model_test.dart`

Expected: PASS with no duplicate stop/finalization and no source deletion on failure.

- [ ] **Step 6: Commit Task 5**

```bash
git add lib/features/diary/viewmodel/record_state.dart lib/features/diary/viewmodel/record_view_model.dart test/features/diary/viewmodel/record_view_model_test.dart
git commit -m "feat: orchestrate durable recording sessions"
```

---

### Task 6: Keep CamerAwesome in Video Mode After Start Failure

**Files:**
- Create: `packages/camerawesome_local/lib/src/orchestrator/video_recording_starter.dart`
- Create: `packages/camerawesome_local/test/orchestrator/video_recording_starter_test.dart`
- Modify: `packages/camerawesome_local/lib/src/orchestrator/states/video_camera_state.dart`
- Modify: `packages/camerawesome_local/android/src/main/kotlin/com/apparence/camerawesome/cameraX/CameraAwesomeX.kt`

**Interfaces:**
- Produces: `startVideoRecordingSafely({required Future<void> Function() startNative, required void Function(Exception) onFailure, required void Function() onStarted}) -> Future<bool>`.

- [ ] **Step 1: Write the failing helper behavior tests**

```dart
test('does not call onStarted when native start fails', () async {
  var started = false;
  Exception? failure;

  final result = await startVideoRecordingSafely(
    startNative: () async => throw Exception('encoder'),
    onFailure: (error) => failure = error,
    onStarted: () => started = true,
  );

  expect(result, isFalse);
  expect(started, isFalse);
  expect(failure.toString(), contains('encoder'));
});
```

- [ ] **Step 2: Run package test and verify RED**

Run: `flutter test packages/camerawesome_local/test/orchestrator/video_recording_starter_test.dart`

Expected: FAIL because `startVideoRecordingSafely` does not exist.

- [ ] **Step 3: Implement helper and use it in `VideoCameraState.startRecording`**

Only call `cameraContext.changeState(VideoRecordingCameraState.from(cameraContext))` through `onStarted`. On failure, emit `MediaCapture.failure` with the real exception and remain in `VideoCameraState`. Return the capture request so existing API signatures remain compatible; the page reacts to the emitted failure event.

Expand the native `VideoRecordEvent.Finalize` error log to include `event.error`, `event.cause`, and `event.outputResults.outputUri`. This is diagnostic-only and must not alter the finalize callback result.

- [ ] **Step 4: Run package and app tests and verify GREEN**

Run:

```powershell
flutter test packages/camerawesome_local/test/orchestrator/video_recording_starter_test.dart
flutter test test/features/diary/viewmodel/record_view_model_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 6**

```bash
git add packages/camerawesome_local/lib/src/orchestrator/video_recording_starter.dart packages/camerawesome_local/lib/src/orchestrator/states/video_camera_state.dart packages/camerawesome_local/android/src/main/kotlin/com/apparence/camerawesome/cameraX/CameraAwesomeX.kt packages/camerawesome_local/test/orchestrator/video_recording_starter_test.dart
git commit -m "fix: retain camera state after recording start failure"
```

---

### Task 7: Recording Page Lifecycle, Failure UI, and Accumulated Timer

**Files:**
- Modify: `lib/features/diary/view/recording_page.dart`
- Modify: `lib/features/diary/view/recording_timer.dart`
- Create: `test/features/diary/view/recording_lifecycle_controller_test.dart`
- Create: `lib/features/diary/recording/recording_lifecycle_controller.dart`
- Create: `test/features/diary/view/recording_timer_test.dart`

**Interfaces:**
- Consumes: `RecordViewModel` commands and CameraAwesome `CameraState`/`MediaCapture`.
- Produces: `RecordingLifecycleController.onLifecycleState(AppLifecycleState)` with injected `stopForBackground` and `resumeRecording` callbacks.

- [ ] **Step 1: Write failing lifecycle controller tests**

```dart
test('inactive does not finalize but paused does', () async {
  var stops = 0;
  final controller = RecordingLifecycleController(
    isRecording: () => true,
    stopForBackground: () async => stops++,
    resumeRecording: () async {},
  );

  await controller.onLifecycleState(AppLifecycleState.inactive);
  await controller.onLifecycleState(AppLifecycleState.paused);
  await controller.onLifecycleState(AppLifecycleState.hidden);

  expect(stops, 1);
});

test('resumed invokes continuation once after background finalize', () async {
  var resumes = 0;
  // paused, mark segment finalized, then emit resumed twice
  expect(resumes, 1);
});
```

The second test uses an injected `shouldResume` callback that changes from false to true after the simulated segment-success event.

- [ ] **Step 2: Run lifecycle tests and verify RED**

Run: `flutter test test/features/diary/view/recording_lifecycle_controller_test.dart`

Expected: FAIL because the controller does not exist.

- [ ] **Step 3: Implement lifecycle controller and page observer**

Make `_RecordingPageState` a `WidgetsBindingObserver`. Register/unregister it in `initState`/`dispose`. Delegate only Android `paused`, `hidden`, and `resumed` states. When background stop is required, call CameraAwesome `stopRecording`; do not navigate away when its success event arrives. On resume, wait for `onVideoMode` and call `startRecording`, then `registerActiveSegment` with the returned capture path.

The stop button first calls `requestUserFinalize()` and invokes CameraAwesome stop only when it returns true. The lifecycle controller uses `requestLifecycleFinalize()` in the same way, so both routes share the idempotent guard without sharing navigation behavior.

- [ ] **Step 4: Handle every capture status**

Replace the success-only callback with a `switch`:

```dart
switch (event.status) {
  case MediaCaptureStatus.capturing:
    return;
  case MediaCaptureStatus.failure:
    unawaited(_handleCaptureFailure(event.exception ?? Exception('Camera recording failed.')));
  case MediaCaptureStatus.success:
    unawaited(_handleSegmentSuccess(event));
}
```

`_handleSegmentSuccess` calls `handleSegmentSaved`, awaits `DiaryViewModel.upsertEntry`, and calls `confirmEntryPersisted`. It stays on the page when the view model enters `waitingForResume`; it pops to the edit sheet only when the view model enters `completed`. `_handleCaptureFailure` resets `_isStopping`, displays the view-model message, and leaves controls enabled.

- [ ] **Step 5: Write failing accumulated timer test**

```dart
testWidgets('timer excludes time spent in background', (tester) async {
  await tester.pumpWidget(MaterialApp(home: RecordingTimer(
    recordedDuration: const Duration(seconds: 10),
    activeSegmentStartedAt: DateTime(2026, 8, 1, 12),
    now: () => DateTime(2026, 8, 1, 12, 0, 5),
  )));
  expect(find.text('00:15'), findsOneWidget);
});
```

- [ ] **Step 6: Run timer test and verify RED**

Run: `flutter test test/features/diary/view/recording_timer_test.dart`

Expected: FAIL because the timer does not accept accumulated duration/clock injection.

- [ ] **Step 7: Implement accumulated timer and safe exit/discard**

Display `recordedDuration + (now - activeSegmentStartedAt)` only while an active segment exists. Swipe/back while recording asks for discard; confirmed discard first stops/finalizes, then removes the entire session and provisional diary entry. Normal background never opens a dialog and never discards.

- [ ] **Step 8: Run Task 7 tests and verify GREEN**

Run:

```powershell
flutter test test/features/diary/view/recording_lifecycle_controller_test.dart
flutter test test/features/diary/view/recording_timer_test.dart
flutter test test/features/diary/viewmodel/record_view_model_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit Task 7**

```bash
git add lib/features/diary/view/recording_page.dart lib/features/diary/view/recording_timer.dart lib/features/diary/recording/recording_lifecycle_controller.dart test/features/diary/view
git commit -m "feat: finalize and resume recordings across lifecycle"
```

---

### Task 8: Dependency Wiring, Recovery Startup, and Full Verification

**Files:**
- Modify: `lib/core/di/service_locator.dart`
- Create: `lib/core/di/recording_dependencies.dart`
- Modify: `lib/core/app.dart`
- Modify: `lib/features/diary/view/diary_page.dart`
- Modify: `test/widget_test.dart`
- Create: `integration_test/recording_lifecycle_test.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: all Task 1-7 services.
- Produces: fully wired `RecordViewModel`, startup `RecordingRecoveryService`, and a device lifecycle regression test.

- [ ] **Step 1: Write a failing wiring smoke test**

Replace the empty widget test with a service construction test using temporary/fake dependencies:

```dart
test('recording dependencies construct with one shared session store', () async {
  final graph = await buildRecordingDependencies(
    storageService: fakeStorage,
    diaryRepository: fakeDiaryRepository,
    videoService: fakeVideoService,
    merger: fakeMerger,
    permissionGateway: fakePermissions,
  );

  expect(graph.recordViewModel, isNotNull);
  expect(graph.recoveryService, isNotNull);
  expect(identical(graph.sessionStore, graph.recordViewModel.sessionStore), isTrue);
});
```

- [ ] **Step 2: Run smoke test and verify RED**

Run: `flutter test test/widget_test.dart`

Expected: FAIL because the recording dependency builder/wiring is absent.

- [ ] **Step 3: Wire services and run recovery before diary load**

Implement `RecordingDependencies` and `Future<RecordingDependencies> buildRecordingDependencies(...)` in `recording_dependencies.dart`. Construct one `RecordingSessionStore`, `MethodChannelVideoSegmentMerger`, `RecordingConsolidator`, `PermissionGateway`, `RecordingDiagnostics`, and `RecordingRecoveryService` in `ServiceLocator` through that builder. Await repository initialization and recovery in `setup()` before `runApp`. Inject the same instances into `RecordViewModel`. `DiaryPage.load()` then reads any recovered entry normally.

Add `integration_test` from the Flutter SDK under `dev_dependencies`:

```yaml
integration_test:
  sdk: flutter
```

- [ ] **Step 4: Write the device lifecycle regression flow**

`integration_test/recording_lifecycle_test.dart` must use visible UI semantics:

1. Tap `Record`.
2. Grant camera/microphone if the system asks.
3. Rotate as required and start recording.
4. Wait two seconds, send the app to background with the integration binding lifecycle API, and wait for finalization.
5. Resume and assert the timer resumes above the first segment's duration.
6. Record two more seconds and stop.
7. Assert one new diary tile exists and its video path is non-zero.

Mark the test with an Android-only guard; it must not auto-run camera operations on desktop.

- [ ] **Step 5: Run all automated verification**

Run:

```powershell
flutter test
flutter analyze
flutter build apk --debug
flutter build apk --release
Set-Location android
./gradlew.bat app:connectedDebugAndroidTest --tests app.videodiary.VideoSegmentMergerTest
```

Expected:

- All Dart and Android tests PASS.
- `flutter analyze` reports no new warnings/errors in modified files.
- Debug and release APK builds succeed.
- The merger instrumentation tests pass on the connected Android 16 device.

- [ ] **Step 6: Run the real-device lifecycle matrix**

On the connected Android 16 device, run the integration test, then manually verify:

- Home during recording stops camera/microphone privacy indicators.
- Resume automatically continues the same session.
- Stop creates one playable diary video containing both colored/time portions.
- Home followed by removal from recents leaves a playable entry after relaunch.
- Denying photos/videos/storage/notifications does not block camera recording.
- Revoking microphone produces a visible actionable error and responsive controls.

Capture filtered diagnostics if any case fails:

```powershell
adb logcat -d -v threadtime | Select-String -Pattern 'VideoDiaryRecording|Camerawesome|VideoRecordEvent|MediaMuxer|SecurityException'
```

- [ ] **Step 7: Confirm no accidental file loss and no unrelated changes**

Run:

```powershell
git status --short
git diff --check
git diff 88a5718..HEAD -- android/app/src/main/AndroidManifest.xml lib/features/diary packages/camerawesome_local/lib/src/orchestrator
```

Expected: only planned recording files differ; the pre-existing deletion of `ToDo.md` remains untouched.

- [ ] **Step 8: Commit Task 8**

```bash
git add lib/core/di/service_locator.dart lib/core/di/recording_dependencies.dart lib/core/app.dart lib/features/diary/view/diary_page.dart test/widget_test.dart integration_test/recording_lifecycle_test.dart pubspec.yaml pubspec.lock
git commit -m "test: verify resilient Android recording flow"
```

---

## Completion Gate

Before claiming completion, invoke `superpowers:verification-before-completion`, run every command in Task 8 Step 5, inspect outputs rather than relying on exit summaries, and perform the Android 16 lifecycle matrix. Then invoke `superpowers:requesting-code-review` and address all high- and medium-severity findings before handoff.
