import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Device-local scheduled reminders. Moscow is the app's default business
/// timezone; the notification OS scheduler persists alarms across app closure.
class CalendarReminderService {
  CalendarReminderService._();
  static final CalendarReminderService instance = CalendarReminderService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final notificationsGranted =
        await android?.requestNotificationsPermission() ?? true;
    if (!notificationsGranted) return false;
    // Exact-alarm access is special on Android 12+. If it is not granted,
    // use an inexact alarm rather than failing to save the reminder.
    await android?.requestExactAlarmsPermission();
    return true;
  }

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    await initialize();
    final scheduled = tz.TZDateTime.from(at, tz.local);
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) {
      throw ArgumentError('Время напоминания должно быть в будущем.');
    }
    const androidDetails = AndroidNotificationDetails(
      'faezagro_calendar_alarm',
      'Напоминания календаря',
      channelDescription: 'Звуковые напоминания о работах в теплице',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final exactAllowed = await android?.canScheduleExactNotifications() ?? false;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'calendar:$id',
    );
  }

  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id);
  }

  Future<List<PendingNotificationRequest>> pending() async {
    await initialize();
    return _plugin.pendingNotificationRequests();
  }
}
