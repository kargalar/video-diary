import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../model/mood.dart';
import '../../viewmodel/diary_view_model.dart';
import '../../../settings/view/widgets/mood_management_bottom_sheet.dart';
import 'mood_chip.dart';
import 'star_rating_bar.dart';

class VideoEditBottomSheet extends StatefulWidget {
  final String currentTitle;
  final String? currentDescription;
  final int? currentRating;
  final List<Mood> currentMoods;
  final DateTime? currentDate;
  final bool isNewVideo;

  const VideoEditBottomSheet({super.key, required this.currentTitle, this.currentDescription, this.currentRating, required this.currentMoods, this.currentDate, this.isNewVideo = false});

  @override
  State<VideoEditBottomSheet> createState() => _VideoEditBottomSheetState();
}

class _VideoEditBottomSheetState extends State<VideoEditBottomSheet> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late FocusNode _titleFocusNode;
  late FocusNode _descriptionFocusNode;
  late int _rating;
  late Set<Mood> _selectedMoods;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.currentTitle);
    _descriptionController = TextEditingController(text: widget.currentDescription ?? '');
    _titleFocusNode = FocusNode();
    _descriptionFocusNode = FocusNode();
    _rating = widget.currentRating ?? 0;
    _selectedMoods = widget.currentMoods.toSet();
    _selectedDate = widget.currentDate ?? DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  Map<String, dynamic> _getResult() {
    return {'title': _titleController.text.trim(), 'description': _descriptionController.text.trim(), 'rating': _rating == 0 ? null : _rating, 'moods': _selectedMoods.toList(), if (kDebugMode) 'date': _selectedDate};
  }

  Future<void> _editMood(Mood mood) async {
    final updated = await showMoodEditorBottomSheet(context, mood: mood);
    if (!updated || !mounted || !_selectedMoods.any((selected) => selected.id == mood.id)) {
      return;
    }

    Mood? refreshedMood;
    for (final item in context.read<DiaryViewModel>().availableMoods) {
      if (item.id == mood.id) {
        refreshedMood = item;
        break;
      }
    }

    setState(() {
      _selectedMoods.removeWhere((selected) => selected.id == mood.id);
      if (refreshedMood != null) {
        _selectedMoods.add(refreshedMood);
      }
    });
  }

  Future<void> _addMood() async {
    final added = await showMoodEditorBottomSheet(context);
    // After adding, we don't automatically select it, but we let the UI rebuild to show it in the list.
    if (added && mounted) {
      setState(() {});
    }
  }

  Future<bool> _showDiscardDialog() async {
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Discard video?', style: TextStyle(color: Colors.white)),
        content: Text('If you close without saving, the video will be deleted.', style: TextStyle(color: Colors.grey[400])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return shouldClose == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : theme.scaffoldBackgroundColor;
    final cardColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);
    final subtleColor = isDark ? Colors.white.withAlpha(30) : Colors.black.withAlpha(15);
    final textColor = isDark ? Colors.white : const Color(0xFF2C2C2C);
    final subtleTextColor = isDark ? Colors.grey[500]! : Colors.grey[400]!;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          if (widget.isNewVideo) {
            if (await _showDiscardDialog() && context.mounted) {
              Navigator.of(context).pop({'discard': true});
            }
          } else {
            Navigator.of(context).pop(_getResult());
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            _buildHeader(theme, textColor, subtleTextColor),
            Expanded(child: _buildContent(theme, isDark, cardColor, subtleColor, textColor, subtleTextColor)),
            if (widget.isNewVideo) _buildSaveButton(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Color textColor, Color subtleTextColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.isNewVideo ? 'New Entry' : 'Edit Entry',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: textColor, letterSpacing: -0.5),
                ),
              ),
              if (widget.isNewVideo)
                IconButton(
                  icon: Icon(Icons.close_rounded, color: subtleTextColor, size: 22),
                  style: IconButton.styleFrom(backgroundColor: Colors.white.withAlpha(8)),
                  onPressed: () async {
                    if (await _showDiscardDialog() && mounted) {
                      Navigator.of(context).pop({'discard': true});
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark, Color cardColor, Color subtleColor, Color textColor, Color subtleTextColor) {
    final moods = context.watch<DiaryViewModel>().availableMoods;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title & Description card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: subtleColor),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _descriptionFocusNode.requestFocus(),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor, letterSpacing: -0.3),
                  cursorColor: Colors.white70,
                  decoration: InputDecoration(
                    hintText: 'Title',
                    hintStyle: TextStyle(fontSize: 18, color: subtleTextColor, fontWeight: FontWeight.w400),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
                Divider(color: subtleColor, height: 20),
                TextField(
                  controller: _descriptionController,
                  focusNode: _descriptionFocusNode,
                  textInputAction: TextInputAction.done,
                  maxLines: null,
                  minLines: 2,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: textColor.withAlpha(180), height: 1.5),
                  cursorColor: Colors.white70,
                  decoration: InputDecoration(
                    hintText: 'How was your day?',
                    hintStyle: TextStyle(fontSize: 14, color: subtleTextColor),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Debug: Date picker
          if (kDebugMode) ...[_buildDebugDatePicker(isDark, cardColor, subtleColor, textColor, subtleTextColor), const SizedBox(height: 20)],

          // Rating section
          _buildSectionLabel('Rating', textColor),
          const SizedBox(height: 10),
          StarRatingBar(rating: _rating, onRatingChanged: (value) => setState(() => _rating = value)),
          const SizedBox(height: 24),

          // Mood section
          _buildSectionLabel('Mood', textColor),
          const SizedBox(height: 6),
          Text('Tap to select. Long press to edit.', style: TextStyle(fontSize: 12, color: subtleTextColor, height: 1.3)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...moods.map((mood) {
                final isSelected = _selectedMoods.any((selected) => selected.id == mood.id);
                return MoodChip(
                  mood: mood,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedMoods.removeWhere((selected) => selected.id == mood.id);
                      } else {
                        _selectedMoods.add(mood);
                      }
                    });
                  },
                  onLongPress: () => _editMood(mood),
                );
              }),
              _buildAddMoodButton(isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddMoodButton(bool isDark) {
    final bgColor = isDark ? Colors.white.withAlpha(8) : const Color(0xFFF0F0F0);
    final borderColor = isDark ? Colors.white.withAlpha(15) : Colors.transparent;
    final iconColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;

    return GestureDetector(
      onTap: _addMood,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18, color: iconColor),
            const SizedBox(width: 4),
            Text(
              'New',
              style: TextStyle(color: iconColor, fontWeight: FontWeight.w500, fontSize: 13, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, Color textColor) {
    return Text(
      label,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor.withAlpha(120), letterSpacing: 1.0),
    );
  }

  Widget _buildDebugDatePicker(bool isDark, Color cardColor, Color subtleColor, Color textColor, Color subtleTextColor) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(primary: Colors.white, onPrimary: Colors.black, surface: Color(0xFF2A2A2A), onSurface: Colors.white),
                dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF2A2A2A)),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) setState(() => _selectedDate = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: subtleColor),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 18, color: subtleTextColor),
            const SizedBox(width: 12),
            Text(
              DateFormat('MMM dd, yyyy').format(_selectedDate),
              style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, size: 18, color: subtleTextColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton(bool isDark) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, _getResult()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 0,
            ),
            child: const Text('Save Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          ),
        ),
      ),
    );
  }
}
