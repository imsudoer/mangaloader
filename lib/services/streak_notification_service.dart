import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;

class StreakNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const int streakNotificationId = 777;

  static Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;

    try {
      tz.initializeTimeZones();

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _notifications.initialize(initSettings);

      // Request permission on Android 13+ and iOS
      if (Platform.isAndroid) {
        final androidImpl = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.requestNotificationsPermission();
      } else if (Platform.isIOS || Platform.isMacOS) {
        final iosImpl = _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
      }

      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing StreakNotificationService: $e');
    }
  }

  static Future<void> scheduleDailyStreakReminder({bool isRu = true, bool enabled = true}) async {
    if (!enabled || !_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      final streak = await rust_storage.getReadingStreak();
      if (streak.isActiveToday) {
        // Already read today! Cancel today's notification
        await _notifications.cancel(streakNotificationId);
        return;
      }

      final days = streak.currentStreak.toInt();
      final title = isRu ? 'Твой огонёк может погаснуть!' : 'Your reading flame might go out!';
      final body = days > 0
          ? (isRu
              ? 'Сохрани свой стрик в $days ${days == 1 ? "день" : (days < 5 ? "дня" : "дней")} — прочитай главу прямо сейчас.'
              : 'Keep your $days-day streak burning — read a chapter now.')
          : (isRu
              ? 'Зажги свой ежедневный огонёк чтения! Прочитай 1 главу.'
              : 'Ignite your daily reading flame! Read 1 chapter.');

      const androidDetails = AndroidNotificationDetails(
        'streak_reminders',
        'Напоминания об огоньке',
        channelDescription: 'Ежедневные уведомления для поддержания стрика чтения',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );

      // Schedule for 20:00 (8 PM) today or tomorrow
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 0);
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await _notifications.zonedSchedule(
        streakNotificationId,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Error scheduling streak reminder: $e');
    }
  }

  static Future<void> cancelReminder() async {
    if (!_initialized) return;
    try {
      await _notifications.cancel(streakNotificationId);
    } catch (_) {}
  }
}
