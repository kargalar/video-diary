import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../viewmodel/diary_view_model.dart';
import 'compact_calendar.dart';

class TopActionButtons extends StatelessWidget {
  const TopActionButtons({super.key});

  void _showCalendarBottomSheet(BuildContext context, DiaryViewModel vm) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16, top: 16, left: 4, right: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CompactCalendar(entries: vm.entries, currentStreak: vm.currentStreak, vm: vm)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DiaryViewModel>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left: Streak Button
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => _showCalendarBottomSheet(context, vm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Theme.of(context).dividerColor.withAlpha(128)),
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      '${vm.currentStreak} day${vm.currentStreak != 1 ? 's' : ''}',
                      style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Right: Settings Button
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => AppRoutes.goToSettings(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).dividerColor.withAlpha(128)),
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Icon(Icons.settings, color: Theme.of(context).iconTheme.color, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
