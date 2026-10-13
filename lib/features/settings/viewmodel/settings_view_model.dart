import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../services/notification_service.dart';
import '../data/settings_repository.dart';
import '../model/settings.dart';

class SettingsViewModel extends ChangeNotifier {
  final SettingsRepository _repo;
  final NotificationService _notifier;

  SettingsModel _state = SettingsModel.def;
  SettingsModel get state => _state;
  SettingsRepository get repo => _repo;

  SettingsViewModel(this._repo, this._notifier) {
    _repo.onSettingsChanged.listen((newSettings) {
      _state = newSettings;
      notifyListeners();
    });
  }

  Future<void> load() async {
    _state = await _repo.load();
    notifyListeners();
  }

  Future<void> loadSettings() async {
    _state = await _repo.load();
    notifyListeners();
  }

  Future<void> setReminder(int hour, int minute) async {
    _state = _state.copyWith(reminderHour: hour, reminderMinute: minute);
    await _repo.save(_state);

    // Only schedule if enabled
    if (_state.reminderEnabled) {
      await _requestNotificationPermission();
      await _notifier.init();
      await _notifier.scheduleWeeklyNotifications(hour, minute);
    }
    notifyListeners();
  }

  Future<bool> setReminderEnabled(bool enabled) async {
    // Check permission when enabling
    if (enabled) {
      final hasPermission = await _requestNotificationPermission();
      if (!hasPermission) {
        // Permission denied, open settings
        await openAppSettings();
        return false;
      }

      // Schedule notification
      await _notifier.init();
      await _notifier.scheduleWeeklyNotifications(_state.reminderHour, _state.reminderMinute);
    } else {
      // Disable notifications
      await _notifier.cancelAll();
    }

    _state = _state.copyWith(reminderEnabled: enabled);
    await _repo.save(_state);
    notifyListeners();
    return true;
  }

  Future<bool> _requestNotificationPermission() async {
    final p = await Permission.notification.request();
    return p.isGranted || p.isLimited;
  }

  Future<void> setLandscape(bool value) async {
    _state = _state.copyWith(landscape: value);
    await _repo.save(_state);
    notifyListeners();
  }

  Future<bool> clearAllVideos(Future<bool> Function() clearAllCallback) async {
    return await clearAllCallback();
  }

  /// Test method for debug mode - sends a test notification immediately
  Future<void> sendTestNotification() async {
    try {
      await _notifier.init();
      await _notifier.sendTestNotification();
    } catch (e) {
      debugPrint('Error sending test notification: $e');
    }
  }

  /// Test method for debug mode - schedules a test notification for 5 seconds from now
  Future<void> scheduleTestNotificationIn5Seconds() async {
    try {
      await _notifier.init();
      await _notifier.scheduleTestNotificationIn5Seconds();
    } catch (e) {
      debugPrint('Error scheduling test notification: $e');
    }
  }

  /// Get diagnostic information about notifications
  Future<Map<String, dynamic>> getDiagnostics() async {
    return await _notifier.diagnostics();
  }

  /// Set storage directory (for import operations)
  Future<void> setStorageDirectory(String directory) async {
    _state = _state.copyWith(storageDirectory: directory);
    await _repo.save(_state);
    notifyListeners();
  }
}
