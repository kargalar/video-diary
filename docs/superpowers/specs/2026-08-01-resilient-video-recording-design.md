# Resilient Android Video Recording Design

## Goal

Make Android recording reliable across OS and device differences without recording in the background. When the app leaves the foreground, all footage captured so far must be finalized and retained. If the same app process returns to the recording screen, recording resumes automatically and the user receives one final video. If the process is later removed or killed, the already finalized footage remains recoverable as that day's diary entry.

## Scope

This change targets the Android recording path. Existing iOS behavior remains unchanged. It does not attempt to keep the camera or microphone active while the app is backgrounded.

Android cannot guarantee a callback when a process is force-stopped while it is still foregrounded. The design therefore finalizes at the first reliable `paused` or `hidden` lifecycle transition. Once that transition completes, removing the app from recents cannot discard the finalized footage.

## Recording Session Model

Each recording uses a durable session with these fields:

- `sessionId`: unique identifier.
- `createdAt`: diary date and recording start time.
- `finalPath`: stable path used by the diary entry.
- `segmentPaths`: finalized pieces not yet consolidated into `finalPath`.
- `lensDirection`: selected front or back camera.
- `resumePending`: whether recording should restart when the same recording screen resumes.
- `entryRegistered`: whether the stable path is already stored in the diary repository.

The session manifest is stored as JSON under `video_diary_data/pending/<sessionId>/session.json`. Updates use a temporary file followed by rename so a process death cannot leave partially written JSON.

## Lifecycle Behavior

### Start

The record button creates a durable session before starting CameraX. Camera and microphone are the only runtime permissions required. The recording output is a session segment in app-specific storage.

### Background

On the first Android `paused` or `hidden` event while recording:

1. An idempotent lifecycle guard prevents duplicate stop requests.
2. CameraAwesome stops and finalizes the current segment.
3. The successful segment is added to the durable manifest.
4. The segment is consolidated into the stable final video.
5. A provisional diary entry is created or refreshed at the stable path.
6. `resumePending` remains true while the recording page and process remain alive.
7. No camera or microphone foreground service is started.

Transient `inactive` events alone do not stop recording because permission dialogs, notification shade interactions, and other overlays can produce them.

### Resume

When the same recording page returns to `resumed`, it waits until CameraAwesome is back in video mode and automatically starts a new segment if `resumePending` is true. The timer represents total captured duration rather than wall-clock background time.

If Android recreated the process, the app recovers and publishes the saved session but does not automatically open the camera or begin recording.

### User Stop

The stop button finalizes the active segment, consolidates it with the stable video, refreshes duration and thumbnail metadata, marks the session complete, and removes the pending manifest and obsolete segment files. The existing edit sheet opens for the single diary entry.

### Discard

Explicit discard removes the stable video, pending segments, manifest, thumbnail, and provisional diary entry. Backgrounding never invokes discard.

## MP4 Consolidation

Android uses a small native `MediaExtractor` and `MediaMuxer` implementation exposed through a Flutter method channel. CameraX segments from one session use the same device, camera, quality selection, and codecs, allowing tracks to be copied without re-encoding.

Consolidation writes to `<finalPath>.merging`, validates that the result contains a video track and non-zero samples, then atomically replaces `finalPath`. The old stable file and all new segments remain untouched until replacement succeeds. Audio is copied when present; a missing audio track does not invalidate a video.

If track formats are incompatible or muxing fails, the application keeps every source segment and the manifest, reports a recoverable error, and retries during the next launch. It never deletes the only readable copy.

## Startup Recovery

After the diary repository is initialized, a recovery service scans pending manifests:

- A valid stable video is registered as the day's entry if it is missing.
- Remaining valid segments are consolidated into the stable video.
- Duration, size, and thumbnail are regenerated after a successful consolidation.
- Corrupt zero-byte temporary outputs are deleted, while source segments are retained.
- Completed sessions are cleaned only after the diary repository confirms the stable entry.

Recovery is idempotent so it is safe after repeated crashes or launches.

## Permission and Android Compatibility Changes

- The recording path requests only `CAMERA` and `RECORD_AUDIO`.
- Photo, video-library, and legacy storage permissions are removed from the record-button flow because recording uses app-specific storage.
- Media permissions needed for migration remain isolated to the migration/import feature rather than blocking camera use.
- The recording-only foreground service call and its camera/microphone service declarations are removed.
- CamerAwesome uses its adaptive/default video quality instead of forcing FHD.
- A missing preferred camera falls back from front to back when possible.

## Error Handling

Every `MediaCaptureStatus.failure` is handled. Start, finalize, storage, muxing, thumbnail, and recovery failures move the view model out of its recording/stopping state and display a concise message. Diagnostic logs include Android SDK, device model, session ID, lifecycle reason, selected lens, output path, CameraX finalize error code, and exception text without recording personal media contents.

CameraAwesome must not transition into `VideoRecordingCameraState` after native start fails. A failed stop returns the UI to a usable video state while retaining all files that may be recoverable.

## Component Boundaries

- `RecordingPage`: observes Android lifecycle, owns UI intent, and delegates session operations.
- `RecordViewModel`: exposes start, lifecycle-finalize, resume, user-stop, failure, and discard commands.
- `RecordingSessionStore`: atomically persists and loads pending session manifests.
- `VideoSegmentMerger`: Dart interface to Android native MP4 consolidation.
- `RecordingRecoveryService`: reconciles pending sessions with files and diary entries at startup.
- `PermissionGateway`: makes the camera/microphone permission policy independently testable.

## Testing

Automated Dart tests cover:

- Only camera and microphone permissions determine recording access.
- Repeated lifecycle events issue one finalize request.
- Background finalization retains a provisional entry and sets resume intent.
- Resume starts exactly one new segment.
- User stop produces one stable diary path across multiple segments.
- Capture failure resets state and retains recoverable files.
- Recovery is idempotent and never deletes source segments before successful replacement.

Android tests use fixture MP4 files to verify video-only and video-plus-audio concatenation, monotonic timestamps, non-zero output, and preservation of sources after an injected merge failure. Final verification includes Flutter unit tests, static analysis, debug and release Android builds, and a device lifecycle pass on Android 16 covering Home, resume, stop, and removal from recents.

## Acceptance Criteria

- No recording continues while the app is backgrounded.
- Footage finalized on background remains available after removal from recents or later process death.
- Returning to the same live recording screen resumes capture automatically.
- All segments from that session appear as one playable diary video.
- Denying photo, video-library, storage, or notification permission does not block recording.
- CameraX failures are visible and leave the recording screen usable.
- No original segment is deleted before a merged replacement and diary entry are confirmed.
