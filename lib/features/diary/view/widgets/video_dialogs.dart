import 'package:flutter/material.dart';

class VideoDialogs {
  static Future<String?> showRenameDialog(BuildContext context, {String current = ''}) async {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        title: const Text(
          'Edit Title',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: Color(0xFF2C2C2C)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a new title for this video',
              style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Video title',
                hintStyle: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w400),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2C2C2C), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.3),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(controller.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2C2C2C),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.3)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<bool?> showDeleteConfirmation(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withAlpha(20), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Video',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: Color(0xFF2C2C2C)),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this video? This action cannot be undone.',
          style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w400, height: 1.5),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.3),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Delete',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.3, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
