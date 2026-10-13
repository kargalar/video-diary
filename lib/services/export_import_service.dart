import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_diary/features/settings/data/settings_repository.dart';
import 'package:video_diary/features/settings/model/settings.dart';

import '../features/diary/data/day_data_repository.dart';
import '../features/diary/data/diary_repository.dart';
import '../features/diary/data/mood_repository.dart';
import '../features/diary/model/diary_entry.dart';
import '../features/diary/model/mood.dart';

typedef ExportImportProgressCallback =
    void Function(double progress, String status);

class ExportImportService {
  static const int _currentSchemaVersion = 3;
  static const int _legacyExportVersion = 2;
  static const String _backupFormat = 'video_diary_backup';

  static const String _manifestPath = 'manifest.json';
  static const String _legacyMetaPath = 'export.json';
  static const String _entriesDataPath = 'data/diary.json';
  static const String _dayDataPath = 'data/day_data.json';
  static const String _moodsDataPath = 'data/moods.json';
  static const String _settingsDataPath = 'data/settings.json';
  static const String _preferencesDataPath = 'data/preferences.json';
  static const String _archiveVideosDir = 'media/videos';
  static const String _archiveThumbnailsDir = 'media/thumbnails';
  static const String _videosDir = 'videos';
  static const String _thumbsDir = 'thumbnails';

  // SharedPreferences keys treated as part of app data.
  static const String _prefCameraLensKey = 'preferred_camera_lens';
  static const String _prefRecordedVideoCountKey = 'recorded_video_count';
  static const String _prefReviewCompletedKey = 'review_completed';

  final DiaryRepository _diaryRepo = DiaryRepository();
  final DayDataRepository _dayRepo = DayDataRepository();
  final MoodRepository _moodRepo = MoodRepository();
  final SettingsRepository _settingsRepo = SettingsRepository();

  /// Creates a portable backup package. The package is a ZIP container, but
  /// its contents are versioned independently from the transport format.
  Future<String> exportData(
    String savePath, {
    ExportImportProgressCallback? onProgress,
  }) async {
    final outputFile = File(savePath);
    ZipFileEncoder? encoder;

    try {
      onProgress?.call(0.03, 'Preparing backup...');
      await outputFile.parent.create(recursive: true);
      if (await outputFile.exists()) await outputFile.delete();

      final entries = await _diaryRepo.load();
      await _dayRepo.init();
      final dayData = await _dayRepo.getAll();
      final settings = await _settingsRepo.load();
      final moods = await _moodRepo.load();
      final prefs = await SharedPreferences.getInstance();

      encoder = ZipFileEncoder();
      encoder.create(outputFile.path, level: ZipFileEncoder.store);

      final exportedEntries = <Map<String, dynamic>>[];
      final exportedFiles = <Map<String, dynamic>>[];
      final usedEntryIds = <String>{};

      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        if (!usedEntryIds.add(entry.id)) {
          throw FormatException('Duplicate diary entry id: ${entry.id}');
        }

        final progress =
            0.08 +
            (0.78 * ((index + 1) / (entries.isEmpty ? 1 : entries.length)));
        onProgress?.call(
          progress,
          'Preparing media (${index + 1}/${entries.length})...',
        );

        final assetStem = _safeAssetStem(entry.id);
        String? videoAssetPath;
        String? thumbnailAssetPath;

        if (entry.path.isNotEmpty) {
          final source = File(entry.path);
          if (await source.exists()) {
            videoAssetPath =
                '$_archiveVideosDir/$assetStem${_safeExtension(entry.path, '.mp4')}';
            exportedFiles.add(
              await _addAsset(
                encoder,
                source: source,
                archivePath: videoAssetPath,
                entryId: entry.id,
                kind: 'video',
              ),
            );
          }
        }

        final thumbnailPath = entry.thumbnailPath;
        if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
          final source = File(thumbnailPath);
          if (await source.exists()) {
            thumbnailAssetPath =
                '$_archiveThumbnailsDir/$assetStem${_safeExtension(thumbnailPath, '.jpg')}';
            exportedFiles.add(
              await _addAsset(
                encoder,
                source: source,
                archivePath: thumbnailAssetPath,
                entryId: entry.id,
                kind: 'thumbnail',
              ),
            );
          }
        }

        final entryJson = Map<String, dynamic>.from(entry.toJson())
          ..remove('path')
          ..remove('thumbnailPath')
          ..['videoAssetPath'] = videoAssetPath
          ..['thumbnailAssetPath'] = thumbnailAssetPath;
        exportedEntries.add(entryJson);
      }

