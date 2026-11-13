import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:path_provider/path_provider.dart';
import 'package:mangaloader/providers/settings_provider.dart' show QuietHours;
import 'package:mangaloader/l10n/strings/notification_strings.dart';
import 'package:mangaloader/services/notification_navigation.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/utils/plural.dart';
import 'package:mangaloader/theme/app_tokens.dart';

class StreakNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const int streakNotificationId = 777;
  static const int updateNotificationId = 888;
  static const int chapterDigestNotificationId = 889;

  /// Merge buffer for chapters that must not trigger a separate notification.
  /// It lives in settings instead of memory because the background worker is a
  /// separate isolate with no provider container and no shared statics.
  static const String digestStateKey = 'chapter_digest_state';
  static const String quietHoursSettingKey = 'quiet_hours';
  static const String chapterDigestSettingKey = 'chapter_digest';

  static Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;

    try {
      tz.initializeTimeZones();

      const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
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

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) =>
            NotificationNavigation.handlePayload(response.payload),
      );

      // Request permission on Android 13+ and iOS
      if (Platform.isAndroid) {
        final androidImpl = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.requestNotificationsPermission();
      } else if (Platform.isIOS || Platform.isMacOS) {
        final iosImpl = _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
      }

      _initialized = true;
      await _handleColdStartLaunch();
    } catch (e) {
      debugPrint('Error initializing StreakNotificationService: $e');
    }
  }

  /// A tap that started the app never reaches `onDidReceiveNotificationResponse`,
  /// so the launch payload has to be read once at startup.
  static Future<void> _handleColdStartLaunch() async {
    try {
      final details = await _notifications.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final payload = details?.notificationResponse?.payload;
      if (payload == null || payload.isEmpty) return;
      _dispatchLaunchPayload(payload);
    } catch (e) {
      debugPrint('Error reading notification launch details: $e');
    }
  }

  /// main() attaches the GoRouter right after [init] and the first frame runs
  /// after that, so routing from the post-frame callback always sees the router.
  static void _dispatchLaunchPayload(String payload) {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationNavigation.handlePayload(payload);
      });
    } catch (e) {
      debugPrint('Error dispatching notification payload: $e');
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
      final s = NotificationStrings(isRu);
      final title = s.streakTitle;
      final body = days > 0
          ? (isRu
              ? s.streakBodyWithDays(Plural.days(days, 'ru'))
              : s.streakBodyWithDays('$days'))
          : s.streakBodyNoDays;

      const androidDetails = AndroidNotificationDetails(
        'streak_reminders',
        'Напоминания об огоньке',
        channelDescription: 'Ежедневные уведомления для поддержания стрика чтения',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
        color: AppTokens.accent,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );

      // Schedule for 20:00 local wall-clock time. tz.local is UTC unless a location is
      // registered explicitly, so the absolute instant is computed from the local clock
      // offset; otherwise the reminder fired three hours late in Moscow and similar zones.
      final now = DateTime.now();
      var localTarget = DateTime(now.year, now.month, now.day, 20, 0);
      if (!localTarget.isAfter(now)) {
        localTarget = localTarget.add(const Duration(days: 1));
      }
      final scheduledDate = tz.TZDateTime.now(tz.UTC).add(localTarget.difference(now));

      await _notifications.zonedSchedule(
        streakNotificationId,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: NotificationNavigation.streakPayload,
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
        icon: '@drawable/ic_notification',
        color: AppTokens.accent,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
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
        payload: NotificationNavigation.updatePayload,
      );

      await markerFile.writeAsString(info.tagName.trim());
    } catch (e) {
      debugPrint('Error showing update notification: $e');
    }
  }

  /// Posts a per-chapter notification, unless quiet hours are active or the user
  /// asked for one daily digest — then the event is merged into [digestStateKey]
  /// and posted later by [flushDigestIfDue].
  static Future<void> showChapterUpdateNotification({
    required int mangaId,
    required String mangaTitle,
    required String chapterInfo,
    bool isRu = true,
    String? slugUrl,
  }) async {
    if (!_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final slug = (slugUrl ?? '').trim();

    try {
      final quietHours = await _readQuietHours();
      final digestEnabled = await _readBoolSetting(chapterDigestSettingKey);

      if (digestEnabled || quietHours.contains(DateTime.now())) {
        await _appendToDigest(title: mangaTitle, chapter: chapterInfo, slug: slug);
        return;
      }

      final title = NotificationStrings(isRu).newChapterTitle;
      final body = '$mangaTitle — $chapterInfo';

      const androidDetails = AndroidNotificationDetails(
        'chapter_updates',
        'Новые главы',
        channelDescription: 'Уведомления о выходе новых глав отслеживаемой манги',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
        color: AppTokens.accent,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
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
        payload: slug.isEmpty ? null : '${NotificationNavigation.chapterPrefix}$slug',
      );
    } catch (e) {
      debugPrint('Error showing chapter notification: $e');
    }
  }

  /// Posts the merged summary once quiet hours are over. Safe to call from both
  /// the foreground tick and the background worker: it is a no-op when nothing
  /// is pending, the night is still running, or today's digest was already sent.
  static Future<void> flushDigestIfDue({bool isRu = true}) async {
    if (!_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      final now = DateTime.now();
      final quietHours = await _readQuietHours();
      if (quietHours.contains(now)) return;

      final today = _dateKey(now);
      final state = await _readDigestState();
      if (state.date != today) {
        // Yesterday's leftovers must not leak into today's summary.
        if (state.entries.isNotEmpty) {
          await _writeDigestState(_DigestState(date: today, postedDate: state.postedDate, entries: const []));
        }
        return;
      }
      if (state.entries.isEmpty) return;
      if (state.postedDate == today) return;

      final total = state.entries.length;
      final preview = state.entries.take(3).map((e) => '${e.title} — ${e.chapter}').join('\n');
      final remaining = total - 3;
      final s = NotificationStrings(isRu);
      final body = remaining > 0
          ? '$preview\n${s.digestMore('$remaining')}'
          : preview;
      final title = s.digestTitle('$total');
      final firstSlug = state.entries.first.slug;

      final androidDetails = AndroidNotificationDetails(
        'chapter_updates',
        'Новые главы',
        channelDescription: 'Уведомления о выходе новых глав отслеживаемой манги',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
        color: AppTokens.accent,
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(body),
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      );

      await _notifications.show(
        chapterDigestNotificationId,
        title,
        body,
        notificationDetails,
        payload: firstSlug.isEmpty ? null : '${NotificationNavigation.chapterPrefix}$firstSlug',
      );

      await _writeDigestState(_DigestState(date: today, postedDate: today, entries: const []));
    } catch (e) {
      debugPrint('Error flushing chapter digest: $e');
    }
  }

  static Future<void> cancelReminder() async {
    if (!_initialized) return;
    try {
      await _notifications.cancel(streakNotificationId);
    } catch (_) {}
  }

  static Future<void> _appendToDigest({
    required String title,
    required String chapter,
    required String slug,
  }) async {
    final today = _dateKey(DateTime.now());
    final state = await _readDigestState();
    final entries = state.date == today
        ? List<_DigestEntry>.from(state.entries)
        : <_DigestEntry>[];
    final entry = _DigestEntry(title: title, chapter: chapter, slug: slug);
    if (!entries.any((e) => e.signature == entry.signature)) {
      entries.add(entry);
    }
    await _writeDigestState(
      _DigestState(date: today, postedDate: state.postedDate, entries: entries),
    );
  }

  static Future<_DigestState> _readDigestState() async {
    final raw = await _readSetting(digestStateKey);
    if (raw == null || raw.isEmpty) return _DigestState.empty;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final rawEntries = json['entries'];
      final entries = rawEntries is List
          ? rawEntries
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => _DigestEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <_DigestEntry>[];
      return _DigestState(
        date: json['date'] as String? ?? '',
        postedDate: json['posted'] as String?,
        entries: entries,
      );
    } catch (e) {
      debugPrint('Corrupted chapter digest state: $e');
      return _DigestState.empty;
    }
  }

  static Future<void> _writeDigestState(_DigestState state) async {
    await _writeSetting(
      digestStateKey,
      jsonEncode({
        'date': state.date,
        'posted': state.postedDate,
        'entries': state.entries.map((e) => e.toJson()).toList(),
      }),
    );
  }

  static Future<QuietHours> _readQuietHours() async {
    final raw = await _readSetting(quietHoursSettingKey);
    if (raw == null || raw.isEmpty) return const QuietHours();
    try {
      return QuietHours.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Corrupted quiet hours settings: $e');
      return const QuietHours();
    }
  }

  static Future<bool> _readBoolSetting(String key) async =>
      (await _readSetting(key)) == 'true';

  static Future<String?> _readSetting(String key) async {
    try {
      return await rust_storage.getSetting(key: key);
    } catch (e) {
      debugPrint('Error reading setting "$key": $e');
      return null;
    }
  }

  static Future<void> _writeSetting(String key, String value) async {
    try {
      await rust_storage.setSetting(key: key, value: value);
    } catch (e) {
      debugPrint('Error writing setting "$key": $e');
    }
  }

  static String _dateKey(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }
}

class _DigestEntry {
  const _DigestEntry({required this.title, required this.chapter, required this.slug});

  final String title;
  final String chapter;
  final String slug;

  /// Two chapters of the same title can share a number after a re-upload, so
  /// the title is part of the identity.
  String get signature => '$title\u0000$chapter';

  Map<String, dynamic> toJson() => {'title': title, 'chapter': chapter, 'slug': slug};

  factory _DigestEntry.fromJson(Map<String, dynamic> json) => _DigestEntry(
        title: json['title'] as String? ?? '',
        chapter: json['chapter'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
      );
}

class _DigestState {
  const _DigestState({required this.date, required this.entries, this.postedDate});

  final String date;
  final String? postedDate;
  final List<_DigestEntry> entries;

  static const _DigestState empty = _DigestState(date: '', entries: []);
}