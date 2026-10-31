import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String studyChannelId = 'nyro_study_channel';
  static const String studyChannelName = 'NYRO Study Notifications';
  static const String dailyChannelId = 'nyro_daily_channel';
  static const String dailyChannelName = 'Daily Study Routine';

  Future<void> init() async {
    _configureLocalTimeZone();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tapped
      },
    );

    // Create Notification Channels explicitly on Android 8.0+
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          studyChannelId,
          studyChannelName,
          description: 'Alerts and reminders for GATE study tasks, custom reminders, and revisits',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          dailyChannelId,
          dailyChannelName,
          description: 'Scheduled reminders for Morning, Afternoon, and Evening study blocks',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    await requestPermissions();
  }

  void _configureLocalTimeZone() {
    tz_data.initializeTimeZones();
    try {
      final offset = DateTime.now().timeZoneOffset;
      // Match timezone database against current system offset
      for (final entry in tz.timeZoneDatabase.locations.entries) {
        final loc = entry.value;
        final nowInLoc = tz.TZDateTime.now(loc);
        if (nowInLoc.timeZoneOffset == offset) {
          tz.setLocalLocation(loc);
          return;
        }
      }
    } catch (_) {}
  }

  Future<bool> requestPermissions() async {
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
    return granted ?? false;
  }

  // Instant notification for testing permissions & channels
  Future<void> showInstantNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      studyChannelId,
      studyChannelName,
      channelDescription: 'Alerts and reminders for GATE study tasks',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      platformDetails,
    );
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    var tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);
    final now = tz.TZDateTime.now(tz.local);

    // If the scheduled time is slightly in the past (e.g. user set it for current minute),
    // bump it by 5 seconds so it fires immediately instead of being discarded
    if (tzScheduled.isBefore(now)) {
      if (now.difference(tzScheduled).inMinutes <= 5) {
        tzScheduled = now.add(const Duration(seconds: 5));
      } else {
        return; // Skip past dates
      }
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      studyChannelId,
      studyChannelName,
      channelDescription: 'Alerts and reminders for GATE study tasks',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
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
    } catch (e) {
      // Fallback if exact alarms permission is not granted on Android 12+
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzScheduled,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> scheduleDailySessionAlerts({
    bool morning = true,
    bool afternoon = true,
    bool evening = true,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      dailyChannelId,
      dailyChannelName,
      channelDescription: 'Scheduled reminders for Morning, Afternoon, and Evening blocks',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const platformDetails = NotificationDetails(android: androidDetails);

    final now = tz.TZDateTime.now(tz.local);

    // 1. Morning Block at 5:00 AM (ID: 9001)
    if (morning) {
      var morningTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, 5, 0);
      if (morningTime.isBefore(now)) {
        morningTime = morningTime.add(const Duration(days: 1));
      }
      try {
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
      } catch (_) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          9001,
          'Morning Study Brief (05:00 AM)',
          'Rise and conquer: Review your target lectures and Ebbinghaus recall items for today!',
          morningTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } else {
      await cancelNotification(9001);
    }

    // 2. Afternoon Session at 1:30 PM (ID: 9002)
    if (afternoon) {
      var afternoonTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, 13, 30);
      if (afternoonTime.isBefore(now)) {
        afternoonTime = afternoonTime.add(const Duration(days: 1));
      }
      try {
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
      } catch (_) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          9002,
          'Afternoon Session (01:30 PM)',
          'Time for Afternoon & Aptitude Block. Stay focused on your GATE target!',
          afternoonTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } else {
      await cancelNotification(9002);
    }

    // 3. Evening Review at 7:00 PM (ID: 9003)
    if (evening) {
      var eveningTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, 19, 0);
      if (eveningTime.isBefore(now)) {
        eveningTime = eveningTime.add(const Duration(days: 1));
      }
      try {
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
      } catch (_) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          9003,
          'Evening Review & Recall (07:00 PM)',
          'Wrap up today’s lectures, log tricky quiz mistakes, and clear Day 1/4/7 recall checkpoints.',
          eveningTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
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
