import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../features/diary/viewmodel/diary_view_model.dart';
import '../../../../services/export_import_service.dart';
import '../../../../services/storage_service.dart';

class ExportImportDialog extends StatefulWidget {
  final VoidCallback onDataImported;

  const ExportImportDialog({super.key, required this.onDataImported});

  @override
  State<ExportImportDialog> createState() => _ExportImportDialogState();
}

class _ExportImportDialogState extends State<ExportImportDialog> {
  final ExportImportService _service = ExportImportService();
  bool _isLoading = false;
  double _progress = 0.0;
  String _statusMessage = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return AlertDialog(
      title: const Text('Export & Import'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              'Export creates a portable backup package containing your videos, thumbnails, and app data. You can restore it at any time.',
              style: textTheme.bodyMedium,
            ),
            _InfoCard(
              icon: Icons.inventory_2_outlined,
              text:
                  'Backup includes: videos, thumbnails, ratings, moods, daily notes, and app settings.',
              backgroundColor: colorScheme.primaryContainer.withValues(
                alpha: 0.4,
              ),
              foregroundColor: colorScheme.onPrimaryContainer,
            ),
            _InfoCard(
              icon: Icons.merge_type_rounded,
              text:
                  'During Import: You can choose to merge backup with existing entries or completely replace them.',
              backgroundColor: colorScheme.secondaryContainer.withValues(
                alpha: 0.4,
              ),
              foregroundColor: colorScheme.onSecondaryContainer,
            ),
            if (_isLoading)
              _ProgressSection(
                progress: _progress,
                statusMessage: _statusMessage,
              )
            else
              _ActionButtonsSection(
                onExport: _handleExport,
                onImport: _handleImport,
                onClearAll: _handleClearAll,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _handleExport() async {
    try {
      setState(() {
        _isLoading = true;
        _progress = 0.0;
        _statusMessage = 'Preparing backup...';
      });

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName = 'video_diary_backup_$timestamp.vdbackup';

      final tempDir = await getTemporaryDirectory();
      final tempZipPath = '${tempDir.path}${Platform.pathSeparator}$fileName';

      final createdPath = await _service.exportData(
        tempZipPath,
        onProgress: (double progress, String status) {
          _reportProgress(progress, status);
        },
      );

      if (!mounted) return;

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Backup File',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const <String>['vdbackup', 'zip'],
        );

        if (savePath != null && savePath.isNotEmpty) {
          final tempFile = File(createdPath);
          final destinationFile = File(savePath);
          await destinationFile.parent.create(recursive: true);
          _reportProgress(0.95, 'Saving backup file...');
          await _copyFileWithProgress(
            source: tempFile,
            destination: destinationFile,
            onProgress: (progress) =>
                _reportProgress(progress, 'Saving backup file...'),
            startProgress: 0.95,
            endProgress: 1.0,
          );
          try {
            await tempFile.delete();
          } catch (_) {}

          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Backup saved: ${destinationFile.path}'),
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      final file = File(createdPath);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Video Diary Backup ($fileName)',
        ),
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Backup created and ready to share/save.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleImport() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['vdbackup', 'zip'],
        allowMultiple: false,
        withData: false,
        withReadStream: true,
      );

      if (result == null || result.files.isEmpty) return;
      final selectedFile = result.files.single;

      if (!mounted) return;
      final importMode = await showDialog<_ImportChoice>(
        context: context,
        builder: (BuildContext dialogContext) => const _ImportModeDialog(),
      );

      if (importMode == null || importMode == _ImportChoice.cancel) return;

      final replaceExisting = importMode == _ImportChoice.replace;

      if (mounted) {
        setState(() {
          _isLoading = true;
          _progress = 0.0;
          _statusMessage = 'Reading backup file...';
        });
      }

      final backupFile = await _resolveSelectedBackup(
        selectedFile,
        onProgress: (progress, status) => _reportProgress(progress, status),
      );
      final internalDir = await StorageService().getInternalDiaryFolder();
      final restoreDirPath = internalDir.path;

      final importedCount = await _service.importData(
        backupFile,
        restoreDirPath,
        replaceExisting: replaceExisting,
        onProgress: (double progress, String status) {
          _reportProgress(progress, status);
        },
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              replaceExisting
                  ? '✅ Old data replaced! $importedCount videos imported.'
                  : '✅ $importedCount videos successfully merged.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        widget.onDataImported();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<File> _resolveSelectedBackup(
    PlatformFile selected, {
    ExportImportProgressCallback? onProgress,
  }) async {
    final selectedPath = selected.path;
    if (selectedPath != null &&
        selectedPath.isNotEmpty &&
        !selectedPath.startsWith('content://')) {
      final existing = File(selectedPath);
      if (await existing.exists()) {
        onProgress?.call(0.05, 'Backup file ready...');
        return existing;
      }
    }

    final safeName = selected.name.isEmpty
        ? 'import_backup.vdbackup'
        : selected.name;
    final tempFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$safeName',
    );
    await tempFile.parent.create(recursive: true);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final stream = selected.readStream;
    if (stream == null) {
      throw Exception('Selected backup file stream is unavailable.');
    }

    final sink = tempFile.openWrite();
    var copiedBytes = 0;
    final totalBytes = selected.size;
    try {
      await for (final chunk in stream) {
        sink.add(chunk);
        copiedBytes += chunk.length;
        final progress = totalBytes > 0
            ? 0.01 + (0.04 * (copiedBytes / totalBytes).clamp(0.0, 1.0))
            : 0.03;
        onProgress?.call(progress, 'Reading backup file...');
      }
    } finally {
      await sink.close();
    }

    onProgress?.call(0.05, 'Backup file ready...');

    if (!await tempFile.exists()) {
      throw Exception('Selected backup file could not be accessed.');
    }

    return tempFile;
  }

  Future<void> _copyFileWithProgress({
    required File source,
    required File destination,
    required void Function(double progress) onProgress,
    required double startProgress,
    required double endProgress,
  }) async {
    final totalBytes = await source.length();
    var copiedBytes = 0;
    final sink = destination.openWrite();

    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        copiedBytes += chunk.length;
        final ratio = totalBytes == 0
            ? 1.0
            : (copiedBytes / totalBytes).clamp(0.0, 1.0);
        onProgress(startProgress + ((endProgress - startProgress) * ratio));
      }
    } finally {
      await sink.close();
    }
  }

  void _reportProgress(double progress, String status) {
    if (!mounted) return;

    setState(() {
      _progress = progress.clamp(0.0, 1.0);
      _statusMessage = status;
    });
  }

  Future<void> _handleClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('⚠️ Clear All Data?'),
        content: const Text(
          'This will permanently DELETE all your recorded videos, thumbnails, ratings, moods, and streak history.\n\nThis action cannot be undone!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      setState(() {
        _isLoading = true;
        _progress = 0.5;
        _statusMessage = 'Clearing all data...';
      });

      final diaryVm = context.read<DiaryViewModel>();
      final success = await diaryVm.clearAll();

      if (!success) {
        throw Exception('Failed to clear data.');
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ All data cleared!'),
            duration: Duration(seconds: 3),
          ),
        );
        widget.onDataImported();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

