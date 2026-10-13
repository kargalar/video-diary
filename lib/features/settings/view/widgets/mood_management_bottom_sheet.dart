import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../diary/model/mood.dart';
import '../../../diary/viewmodel/diary_view_model.dart';

class MoodManagementBottomSheet extends StatefulWidget {
  const MoodManagementBottomSheet({super.key});

  @override
  State<MoodManagementBottomSheet> createState() => _MoodManagementBottomSheetState();
}

class _MoodManagementBottomSheetState extends State<MoodManagementBottomSheet> {
  Future<void> _showEditor(BuildContext context, {Mood? mood}) async {
    await showMoodEditorBottomSheet(context, mood: mood);
  }

  Future<void> _deleteMood(BuildContext context, Mood mood) async {
    final vm = context.read<DiaryViewModel>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DeleteMoodDialog(mood: mood),
    );

    if (confirm == true && context.mounted) {
      await vm.deleteMood(mood.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DiaryViewModel>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(999)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Mood Library', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  FilledButton.icon(onPressed: () => _showEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('Add')),
                ],
              ),
            ),
            Expanded(
              child: vm.availableMoods.isEmpty
                  ? Center(
                      child: Text('No moods yet.', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: vm.availableMoods.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final mood = vm.availableMoods[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            leading: Text(mood.emoji, style: const TextStyle(fontSize: 28)),
                            title: Text(mood.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit mood',
                                  onPressed: () => _showEditor(context, mood: mood),
                                  icon: const Icon(Icons.edit_rounded),
                                ),
                                IconButton(tooltip: 'Delete mood', onPressed: () => _deleteMood(context, mood), icon: const Icon(Icons.delete_outline_rounded), color: Colors.redAccent),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showMoodEditorBottomSheet(BuildContext context, {Mood? mood}) async {
  final vm = context.read<DiaryViewModel>();

  final result = await showModalBottomSheet<_MoodEditorResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _MoodEditorSheet(mood: mood),
  );

  if (result == null || !context.mounted) {
    return false;
  }

  if (result.isDeleted && mood != null) {
    await vm.deleteMood(mood.id);
    return true;
  }

  final ok = mood == null ? await vm.addMood(emoji: result.emoji, label: result.label) : await vm.updateMood(original: mood, emoji: result.emoji, label: result.label);

  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mood label cannot be empty.')));
  }

  return ok;
}

class _MoodEditorResult {
  const _MoodEditorResult({required this.emoji, required this.label, this.isDeleted = false});

  final String emoji;
  final String label;
  final bool isDeleted;
}

class _MoodEditorSheet extends StatefulWidget {
  const _MoodEditorSheet({this.mood});

  final Mood? mood;

  @override
  State<_MoodEditorSheet> createState() => _MoodEditorSheetState();
}

class _MoodEditorSheetState extends State<_MoodEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emojiController;
  late final TextEditingController _labelController;
  late final FocusNode _emojiFocusNode;
  late final FocusNode _labelFocusNode;

  bool get _isEditing => widget.mood != null;

  @override
  void initState() {
    super.initState();
    _emojiController = TextEditingController(text: widget.mood?.emoji ?? '🙂');
    _labelController = TextEditingController(text: widget.mood?.label ?? '');
    _emojiFocusNode = FocusNode();
    _labelFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _emojiController.dispose();
    _labelController.dispose();
    _emojiFocusNode.dispose();
    _labelFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(_MoodEditorResult(emoji: _emojiController.text.trim(), label: _labelController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : theme.scaffoldBackgroundColor;
    final cardColor = isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF7F8FA);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final accentColor = theme.colorScheme.primary;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: isDark ? 0.18 : 0.10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Icon(_isEditing ? Icons.edit_rounded : Icons.add_reaction_rounded, color: accentColor, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_isEditing ? 'Edit mood' : 'Create mood', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('You can enter a short phrase instead of an emoji.', style: theme.textTheme.bodyMedium?.copyWith(color: secondaryTextColor, height: 1.35)),
                          ],
                        ),
                      ),
                      if (_isEditing)
                        IconButton(
                          tooltip: 'Delete mood',
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => _DeleteMoodDialog(mood: widget.mood!),
                            );
                            if (confirm == true && context.mounted) {
                              Navigator.of(context).pop(const _MoodEditorResult(emoji: '', label: '', isDeleted: true));
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _emojiController,
                    focusNode: _emojiFocusNode,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _labelFocusNode.requestFocus(),
                    inputFormatters: [LengthLimitingTextInputFormatter(12)],
                    decoration: InputDecoration(
                      labelText: 'Emoji or short phrase',
                      hintText: '🙂, OK, Gym, ++',
                      helperText: 'Leave blank to use 🙂 by default.',
                      prefixIcon: const Icon(Icons.emoji_emotions_outlined),
                      filled: true,
                      fillColor: cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: accentColor, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _labelController,
                    focusNode: _labelFocusNode,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Mood name is required.';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Mood name',
                      hintText: 'Happy, Focused, Busy...',
                      prefixIcon: const Icon(Icons.label_outline_rounded),
                      filled: true,
                      fillColor: cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: accentColor, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            side: BorderSide(color: borderColor),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: Icon(_isEditing ? Icons.check_rounded : Icons.add_rounded),
                          label: Text(_isEditing ? 'Save' : 'Create'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteMoodDialog extends StatelessWidget {
  const _DeleteMoodDialog({required this.mood});

  final Mood mood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final cardColor = isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFFFF4F4);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.red.withValues(alpha: 0.12);
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Material(
        color: surfaceColor,
        elevation: 10,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              Text('Delete mood?', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Text(mood.emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(mood.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('This mood will be removed from the library and existing diary entries.', style: theme.textTheme.bodyMedium?.copyWith(color: secondaryTextColor, height: 1.45)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.delete_rounded),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