      final settingsJson = Map<String, dynamic>.from(settings.toJson())
        // Absolute paths are device-specific and must never be restored.
        ..['storageDirectory'] = null;
      final prefsData = <String, dynamic>{
        _prefCameraLensKey: prefs.getString(_prefCameraLensKey),
        _prefRecordedVideoCountKey: prefs.getInt(_prefRecordedVideoCountKey),
        _prefReviewCompletedKey: prefs.getBool(_prefReviewCompletedKey),
      };

      _addJsonFile(encoder, _entriesDataPath, {'entries': exportedEntries});
      _addJsonFile(encoder, _dayDataPath, {
        for (final item in dayData.entries) item.key: item.value.toJson(),
      });
      _addJsonFile(encoder, _moodsDataPath, {
        'moods': moods.map((mood) => mood.toJson()).toList(),
      });
      _addJsonFile(encoder, _settingsDataPath, settingsJson);
      _addJsonFile(encoder, _preferencesDataPath, prefsData);

      final manifest = <String, dynamic>{
        'format': _backupFormat,
        'schemaVersion': _currentSchemaVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'totalVideos': entries.length,
        'data': {
          'entries': _entriesDataPath,
          'dayData': _dayDataPath,
          'moods': _moodsDataPath,
          'settings': _settingsDataPath,
          'preferences': _preferencesDataPath,
        },
        'files': exportedFiles,
      };
      _addJsonFile(encoder, _manifestPath, manifest);

