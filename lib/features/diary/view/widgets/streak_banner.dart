import 'package:flutter/material.dart';

class StreakBanner extends StatelessWidget {
  final int current;
  final int max;
  const StreakBanner({super.key, required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasStreak = current > 0 || max > 0;
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 250),
      crossFadeState: hasStreak
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      firstChild: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Icon(
                Icons.local_fire_department_outlined,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$current days',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    max > 0
                        ? 'Best: $max days'
                        : 'Keep your daily streak going',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w300,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      secondChild: const SizedBox.shrink(),
    );
  }
}
