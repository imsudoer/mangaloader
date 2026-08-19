import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:path_provider/path_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/services/update_checker.dart';

class StreakNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const int streakNotificationId = 777;
  static const int updateNotificationId = 888;

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

  static Future<void> showUpdateNotificationOnce(AppUpdateInfo info, {bool isRu = true}) async {
    if (!_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final markerFile = File('${appDir.path}/last_notified_update.txt');
      if (markerFile.existsSync()) {
        final lastNotified = await markerFile.readAsString();
        if (lastNotified.trim() == info.tagName.trim()) {
          return;
        }
      }

      final tag = info.tagName.startsWith('v') ? info.tagName : 'v${info.tagName}';
      final title = isRu
          ? 'Доступно обновление MangaLoader $tag'
          : 'MangaLoader update $tag is available';
      final body = isRu
          ? 'Вышла новая версия приложения с улучшениями. Нажмите, чтобы обновиться.'
          : 'A new version with improvements is available. Tap to update.';

      const androidDetails = AndroidNotificationDetails(
        'app_updates',
        'Обновления приложения',
        channelDescription: 'Уведомления о выходе новых версий MangaLoader',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );

      await _notifications.show(
        updateNotificationId,
        title,
        body,
        notificationDetails,
      );

      await markerFile.writeAsString(info.tagName.trim());
    } catch (e) {
      debugPrint('Error showing update notification: $e');
    }
  }

  static Future<void> showChapterUpdateNotification({
    required int mangaId,
    required String mangaTitle,
    required String chapterInfo,
    bool isRu = true,
  }) async {
    if (!_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      final title = isRu ? 'Вышла новая глава!' : 'New Chapter Released!';
      final body = '$mangaTitle — $chapterInfo';

      const androidDetails = AndroidNotificationDetails(
        'chapter_updates',
        'Новые главы',
        channelDescription: 'Уведомления о выходе новых глав отслеживаемой манги',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );

      await _notifications.show(
        (10000 + (mangaId % 50000)).toInt(),
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error showing chapter notification: $e');
    }
  }

  static Future<void> cancelReminder() async {
    if (!_initialized) return;
    try {
      await _notifications.cancel(streakNotificationId);
    } catch (_) {}
  }
}
