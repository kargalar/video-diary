import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/navigation/app_routes.dart';
import '../viewmodel/settings_view_model.dart';
import '../../diary/viewmodel/diary_view_model.dart';
import 'privacy_policy_webview_page.dart';
import 'widgets/mood_management_bottom_sheet.dart';
import 'widgets/export_import_dialog.dart';

class SettingsPage extends StatelessWidget {
  static const route = '/settings';
  const SettingsPage({super.key});

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8, top: 24),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildSection(BuildContext context, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionColor = isDark ? const Color(0xFF242424) : Colors.white;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05);
    final shadowColor = isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.02);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: sectionColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [BoxShadow(color: shadowColor, blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children.asMap().entries.map((entry) {
          final isLast = entry.key == children.length - 1;
          return Column(
            children: [
              entry.value,
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Divider(height: 1, thickness: 1, color: borderColor),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTile({required BuildContext context, required IconData icon, required Color iconColor, required String title, String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      minVerticalPadding: 8,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: iconColor.withValues(alpha: isDark ? 0.3 : 0.2), width: 1),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, height: 1.3)) : null,
      trailing: trailing ?? Icon(Icons.chevron_right_rounded, color: isDark ? Colors.grey.shade500 : Colors.grey.shade400, size: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final diaryVm = context.watch<DiaryViewModel>();
    final state = vm.state;
    final timeOfDay = TimeOfDay(hour: state.reminderHour, minute: state.reminderMinute);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _buildSectionHeader('Preferences'),
          _buildSection(context, [
            _buildTile(
              context: context,
              icon: Icons.notifications_active_rounded,
              iconColor: Colors.orangeAccent,
              title: 'Daily Reminder',
              subtitle: state.reminderEnabled ? 'Daily notifications at ${timeOfDay.format(context)}' : 'Daily notifications are off',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.reminderEnabled) ...[
                    ElevatedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: timeOfDay,
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                timePickerTheme: TimePickerThemeData(
                                  backgroundColor: isDark ? const Color(0xFF242424) : Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          await vm.setReminder(picked.hour, picked.minute);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder time updated')));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: const Size(50, 32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        backgroundColor: isDark ? Colors.white12 : Colors.black12,
                        foregroundColor: isDark ? Colors.white : Colors.black,
                      ),
                      child: Text(timeOfDay.format(context), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Transform.scale(
                    scale: 0.9,
                    child: CupertinoSwitch(
                      activeTrackColor: Colors.orangeAccent,
                      value: state.reminderEnabled,
                      onChanged: (v) async {
                        final success = await vm.setReminderEnabled(v);
                        if (!success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification permission required. Please grant permission in app settings.')));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            _buildTile(
              context: context,
              icon: Icons.emoji_emotions_rounded,
              iconColor: Colors.tealAccent,
              title: 'Mood Library',
              subtitle: '${diaryVm.availableMoods.length} moods available',
              onTap: () {
                showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => const MoodManagementBottomSheet());
              },
            ),
          ]),

          _buildSectionHeader('Data & Privacy'),
          _buildSection(context, [
            _buildTile(
              context: context,
              icon: Icons.cloud_sync_rounded,
              iconColor: Colors.greenAccent,
              title: 'Export & Import Data',
              subtitle: 'Backup your data or restore from another device',
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => ExportImportDialog(
                    onDataImported: () {
                      diaryVm.load();
                    },
                  ),
                );
              },
            ),
            _buildTile(
              context: context,
              icon: Icons.privacy_tip_rounded,
              iconColor: Colors.purpleAccent,
              title: 'Privacy Policy',
              subtitle: 'View our privacy policy',
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => const PrivacyPolicyWebViewPage()));
              },
            ),
          ]),

          _buildSectionHeader('About'),
          _buildSection(context, [
            _buildTile(
              context: context,
              icon: Icons.code_rounded,
              iconColor: Colors.grey,
              title: 'GitHub',
              subtitle: 'View source code on GitHub',
              trailing: const Icon(Icons.open_in_new_rounded, color: Colors.grey, size: 20),
              onTap: () async {
                final uri = Uri.parse('https://github.com/kargalar/video_diary');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            if (kDebugMode)
              _buildTile(
                context: context,
                icon: Icons.bug_report_rounded,
                iconColor: Colors.redAccent,
                title: 'Debug',
                subtitle: 'Test notifications and diagnostics',
                onTap: () {
                  AppRoutes.goToDebug(context);
                },
              ),
          ]),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Version 1.2.6+22',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