enum _ImportChoice { replace, merge, cancel }

class _ImportModeDialog extends StatelessWidget {
  const _ImportModeDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return AlertDialog(
      title: const Text('Import Options'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            'How would you like to restore this backup?',
            style: textTheme.bodyMedium,
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(_ImportChoice.merge),
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Merge with Existing Data'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_ImportChoice.replace),
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Replace All Existing Data'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ImportChoice.cancel),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color backgroundColor;
  final Color foregroundColor;

  const _InfoCard({
    required this.icon,
    required this.text,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Icon(icon, size: 20, color: foregroundColor),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(color: foregroundColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  final double progress;
  final String statusMessage;

  const _ProgressSection({required this.progress, required this.statusMessage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          borderRadius: BorderRadius.circular(4),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                statusMessage,
                style: textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButtonsSection extends StatelessWidget {
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onClearAll;

  const _ActionButtonsSection({
    required this.onExport,
    required this.onImport,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        FilledButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Export Backup'),
        ),
        OutlinedButton.icon(
          onPressed: onImport,
          icon: const Icon(Icons.upload_rounded),
          label: const Text('Import Backup'),
        ),
        TextButton.icon(
          onPressed: onClearAll,
          icon: const Icon(Icons.delete_sweep_rounded),
          label: const Text('Clear All Data'),
          style: TextButton.styleFrom(foregroundColor: colorScheme.error),
        ),
      ],
    );
  }
}
