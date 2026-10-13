import 'package:flutter/material.dart';

class StarRatingBar extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onRatingChanged;

  const StarRatingBar({super.key, required this.rating, required this.onRatingChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedColor = isDark ? Colors.white.withAlpha(25) : Colors.grey[200]!;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // Stars
        ...List.generate(5, (index) {
          final starValue = index + 1;
          final isSelected = starValue <= rating;
          return GestureDetector(
            onTap: () => onRatingChanged(starValue),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: Icon(isSelected ? Icons.star_rounded : Icons.star_outline_rounded, size: 36, color: isSelected ? Colors.amber[500] : unselectedColor),
            ),
          );
        }),
        // Clear button
        if (rating > 0)
          GestureDetector(
            onTap: () => onRatingChanged(0),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: isDark ? Colors.white.withAlpha(10) : Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.grey[600] : Colors.grey[500]),
              ),
            ),
          ),
      ],
    );
  }
}
