import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tapped logic if needed
      },
    );
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    final tz.TZDateTime tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);

    if (tzScheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      return; // Skip past dates
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'nyro_study_channel',
      'NYRO Study Notifications',
      channelDescription: 'Alerts and reminders for GATE lectures and revisions',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduled,
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> scheduleDailySessionAlerts({
    bool morning = true,
    bool afternoon = true,
    bool evening = true,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'nyro_daily_channel',
      'Daily Study Routine',
      channelDescription: 'Scheduled reminders for Morning, Afternoon, and Evening blocks',
      importance: Importance.high,
      priority: Priority.high,
    );
    const platformDetails = NotificationDetails(android: androidDetails);

    final now = tz.TZDateTime.now(tz.local);

    // 1. Morning Block at 5:00 AM (ID: 9001)
    if (morning) {
      var morningTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, 5, 0);
      if (morningTime.isBefore(now)) {
        morningTime = morningTime.add(const Duration(days: 1));
      }
      await flutterLocalNotificationsPlugin.zonedSchedule(
        9001,
        'Morning Study Brief (05:00 AM)',
        'Rise and conquer: Review your target lectures and Ebbinghaus recall items for today!',
        morningTime,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } else {
      await cancelNotification(9001);
    }

    // 2. Afternoon Session at 1:30 PM (ID: 9002)
    if (afternoon) {
      var afternoonTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, 13, 30);
      if (afternoonTime.isBefore(now)) {
        afternoonTime = afternoonTime.add(const Duration(days: 1));
      }
      await flutterLocalNotificationsPlugin.zonedSchedule(
        9002,
        'Afternoon Session (01:30 PM)',
        'Time for Afternoon & Aptitude Block. Stay focused on your GATE target!',
        afternoonTime,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } else {
      await cancelNotification(9002);
    }

    // 3. Evening Review at 7:00 PM (ID: 9003)
    if (evening) {
      var eveningTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, 19, 0);
      if (eveningTime.isBefore(now)) {
        eveningTime = eveningTime.add(const Duration(days: 1));
      }
      await flutterLocalNotificationsPlugin.zonedSchedule(
        9003,
        'Evening Review & Recall (07:00 PM)',
        'Wrap up today’s lectures, log tricky quiz mistakes, and clear Day 1/4/7 recall checkpoints.',
        eveningTime,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } else {
      await cancelNotification(9003);
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}
