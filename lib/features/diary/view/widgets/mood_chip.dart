import 'package:flutter/material.dart';

import '../../model/mood.dart';

class MoodChip extends StatelessWidget {
  final Mood mood;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const MoodChip({super.key, required this.mood, required this.isSelected, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedBg = isDark ? Colors.white.withAlpha(20) : const Color(0xFFE0F7FA);
    final unselectedBg = isDark ? Colors.white.withAlpha(8) : const Color(0xFFF0F0F0);
    final selectedBorder = isDark ? Colors.white.withAlpha(60) : const Color(0xFF00BCD4);
    final unselectedBorder = isDark ? Colors.white.withAlpha(15) : Colors.transparent;
    final selectedTextColor = isDark ? Colors.white : const Color(0xFF006064);
    final unselectedTextColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected ? selectedBorder : unselectedBorder, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mood.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              mood.label,
              style: TextStyle(color: isSelected ? selectedTextColor : unselectedTextColor, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, fontSize: 13, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}