      await encoder.close();
      encoder = null;
      onProgress?.call(1.0, 'Backup completed successfully.');
      debugPrint('Export successful: ${outputFile.path}');
      return outputFile.path;
    } catch (error) {
      debugPrint('Export error: $error');
      if (encoder != null) {
        try {
          await encoder.close();
        } catch (_) {}
      }
      if (await outputFile.exists()) {
        try {
          await outputFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Imports the current manifest-based package and legacy v2 ZIP files.
  /// All archive content is staged and verified before existing data changes.
  Future<int> importData(
    File backupFile,
    String restoreToDirectory, {
    bool replaceExisting = true,
    ExportImportProgressCallback? onProgress,
  }) async {
    InputFileStream? input;
    Directory? stagingDirectory;

    try {
      onProgress?.call(0.03, 'Validating backup file...');
      if (!await backupFile.exists()) {
        throw Exception('Backup file not found: ${backupFile.path}');
      }

      final restoreDirectory = Directory(restoreToDirectory);
      await restoreDirectory.create(recursive: true);
      stagingDirectory = Directory(
        _resolveInside(restoreDirectory.path, '.import-${_newOperationId()}'),
      );
      await stagingDirectory.create(recursive: true);

      input = InputFileStream(backupFile.path);
      final archive = ZipDecoder().decodeStream(input);
      final archiveFiles = _indexArchiveFiles(archive);

      final plan = archiveFiles.containsKey(_manifestPath)
          ? await _readV3Plan(
              archiveFiles,
              stagingDirectory,
              restoreDirectory,
              onProgress,
            )
          : archiveFiles.containsKey(_legacyMetaPath)
          ? await _readLegacyV2Plan(
              archiveFiles,
              stagingDirectory,
              restoreDirectory,
              onProgress,
            )
          : throw FormatException(
              'Invalid backup: missing $_manifestPath or $_legacyMetaPath',
            );

      return await _commitImportPlan(
        plan,
        restoreDirectory,
        replaceExisting: replaceExisting,
        onProgress: onProgress,
      );
    } catch (error) {
      debugPrint('Import error: $error');
      rethrow;
    } finally {
      await input?.close();
      final staging = stagingDirectory;
      if (staging != null && await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } catch (error) {
          debugPrint('Could not remove import staging directory: $error');
        }
      }
    }
  }

  /// Legacy helper, kept for backwards compatibility with version 1 JSON.
  bool validateJsonFormat(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final version = data['version'] as int?;
      final videos = data['videos'] as List<dynamic>?;
      return version == 1 && videos != null && videos.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getExportInfo() async {
    try {
      final entries = await _diaryRepo.load();
      var totalDurationMs = 0;
      var totalFileBytes = 0;

      for (final entry in entries) {
        totalDurationMs += entry.durationMs ?? 0;
        totalFileBytes += entry.fileBytes ?? 0;
      }

      return {
        'totalVideos': entries.length,
        'totalDurationSec': totalDurationMs ~/ 1000,
        'totalSizeBytes': totalFileBytes,
        'exportTimestamp': DateTime.now().toIso8601String(),
      };
    } catch (error) {
      debugPrint('Error getting export info: $error');
      return {};
    }
  }

  Future<Map<String, dynamic>> _addAsset(
    ZipFileEncoder encoder, {
    required File source,
    required String archivePath,
    required String entryId,
    required String kind,
  }) async {
    final sizeBytes = await source.length();
    final sha256Hash = await _sha256File(source);
    encoder.addFile(source, archivePath, ZipFileEncoder.store);
    return {
      'entryId': entryId,
      'kind': kind,
      'path': archivePath,
      'sizeBytes': sizeBytes,
      'sha256': sha256Hash,
    };
  }

  void _addJsonFile(
    ZipFileEncoder encoder,
    String path,
    Map<String, dynamic> data,
  ) {
    final bytes = utf8.encode(jsonEncode(data));
    encoder.addArchiveFile(ArchiveFile(path, bytes.length, bytes));
  }

  Future<_ImportPlan> _readV3Plan(
    Map<String, ArchiveFile> archiveFiles,
    Directory stagingDirectory,
    Directory restoreDirectory,
    ExportImportProgressCallback? onProgress,
  ) async {
    final manifest = _readArchiveJson(archiveFiles, _manifestPath);
    if (manifest['format'] != _backupFormat) {
      throw FormatException('Unsupported backup format.');
    }

    final schemaVersion = (manifest['schemaVersion'] as num?)?.toInt();
    if (schemaVersion != _currentSchemaVersion) {
      throw FormatException(
        'Unsupported backup schema version: $schemaVersion',
      );
    }

    final data = Map<String, dynamic>.from(manifest['data'] as Map);
    final entriesData = _readArchiveJson(
      archiveFiles,
      _requiredRelativePath(data, 'entries'),
    );
    final dayDataData = _readArchiveJson(
      archiveFiles,
      _requiredRelativePath(data, 'dayData'),
    );
    final moodsData = _readArchiveJson(
      archiveFiles,
      _requiredRelativePath(data, 'moods'),
    );
    final settingsData = _readArchiveJson(
      archiveFiles,
      _requiredRelativePath(data, 'settings'),
    );
    final preferencesPath = data['preferences'] as String?;
    final preferencesData = preferencesPath == null
        ? null
        : _readArchiveJson(archiveFiles, _normalizeRelative(preferencesPath));

    final assets = <String, _StagedAsset>{};
    final assetPaths = <String, String>{};
    final usedArchivePaths = <String>{};
    final referencedAssetKeys = <String>{};
    final assetRecords = manifest['files'];
    if (assetRecords is! List) {
      throw FormatException('Invalid backup manifest: files must be a list.');
    }

    for (var index = 0; index < assetRecords.length; index++) {
      final asset = Map<String, dynamic>.from(assetRecords[index] as Map);
      final entryId = asset['entryId'] as String?;
      final kind = asset['kind'] as String?;
      final archivePath = _normalizeRelative(asset['path'] as String? ?? '');
      final expectedSize = (asset['sizeBytes'] as num?)?.toInt();
      final expectedSha256 = asset['sha256'] as String?;

      if (entryId == null ||
          entryId.isEmpty ||
          (kind != 'video' && kind != 'thumbnail') ||
          expectedSize == null ||
          expectedSize < 0 ||
          expectedSha256 == null ||
          expectedSha256.isEmpty) {
        throw FormatException('Invalid asset record in backup manifest.');
      }

      final key = '$entryId::$kind';
      if (assets.containsKey(key)) {
        throw FormatException('Duplicate asset record: $key');
      }
      if (!usedArchivePaths.add(archivePath)) {
        throw FormatException('Duplicate asset path: $archivePath');
      }

      final archiveFile = archiveFiles[archivePath];
      if (archiveFile == null) {
        throw FormatException('Missing asset in backup: $archivePath');
      }

      final stagedFile = await _extractAndVerify(
        archiveFile,
        archivePath,
        stagingDirectory,
        expectedSize: expectedSize,
        expectedSha256: expectedSha256,
      );
      final extension = _safeExtension(
        archivePath,
        kind == 'video' ? '.mp4' : '.jpg',
      );
      final destinationRelative = kind == 'video'
          ? '$_videosDir/${_safeAssetStem(entryId)}$extension'
          : '$_thumbsDir/${_safeAssetStem(entryId)}$extension';
      final destinationPath = _resolveInside(
        restoreDirectory.path,
        destinationRelative,
      );
      assets[key] = _StagedAsset(
        stagedFile: stagedFile,
        destinationPath: destinationPath,
      );
      assetPaths[key] = archivePath;
      final progress =
          0.10 +
          (0.58 *
              ((index + 1) / (assetRecords.isEmpty ? 1 : assetRecords.length)));
      onProgress?.call(
        progress,
        'Validating media (${index + 1}/${assetRecords.length})...',
      );
    }

    final rawEntries = entriesData['entries'];
    if (rawEntries is! List) {
      throw FormatException('Invalid backup data: entries must be a list.');
    }
    final entries = <DiaryEntry>[];
    final entryIds = <String>{};
    for (final rawEntry in rawEntries) {
      final entryJson = Map<String, dynamic>.from(rawEntry as Map);
      final entryId = entryJson['id'] as String?;
      if (entryId == null || entryId.isEmpty || !entryIds.add(entryId)) {
        throw FormatException('Invalid or duplicate diary entry id.');
      }

      final videoAssetPath = entryJson.remove('videoAssetPath') as String?;
      final thumbnailAssetPath =
          entryJson.remove('thumbnailAssetPath') as String?;
      final videoAsset = videoAssetPath == null
          ? null
          : assets['$entryId::video'];
      final thumbnailAsset = thumbnailAssetPath == null
          ? null
          : assets['$entryId::thumbnail'];
      if (videoAssetPath != null) referencedAssetKeys.add('$entryId::video');
      if (thumbnailAssetPath != null) {
        referencedAssetKeys.add('$entryId::thumbnail');
      }
      if (videoAssetPath != null &&
              (videoAsset == null ||
                  assetPaths['$entryId::video'] !=
                      _normalizeRelative(videoAssetPath)) ||
          thumbnailAssetPath != null &&
              (thumbnailAsset == null ||
                  assetPaths['$entryId::thumbnail'] !=
                      _normalizeRelative(thumbnailAssetPath))) {
        throw FormatException('Diary entry references a missing media asset.');
      }

      entryJson['path'] = '';
      entryJson['thumbnailPath'] = null;
      final sourceEntry = DiaryEntry.fromJson(entryJson);
      entries.add(
        _entryWithMediaPaths(
          sourceEntry,
          path: videoAsset?.destinationPath ?? '',
          thumbnailPath: thumbnailAsset?.destinationPath,
        ),
      );
    }
    if (assets.keys.any((key) => !referencedAssetKeys.contains(key))) {
      throw FormatException('Backup contains an unreferenced media asset.');
    }

    return _ImportPlan(
      entries: entries,
      dayData: _parseDayData(dayDataData),
      moods: _parseMoods(moodsData['moods']),
      settings: SettingsModel.fromJson(settingsData),
      preferences: preferencesData,
      assets: assets.values.toList(),
    );
  }

  Future<_ImportPlan> _readLegacyV2Plan(
    Map<String, ArchiveFile> archiveFiles,
    Directory stagingDirectory,
    Directory restoreDirectory,
    ExportImportProgressCallback? onProgress,
  ) async {
    final meta = _readArchiveJson(archiveFiles, _legacyMetaPath);
    final version = (meta['version'] as num?)?.toInt();
    if (version != _legacyExportVersion) {
      throw FormatException('Unsupported legacy backup version: $version');
    }

    final rawVideos = meta['videos'];
    if (rawVideos is! List) {
      throw FormatException('Invalid legacy backup: videos must be a list.');
    }

    final entries = <DiaryEntry>[];
    final assets = <_StagedAsset>[];
    for (var index = 0; index < rawVideos.length; index++) {
      final sourceEntry = DiaryEntry.fromJson(
        Map<String, dynamic>.from(rawVideos[index] as Map),
      );
      final videoPath = await _extractLegacyAsset(
        archiveFiles,
        sourceEntry.path,
        stagingDirectory,
        restoreDirectory,
        entryId: sourceEntry.id,
        kind: 'video',
        assets: assets,
      );
      final thumbnailPath = await _extractLegacyAsset(
        archiveFiles,
        sourceEntry.thumbnailPath,
        stagingDirectory,
        restoreDirectory,
        entryId: sourceEntry.id,
        kind: 'thumbnail',
        assets: assets,
      );
      entries.add(
        _entryWithMediaPaths(
          sourceEntry,
          path: videoPath ?? '',
          thumbnailPath: thumbnailPath,
        ),
      );
      final progress =
          0.10 +
          (0.58 * ((index + 1) / (rawVideos.isEmpty ? 1 : rawVideos.length)));
      onProgress?.call(
        progress,
        'Importing legacy backup (${index + 1}/${rawVideos.length})...',
      );
    }

    final settingsRaw = meta['settings'];
    final settings = settingsRaw is Map
        ? SettingsModel.fromJson(Map<String, dynamic>.from(settingsRaw))
        : null;
    final prefsRaw = meta['prefs'];

    return _ImportPlan(
      entries: entries,
      dayData: _parseDayData(meta['dayData']),
      moods: _parseMoods(meta['moodCatalog']),
      settings: settings,
      preferences: prefsRaw is Map ? Map<String, dynamic>.from(prefsRaw) : null,
      assets: assets,
    );
  }

  Future<String?> _extractLegacyAsset(
    Map<String, ArchiveFile> archiveFiles,
    String? relativePath,
    Directory stagingDirectory,
    Directory restoreDirectory, {
    required String entryId,
    required String kind,
    required List<_StagedAsset> assets,
  }) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    final archivePath = _normalizeRelative(relativePath);
    final archiveFile = archiveFiles[archivePath];
    if (archiveFile == null) return null;

    final stagedFile = await _extractAndVerify(
      archiveFile,
      archivePath,
      stagingDirectory,
    );
    final extension = _safeExtension(
      archivePath,
      kind == 'video' ? '.mp4' : '.jpg',
    );
    final destinationRelative = kind == 'video'
        ? '$_videosDir/${_safeAssetStem(entryId)}$extension'
        : '$_thumbsDir/${_safeAssetStem(entryId)}$extension';
    final destinationPath = _resolveInside(
      restoreDirectory.path,
      destinationRelative,
    );
    assets.add(
      _StagedAsset(stagedFile: stagedFile, destinationPath: destinationPath),
    );
    return destinationPath;
  }

  Future<int> _commitImportPlan(
    _ImportPlan plan,
    Directory restoreDirectory, {
    required bool replaceExisting,
    ExportImportProgressCallback? onProgress,
  }) async {
    final currentEntries = await _diaryRepo.load();
    final oldMediaPaths = _mediaPaths(currentEntries);

    onProgress?.call(0.74, 'Placing media files...');
    for (final asset in plan.assets) {
      await _installStagedAsset(asset);
    }

    onProgress?.call(0.84, 'Updating diary data...');
    final committedEntries = replaceExisting
        ? _sortEntries(plan.entries)
        : _mergeEntries(currentEntries, plan.entries);
    await _diaryRepo.save(committedEntries);

    final currentMoodCatalog = replaceExisting
        ? <Mood>[]
        : await _moodRepo.load();
    final moodsById = <String, Mood>{
      for (final mood in currentMoodCatalog) mood.id: mood,
    };
    for (final mood in plan.moods) {
      moodsById[mood.id] = mood;
    }
    for (final entry in plan.entries) {
      for (final mood in entry.moods ?? const <Mood>[]) {
        moodsById[mood.id] = mood;
      }
    }
    await _moodRepo.save(moodsById.values.toList());

    await _dayRepo.init();
    final dayDataBox = Hive.box('day_data');
    if (replaceExisting) await dayDataBox.clear();
    for (final item in plan.dayData.entries) {
      if (replaceExisting || !dayDataBox.containsKey(item.key)) {
        await dayDataBox.put(item.key, item.value);
      }
    }

    if (replaceExisting && plan.settings != null) {
      final settingsJson = Map<String, dynamic>.from(plan.settings!.toJson())
        ..['storageDirectory'] = null;
      await _settingsRepo.save(SettingsModel.fromJson(settingsJson));
    }
    if (replaceExisting && plan.preferences != null) {
      await _restorePreferences(plan.preferences!);
    }

    if (replaceExisting) {
      final newMediaPaths = _mediaPaths(committedEntries);
      for (final oldPath in oldMediaPaths.difference(newMediaPaths)) {
        await _deleteIfExists(oldPath);
      }
    }

    onProgress?.call(1.0, 'Import completed successfully.');
    debugPrint('Import successful: ${plan.entries.length} videos');
    return plan.entries.length;
  }

  Future<void> _installStagedAsset(_StagedAsset asset) async {
    final destination = File(asset.destinationPath);
    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.importing-${_newOperationId()}',
    );
    try {
      await _copyFile(asset.stagedFile, temporary);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    } catch (_) {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _copyFile(File source, File destination) async {
    final sink = destination.openWrite();
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
  }

  Future<File> _extractAndVerify(
    ArchiveFile archiveFile,
    String archivePath,
    Directory stagingDirectory, {
    int? expectedSize,
    String? expectedSha256,
  }) async {
    final outputPath = _resolveInside(stagingDirectory.path, archivePath);
    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    final output = OutputFileStream(outputFile.path);
    try {
      archiveFile.writeContent(output);
    } finally {
      await output.close();
    }

    final actualSize = await outputFile.length();
    if (expectedSize != null && actualSize != expectedSize) {
      throw FormatException('Asset size mismatch: $archivePath');
    }
    final actualSha256 = await _sha256File(outputFile);
    if (expectedSha256 != null &&
        actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
      throw FormatException('Asset checksum mismatch: $archivePath');
    }
    return outputFile;
  }

  Future<String> _sha256File(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.events.single.toString();
  }

  Future<void> _restorePreferences(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final lens = data[_prefCameraLensKey];
    if (lens is String) await prefs.setString(_prefCameraLensKey, lens);
    final count = data[_prefRecordedVideoCountKey];
    if (count is int) await prefs.setInt(_prefRecordedVideoCountKey, count);
    final reviewCompleted = data[_prefReviewCompletedKey];
    if (reviewCompleted is bool) {
      await prefs.setBool(_prefReviewCompletedKey, reviewCompleted);
    }
  }

  Map<String, ArchiveFile> _indexArchiveFiles(Archive archive) {
    final files = <String, ArchiveFile>{};
    for (final archiveFile in archive.files.where((file) => file.isFile)) {
      final path = _normalizeRelative(archiveFile.name);
      if (files.containsKey(path)) {
        throw FormatException('Duplicate file in backup: $path');
      }
      files[path] = archiveFile;
    }
    return files;
  }

  Map<String, dynamic> _readArchiveJson(
    Map<String, ArchiveFile> archiveFiles,
    String path,
  ) {
    final archiveFile = archiveFiles[path];
    if (archiveFile == null) {
      throw FormatException('Missing backup metadata: $path');
    }
    final content = archiveFile.content;
    final value = jsonDecode(utf8.decode(content));
    if (value is! Map) {
      throw FormatException('Backup metadata must be a JSON object: $path');
    }
    return Map<String, dynamic>.from(value);
  }

  String _requiredRelativePath(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Backup manifest is missing data.$key.');
    }
    return _normalizeRelative(value);
  }

  Map<String, Map<String, dynamic>> _parseDayData(Object? raw) {
    if (raw is! Map) return {};
    final result = <String, Map<String, dynamic>>{};
    for (final item in raw.entries) {
      if (item.value is Map) {
        result[item.key.toString()] = Map<String, dynamic>.from(
          item.value as Map,
        );
      }
    }
    return result;
  }

  List<Mood> _parseMoods(Object? raw) {
    if (raw is! List) return [];
    return raw.map(Mood.fromDynamic).whereType<Mood>().toList();
  }

  List<DiaryEntry> _mergeEntries(
    List<DiaryEntry> current,
    List<DiaryEntry> imported,
  ) {
    final entriesById = <String, DiaryEntry>{
      for (final entry in current) entry.id: entry,
    };
    for (final entry in imported) {
      final existing = entriesById[entry.id];
      entriesById[entry.id] = existing == null
          ? entry
          : _mergeEntry(existing, entry);
    }
    return _sortEntries(entriesById.values.toList());
  }

  DiaryEntry _mergeEntry(DiaryEntry current, DiaryEntry imported) {
    return DiaryEntry(
      id: imported.id,
      path: imported.path.isNotEmpty ? imported.path : current.path,
      date: imported.date,
      thumbnailPath: imported.thumbnailPath ?? current.thumbnailPath,
      durationMs: imported.durationMs,
      fileBytes: imported.fileBytes,
      title: imported.title,
      description: imported.description,
      rating: imported.rating,
      moods: imported.moods,
      lensDirection: imported.lensDirection,
    );
  }

  List<DiaryEntry> _sortEntries(List<DiaryEntry> entries) {
    entries.sort((left, right) => right.date.compareTo(left.date));
    return entries;
  }

  Set<String> _mediaPaths(Iterable<DiaryEntry> entries) {
    return {
      for (final entry in entries)
        if (entry.path.isNotEmpty) entry.path,
      for (final entry in entries)
        if (entry.thumbnailPath != null && entry.thumbnailPath!.isNotEmpty)
          entry.thumbnailPath!,
    };
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (error) {
        debugPrint('Could not delete old media file $path: $error');
      }
    }
  }

  DiaryEntry _entryWithMediaPaths(
    DiaryEntry entry, {
    required String path,
    required String? thumbnailPath,
  }) {
    return DiaryEntry(
      id: entry.id,
      path: path,
      date: entry.date,
      thumbnailPath: thumbnailPath,
      durationMs: entry.durationMs,
      fileBytes: entry.fileBytes,
      title: entry.title,
      description: entry.description,
      rating: entry.rating,
      moods: entry.moods,
      lensDirection: entry.lensDirection,
    );
  }

  String _safeAssetStem(String id) {
    final sanitized = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final prefix = sanitized.isEmpty ? 'asset' : sanitized;
    final digest = sha256.convert(utf8.encode(id)).toString().substring(0, 12);
    return '${prefix}_$digest';
  }

  String _safeExtension(String path, String fallback) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return fallback;
    final extension = name.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : fallback;
  }

  String _normalizeRelative(String relative) {
    final normalized = relative.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.startsWith('~/')) {
      throw FormatException('Invalid absolute or empty backup path: $relative');
    }
    if (normalized.length >= 2 && normalized[1] == ':') {
      throw FormatException('Invalid drive path in backup: $relative');
    }
    final parts = normalized.split('/');
    for (final part in parts) {
      if (part == '.' || part == '..') {
        throw FormatException('Invalid traversal path in backup: $relative');
      }
    }
    return parts.where((part) => part.isNotEmpty).join('/');
  }

  String _resolveInside(String base, String relative) {
    final clean = _normalizeRelative(
      relative,
    ).replaceAll('/', Platform.pathSeparator);
    final separator = Platform.pathSeparator;
    final normalizedBase = base.endsWith(separator)
        ? base.substring(0, base.length - 1)
        : base;
    return '$normalizedBase$separator$clean';
  }

  String _newOperationId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$timestamp-${timestamp.hashCode.abs()}';
  }
}

class _ImportPlan {
  const _ImportPlan({
    required this.entries,
    required this.dayData,
    required this.moods,
    required this.settings,
    required this.preferences,
    required this.assets,
  });

  final List<DiaryEntry> entries;
  final Map<String, Map<String, dynamic>> dayData;
  final List<Mood> moods;
  final SettingsModel? settings;
  final Map<String, dynamic>? preferences;
  final List<_StagedAsset> assets;
}

class _StagedAsset {
  const _StagedAsset({required this.stagedFile, required this.destinationPath});

  final File stagedFile;
  final String destinationPath;
}
