import 'dart:io';

import 'package:flutter/material.dart';

class StackedThumbnails extends StatelessWidget {
  final List<dynamic> entries;

  const StackedThumbnails({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final thumbPaths = entries.take(3).where((e) => e.thumbnailPath != null).map((e) => e.thumbnailPath as String).toList();

    if (thumbPaths.isEmpty) {
      return Container(
        color: Colors.grey[200],
        child: Icon(Icons.videocam_outlined, size: 48, color: Colors.grey[400]),
      );
    }

    Widget buildThumb(String path) {
      return Image.file(File(path), fit: BoxFit.cover);
    }

    return Stack(
      children: [
        // Main thumbnail (full)
        Positioned.fill(child: buildThumb(thumbPaths[0])),
        // Second thumbnail (if exists) - small overlay at bottom right
        if (thumbPaths.length > 1)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(6), child: buildThumb(thumbPaths[1])),
            ),
          ),
        // Third thumbnail (if exists) - small overlay next to second
        if (thumbPaths.length > 2)
          Positioned(
            bottom: 8,
            right: 76,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(6), child: buildThumb(thumbPaths[2])),
            ),
          ),
      ],
    );
  }
}
