import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const String _channelId = 'daily_video_diary_v2';
  static const String _channelName = 'Daily Reminder';

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    const windows = WindowsInitializationSettings(appName: 'Video Diary', appUserModelId: 'app.videodiary', guid: 'e0e87d60-3b0f-4ff2-8d85-0a9c8ebdb5a9');
    const initSettings = InitializationSettings(android: android, iOS: iOS, windows: windows);
    await _plugin.initialize(initSettings);

    // Ensure Android channel exists (some OEMs/Release builds can be picky)
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(_channelId, _channelName, description: 'Daily reminder to record your video diary', importance: Importance.max));

    // timezone init
    try {
      tz.initializeTimeZones();
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (_) {
      // Fallback
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    _initialized = true;
  }

  /// Schedule notifications for the next 7 days at the specified time
  /// Uses zonedSchedule (scheduled notifications) instead of daily repeating notifications
  /// because scheduled notifications are more reliable on most Android devices
  Future<void> scheduleWeeklyNotifications(int hour, int minute) async {
    // Ensure initialization
    if (!_initialized) {
      await init();
    }

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(_channelId, _channelName, channelDescription: 'Daily reminder to record your video diary', importance: Importance.max, priority: Priority.high, fullScreenIntent: true),
      iOS: const DarwinNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );

    await _ensureAndroidPermissions();

    // Cancel all existing scheduled notifications first
    for (int i = 0; i < 7; i++) {
      await _plugin.cancel(1001 + i);
    }

    final now = tz.TZDateTime.now(tz.local);
    int scheduledCount = 0;

    // Check if a video was already recorded today
    final prefs = await SharedPreferences.getInstance();
    final lastRecordedDayStr = prefs.getString('last_recorded_day');
    bool skipToday = false;
    if (lastRecordedDayStr != null) {
      final lastRecordedDay = DateTime.tryParse(lastRecordedDayStr);
      if (lastRecordedDay != null) {
        if (lastRecordedDay.year == now.year && lastRecordedDay.month == now.month && lastRecordedDay.day == now.day) {
          skipToday = true;
        }
      }
    }

    // Schedule notifications for the next 7 days
    for (int i = 0; i < 7; i++) {
      if (i == 0 && skipToday) {
        continue;
      }
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      scheduled = scheduled.add(Duration(days: i));

      // Only schedule future notifications
      if (scheduled.isAfter(now)) {
        try {
          await _plugin.zonedSchedule(1001 + i, 'Video Diary', 'Don\'t forget to record today\'s video', scheduled, details, androidScheduleMode: AndroidScheduleMode.exact);
          scheduledCount++;
        } catch (e) {
          // Fallback to inexact if exact fails (e.g., on systems with exact alarm restrictions)
          try {
            await _plugin.zonedSchedule(1001 + i, 'Video Diary', 'Don\'t forget to record today\'s video', scheduled, details, androidScheduleMode: AndroidScheduleMode.inexact);
            scheduledCount++;
          } catch (_) {
            // Failed to schedule this notification
          }
        }
      }
    }

    // Log scheduled count for debugging
    if (scheduledCount > 0) {
      // Successfully scheduled notifications
    }
  }

  /// Reschedule notifications if needed (call on app launch)
  /// This should be called on every app launch to ensure notifications are always scheduled
  Future<void> rescheduleIfNeeded(bool enabled, int hour, int minute) async {
    // Ensure initialization before scheduling
    if (!_initialized) {
      await init();
    }

    if (enabled) {
      await scheduleWeeklyNotifications(hour, minute);
    } else {
      await cancelAll();
    }
  }

  /// Cancels the notification scheduled for today (ID `1001`)
  Future<void> cancelTodayNotification() async {
    await _plugin.cancel(1001);
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  /// Schedule a test notification for 5 seconds from now (for debugging)
  Future<void> scheduleTestNotificationIn5Seconds() async {
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(_channelId, _channelName, channelDescription: 'Daily reminder to record your video diary', importance: Importance.max, priority: Priority.high, fullScreenIntent: true),
      iOS: const DarwinNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );

    final now = tz.TZDateTime.now(tz.local);
    final scheduled = now.add(const Duration(seconds: 5));

    await _ensureAndroidPermissions();
    // Schedule for exact time (5 seconds from now)
    await _plugin.cancel(9998);
    try {
      await _plugin.zonedSchedule(9998, 'Video Diary Test (Scheduled)', 'This notification was scheduled for 5 seconds from now', scheduled, details, androidScheduleMode: AndroidScheduleMode.exact);
    } catch (e) {
      // Fallback to inexact if exact fails
      await _plugin.zonedSchedule(9998, 'Video Diary Test (Scheduled)', 'This notification was scheduled for 5 seconds from now', scheduled, details, androidScheduleMode: AndroidScheduleMode.inexact);
    }
  }

  /// Send an immediate test notification (for debugging)
  Future<void> sendTestNotification() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(_channelId, _channelName, channelDescription: 'Daily reminder to record your video diary', importance: Importance.max, priority: Priority.high),
      iOS: DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );

    await _ensureAndroidPermissions();
    await _plugin.show(9999, 'Video Diary Test', 'This is a test notification. Your daily reminders are working!', details);
  }

  Future<Map<String, dynamic>> diagnostics() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    bool? notifEnabled;
    try {
      notifEnabled = await android?.areNotificationsEnabled();
    } catch (_) {}
    return {'initialized': _initialized, 'timezone': tz.local.name, 'androidNotificationsEnabled': notifEnabled, 'channelId': _channelId};
  }

  Future<void> _ensureAndroidPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    try {
      await android?.requestNotificationsPermission();
      // Request exact alarm permission for precise notification delivery
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
  }
}
