import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../viewmodel/diary_view_model.dart';
import '../../viewmodel/record_view_model.dart';
import '../../../settings/viewmodel/settings_view_model.dart';
import '../../../../services/video_review_service.dart';
import 'video_edit_bottom_sheet.dart';

class RecordFab extends StatelessWidget {
  const RecordFab({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DiaryViewModel>();
    final recordVm = context.read<RecordViewModel>();

    return GestureDetector(
      key: const ValueKey('record_fab'),
      onTap: () async {
        final hasPermissions = await recordVm.requestAndCheckPermissions();
        if (!hasPermissions) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Camera and microphone permissions are required to record videos.', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(label: 'Settings', onPressed: () => openAppSettings(), textColor: Colors.white),
            ),
          );
          return;
        }

        // ignore: use_build_context_synchronously
        final filePath = await AppRoutes.goToRecord(context);
        if (!context.mounted) return;

        if (filePath != null && filePath is String) {
          final latestEntry = vm.entries.isNotEmpty ? vm.entries.first : null;
          if (latestEntry == null) return;

          final result = await showModalBottomSheet<Map<String, dynamic>>(
            // ignore: use_build_context_synchronously
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            isDismissible: true,
            enableDrag: false,
            builder: (context) => PopScope(
              canPop: false,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: VideoEditBottomSheet(currentTitle: '', currentRating: null, currentMoods: const [], isNewVideo: true),
              ),
            ),
          );

          if (result != null) {
            var entryPath = latestEntry.path;

            if (result['discard'] == true) {
              await vm.deleteByPath(latestEntry.path);
              return;
            }

            final title = result['title'] as String?;
            final description = result['description'] as String?;
            final rating = result['rating'] as int?;
            final moods = result['moods'] as List<dynamic>?;

            if (title != null && title.trim().isNotEmpty) {
              final updatedPath = await vm.renameByPath(entryPath, title.trim());
              if (updatedPath != null) {
                entryPath = updatedPath;
              }
            }

            if (description != null && description.trim().isNotEmpty) {
              await vm.setDescriptionForEntry(entryPath, description.trim());
            }

            if (rating != null) {
              await vm.setRatingForEntry(entryPath, rating.clamp(1, 5));
            }

            if (moods != null && moods.isNotEmpty) {
              await vm.setMoodsForEntry(entryPath, moods.cast());
            }

            if (context.mounted) {
              final settingsVm = context.read<SettingsViewModel>();
              if (!settingsVm.state.hasShownNotificationPrompt) {
                final newSettings = settingsVm.state.copyWith(hasShownNotificationPrompt: true);
                await settingsVm.repo.save(newSettings);
                settingsVm.loadSettings();

                // ignore: use_build_context_synchronously
                if (context.mounted) {
                  final wantNotifications = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Daily Reminders'),
                      content: const Text('Would you like to receive daily reminders to record your video?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not Now')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: Colors.blue),
                          child: const Text('Enable'),
                        ),
                      ],
                    ),
                  );

                  if (wantNotifications == true && context.mounted) {
                    AppRoutes.goToSettings(context);
                  }
                }
              }
            }

            // ignore: use_build_context_synchronously
            if (context.mounted) {
              final reviewService = VideoReviewService();
              await reviewService.incrementVideoCountAndRequestReview();
            }
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 6)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 22),
            const SizedBox(width: 8),
            Text(
              'Record',
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
