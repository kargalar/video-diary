import 'dart:io';

import 'package:path_provider/path_provider.dart';

class StorageService {
  Future<Directory> getInternalDiaryFolder() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final baseDir = '${docsDir.path}${Platform.pathSeparator}video_diary_data';
    return ensureDiaryFolder(baseDir);
  }

  Future<Directory> ensureDiaryFolder(String baseDir) async {
    final d = Directory(baseDir);
    if (!await d.exists()) {
      await d.create(recursive: true);
    }

    // Create videos and thumbnails subdirectories
    final videosDir = Directory('${d.path}${Platform.pathSeparator}videos');
    final thumbsDir = Directory('${d.path}${Platform.pathSeparator}thumbnails');

    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }
    if (!await thumbsDir.exists()) {
      await thumbsDir.create(recursive: true);
    }

    return d;
  }
}
