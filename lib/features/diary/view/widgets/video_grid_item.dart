import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../model/mood.dart';
import '../player_page.dart';
import 'video_edit_bottom_sheet.dart';

class VideoGridItem extends StatelessWidget {
  final dynamic entry;
  final Function(Map<String, dynamic> updates) onEdit;
  final VoidCallback onDelete;

  const VideoGridItem({super.key, required this.entry, required this.onEdit, required this.onDelete});

  // Check if video file exists at the specified path
  bool _videoExists() {
    final path = entry.path as String;
    return File(path).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = entry.path as String;
    final date = entry.date as DateTime;
    final thumb = entry.thumbnailPath as String?;
    final title = entry.title as String?;
    final description = entry.description as String?;
    final moods = (entry.moods as List<Mood>?) ?? [];
    final rating = entry.rating as int?;

    return Slidable(
      key: ValueKey(path),
      startActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [SlidableAction(onPressed: (context) => _openEditBottomSheet(context), backgroundColor: Colors.blue, foregroundColor: Colors.white, icon: Icons.edit, label: 'Edit', borderRadius: BorderRadius.circular(16))],
      ),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [SlidableAction(onPressed: (context) => onDelete(), backgroundColor: Colors.red, foregroundColor: Colors.white, icon: Icons.delete, label: 'Delete', borderRadius: BorderRadius.circular(16))],
      ),
      child: GestureDetector(
        onTap: () {
          // Only allow navigation if video file exists
          if (_videoExists()) {
            AppRoutes.goToPlayer(context, PlayerPageArgs(path: path, title: title, lensDirection: entry.lensDirection as String?));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Video file not found. It may have been moved or deleted.'), backgroundColor: Colors.red, duration: Duration(seconds: 2)));
          }
        },
        onLongPress: () => _openEditBottomSheet(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Thumbnail - full container
                Positioned.fill(
                  child: thumb != null && _videoExists()
                      ? Image.file(File(thumb), fit: BoxFit.cover)
                      : Container(
                          color: Colors.grey[200],
                          child: !_videoExists()
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.warning_rounded, size: 48, color: Colors.red[300]),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(
                                        'Video konumda yok',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 12, color: Colors.red[400], fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                )
                              : Icon(Icons.videocam_outlined, size: 48, color: Colors.grey[400]),
                        ),
                ),
                // Gradient overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withAlpha(150)], stops: const [0.5, 1.0]),
                    ),
                  ),
                ),
                // Info overlay at bottom
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        Text(
                          title?.isNotEmpty == true ? title! : 'Untitled',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Description
                        if (description?.isNotEmpty == true) ...[
                          const SizedBox(height: 3),
                          Text(
                            description!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white60,
                              shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        // Date, Moods and Rating - Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Date
                            Text(
                              _formatDate(date),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                                shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                              ),
                            ),
                            // Moods and Rating
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Moods
                                if (moods.isNotEmpty) Wrap(spacing: 2, children: moods.map((mood) => Text(mood.emoji, style: const TextStyle(fontSize: 14))).toList()),
                                // Rating
                                if ((rating ?? 0) > 0) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.amber.withAlpha(230), borderRadius: BorderRadius.circular(8)),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star, size: 12, color: Colors.white),
                                        const SizedBox(width: 2),
                                        Text(
                                          '$rating',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditBottomSheet(BuildContext context) async {
    final title = entry.title as String?;
    final description = entry.description as String?;
    final rating = entry.rating as int?;
    final moods = (entry.moods as List<Mood>?) ?? [];
    final date = entry.date as DateTime?;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: VideoEditBottomSheet(currentTitle: title ?? '', currentDescription: description, currentRating: rating, currentMoods: moods, currentDate: date),
      ),
    );

    if (result != null) {
      onEdit(result);
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(d.year, d.month, d.day);

    if (dateOnly == today) {
      return 'Today ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    if (dateOnly == yesterday) {
      return 'Yesterday';
    }

    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthName = monthNames[d.month - 1];

    if (d.year == now.year) {
      return '${d.day} $monthName';
    }

    return '${d.day} $monthName ${d.year}';
  }
}
