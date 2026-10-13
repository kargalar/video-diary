import 'dart:io';
import 'package:flutter/foundation.dart';

import '../features/diary/data/diary_repository.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/model/settings.dart';
import 'storage_service.dart';
import 'video_service.dart';

class MigrationService {
  static VoidCallback? onDataMigrated;

  final DiaryRepository diaryRepo;
  final SettingsRepository settingsRepo;
  final StorageService storageService;
  final VideoService videoService;

  MigrationService(this.diaryRepo, this.settingsRepo, this.storageService, this.videoService);

  /// Silently migrate old external videos to internal app storage.
  /// Runs in background without blocking UI.
  Future<void> runSilentMigration() async {
    try {
      debugPrint('[Migration] Starting silent migration...');

      final settings = await settingsRepo.load();
      if (settings.storageDirectory == null) {
        debugPrint('[Migration] No custom directory set, skipping migration.');
        return;
      }

      final oldBaseDir = settings.storageDirectory!;
      final newDir = await storageService.getInternalDiaryFolder();

      debugPrint('[Migration] Old base dir: $oldBaseDir');
      debugPrint('[Migration] New internal dir: ${newDir.path}');

      if (oldBaseDir == newDir.path) {
        debugPrint('[Migration] Already migrated or using same directory. Stopping.');
        return;
      }

      final entries = await diaryRepo.load();
      bool changed = false;
      final updatedEntries = entries.toList();

      int migratedVideos = 0;
      int migratedThumbs = 0;

      for (int i = 0; i < updatedEntries.length; i++) {
        final entry = updatedEntries[i];
        var path = entry.path;
        var thumbPath = entry.thumbnailPath;
        var entryChanged = false;

        if (path.startsWith(oldBaseDir)) {
          final file = File(path);
          if (await file.exists()) {
            debugPrint('[Migration] Moving video: $path');
            final filename = path.split(Platform.pathSeparator).last;
            final newPath = '${newDir.path}${Platform.pathSeparator}videos${Platform.pathSeparator}$filename';
            await videoService.moveVideoFile(path, newPath);
            path = newPath;
            entryChanged = true;
            migratedVideos++;
          }
        }

        if (thumbPath != null && thumbPath.startsWith(oldBaseDir)) {
          final file = File(thumbPath);
          if (await file.exists()) {
            debugPrint('[Migration] Moving thumb: $thumbPath');
            final filename = thumbPath.split(Platform.pathSeparator).last;
            final newThumbPath = '${newDir.path}${Platform.pathSeparator}thumbnails${Platform.pathSeparator}$filename';
            try {
              await file.rename(newThumbPath); // move
            } catch (_) {
              await file.copy(newThumbPath);
              await file.delete();
            }
            thumbPath = newThumbPath;
            entryChanged = true;
            migratedThumbs++;
          }
        }

        if (entryChanged) {
          changed = true;
          updatedEntries[i] = entry.copyWith(path: path, thumbnailPath: thumbPath);
        }
      }

      debugPrint('[Migration] Summary: $migratedVideos videos, $migratedThumbs thumbnails migrated.');

      if (changed) {
        debugPrint('[Migration] Saving updated paths to database...');
        await diaryRepo.save(updatedEntries);
        onDataMigrated?.call();
      }

      // Attempt to clean up the old directory
      final oldDir = Directory(oldBaseDir);
      if (await oldDir.exists()) {
        try {
          debugPrint('[Migration] Attempting to clean up old directory...');
          await oldDir.delete(recursive: true);
        } catch (e) {
          debugPrint('[Migration] Could not delete old directory (may be SAF protected): $e');
        }
      }

      // Important: clear the setting so it won't run again.
      debugPrint('[Migration] Clearing storageDirectory setting flag...');
      await settingsRepo.save(SettingsModel(storageDirectory: null, reminderHour: settings.reminderHour, reminderMinute: settings.reminderMinute, reminderEnabled: settings.reminderEnabled, landscape: settings.landscape, hasShownNotificationPrompt: settings.hasShownNotificationPrompt));

      debugPrint('[Migration] Finished successfully.');
    } catch (e) {
      debugPrint('[Migration] ERROR during migration: $e');
    }
  }
}
