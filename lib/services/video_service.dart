import 'dart:io';

import 'package:video_player/video_player.dart';

class VideoService {
  Future<VideoPlayerController> createPlayer(String filePath) async {
    final controller = VideoPlayerController.file(File(filePath));
    await controller.initialize();
    return controller;
  }

  /// Moves a recorded video file from source to target path.
  Future<void> moveVideoFile(String sourcePath, String targetPath) async {
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);

    // Ensure target directory exists
    await targetFile.parent.create(recursive: true);

    // Try to rename (move) first - faster and more efficient
    // If rename fails (cross-device), fall back to copy + delete
    try {
      await sourceFile.rename(targetPath);
    } catch (_) {
      await sourceFile.copy(targetPath);
      await sourceFile.delete();
    }
  }
}
