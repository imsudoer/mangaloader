import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/services/update_downloader.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';

// Helper function to load all settings into providers upon app launch
Future<void> loadPersistentSettings(WidgetRef ref) async {
  try {
    final settings = await rust_storage.getAllSettings();
    final map = {for (var item in settings) item.key: item.value};

    // 1. Theme mode
    if (map.containsKey('theme_mode')) {
      final val = map['theme_mode']!;
      if (val == 'light') {
        ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light, persist: false);
      } else if (val == 'system') {
        ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system, persist: false);
      } else {
        ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark, persist: false);
      }
    }

    // 2. AMOLED Mode
    if (map.containsKey('amoled_mode')) {
      ref.read(amoledModeProvider.notifier).setAmoled(map['amoled_mode'] == 'true', persist: false);
    }

    // 3. Locale
    if (map.containsKey('locale')) {
      final code = map['locale']!;
      if (code == 'ru' || code == 'en') {
        ref.read(localeProvider.notifier).setLocale(Locale(code), persist: false);
      } else {
        ref.read(localeProvider.notifier).setLocale(null, persist: false);
      }
    }

    // 4. Auto check updates
    if (map.containsKey('auto_check_updates')) {
      ref.read(autoCheckUpdatesProvider.notifier).setAutoCheck(map['auto_check_updates'] == 'true', persist: false);
    }

    // 4.1 Update channel
    if (map.containsKey('update_channel')) {
      final ch = map['update_channel'] == 'beta' ? UpdateChannel.beta : UpdateChannel.stable;
      ref.read(updateChannelProvider.notifier).setChannel(ch, persist: false);
    }

    // 5. Download Concurrency
    if (map.containsKey('download_concurrency_images')) {
      ref.read(downloadConcurrencyImagesProvider.notifier).setConcurrency(
          int.tryParse(map['download_concurrency_images']!) ?? 10, persist: false);
    }
    if (map.containsKey('download_concurrency_chapters')) {
      ref.read(downloadConcurrencyChaptersProvider.notifier).setConcurrency(
          int.tryParse(map['download_concurrency_chapters']!) ?? 3, persist: false);
    }

    // 6. Auto clear cache days
    if (map.containsKey('auto_clear_cache_days')) {
      ref.read(autoClearCacheDaysProvider.notifier).setDays(
          int.tryParse(map['auto_clear_cache_days']!) ?? 7, persist: false);
    }

    // 7. Streak notifications
    if (map.containsKey('streak_notifications_enabled')) {
      ref.read(streakNotificationsEnabledProvider.notifier).setEnabled(
          map['streak_notifications_enabled'] == 'true', persist: false);
    }

    // 8. Smart auto download count
    if (map.containsKey('smart_auto_download_count')) {
      ref.read(smartAutoDownloadCountProvider.notifier).setCount(
          int.tryParse(map['smart_auto_download_count']!) ?? 0, persist: false);
    }

    // 9. Auto delete read chapters
    if (map.containsKey('auto_delete_read_chapters')) {
      ref.read(autoDeleteReadChaptersProvider.notifier).setAutoDelete(
          map['auto_delete_read_chapters'] == 'true', persist: false);
    }

    // 10. Chapter notifications
    if (map.containsKey('chapter_notifications_enabled')) {
      ref.read(chapterNotificationsEnabledProvider.notifier).setEnabled(
          map['chapter_notifications_enabled'] == 'true', persist: false);
    }

    // 11. Search history
    if (map.containsKey('search_history')) {
      try {
        final list = List<String>.from(jsonDecode(map['search_history']!));
        ref.read(searchHistoryProvider.notifier).loadHistory(list);
      } catch (_) {}
    }

    // 12. Reader preferences (reading mode, scale, filters)
    if (map.containsKey('reader_prefs')) {
      try {
        final raw = map['reader_prefs']!;
        if (raw.isNotEmpty) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          ref.read(readerPrefsProvider.notifier).load(ReaderPrefs.fromJson(json));
        }
      } catch (_) {}
    }

    // 12.1 Per-title reader overrides
    if (map.containsKey('reader_prefs_titles')) {
      try {
        final raw = map['reader_prefs_titles']!;
        if (raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final overrides = decoded.map(
            (key, value) => MapEntry(
              key,
              ReaderPrefs.fromJson(value as Map<String, dynamic>),
            ),
          );
          ref.read(titleReaderPrefsProvider.notifier).load(overrides);
        }
      } catch (_) {}
    }

    // 12.2 Downloads
    if (map.containsKey('downloads_wifi_only')) {
      ref.read(wifiOnlyDownloadsProvider.notifier).setEnabled(
            map['downloads_wifi_only'] == 'true',
            persist: false,
          );
    }
    if (map.containsKey('downloads_storage_limit_mb')) {
      ref.read(downloadsStorageLimitProvider.notifier).setLimitMb(
            int.tryParse(map['downloads_storage_limit_mb']!) ?? 0,
            persist: false,
          );
    }

    // 12.3 Notifications digest and quiet hours
    if (map.containsKey('quiet_hours')) {
      try {
        final raw = map['quiet_hours']!;
        if (raw.isNotEmpty) {
          ref.read(quietHoursProvider.notifier).load(
                QuietHours.fromJson(jsonDecode(raw) as Map<String, dynamic>),
              );
        }
      } catch (_) {}
    }
    if (map.containsKey('chapter_digest')) {
      ref.read(chapterDigestProvider.notifier).setEnabled(
            map['chapter_digest'] == 'true',
            persist: false,
          );
    }

    // 12.4 Automatic backup interval
    if (map.containsKey('auto_backup_interval_days')) {
      ref.read(autoBackupIntervalProvider.notifier).setDays(
            int.tryParse(map['auto_backup_interval_days']!) ?? 0,
            persist: false,
          );
    }

    // 13. Cookies & User Profile
    if (map.containsKey('cookies')) {
      final cookies = map['cookies']!;
      ref.read(cookiesProvider.notifier).setCookies(cookies, persist: false);
      if (cookies.isNotEmpty) {
        rust_api.setCookies(cookies: cookies);
      }
    }

    if (map.containsKey('user_profile')) {
      try {
        final json = jsonDecode(map['user_profile']!) as Map<String, dynamic>;
        ref.read(currentUserProfileProvider.notifier).setProfile(UserProfile(
          id: (json['id'] as num).toInt(),
          username: json['username'] as String,
          avatarUrl: json['avatar_url'] as String,
          createdAt: json['created_at'] as String?,
          loginStreak: (json['login_streak'] as num).toInt(),
        ), persist: false);
      } catch (_) {}
    }
  } catch (e) {
    debugPrint("Error loading persistent settings: $e");
  }
}

// 1. Theme mode provider with SQLite persistence
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark);

  void setThemeMode(ThemeMode mode, {bool persist = true}) {
    state = mode;
    if (persist) {
      final val = mode == ThemeMode.light ? 'light' : (mode == ThemeMode.system ? 'system' : 'dark');
      rust_storage.setSetting(key: 'theme_mode', value: val);
    }
  }

  void toggle() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setThemeMode(next);
  }
}

// 2. Pure AMOLED mode provider with persistence
final amoledModeProvider = StateNotifierProvider<AmoledModeNotifier, bool>(
  (ref) => AmoledModeNotifier(),
);

class AmoledModeNotifier extends StateNotifier<bool> {
  AmoledModeNotifier() : super(false);

  void setAmoled(bool value, {bool persist = true}) {
    state = value;
    if (persist) {
      rust_storage.setSetting(key: 'amoled_mode', value: value.toString());
    }
  }
}

// 3. Locale provider with persistence
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>(
  (ref) => LocaleNotifier(),
);

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier() : super(null);

  void setLocale(Locale? locale, {bool persist = true}) {
    state = locale;
    if (persist) {
      rust_storage.setSetting(key: 'locale', value: locale?.languageCode ?? 'system');
    }
  }
}

// 4. Auto update check provider
final autoCheckUpdatesProvider = StateNotifierProvider<AutoCheckUpdatesNotifier, bool>(
  (ref) => AutoCheckUpdatesNotifier(),
);

class AutoCheckUpdatesNotifier extends StateNotifier<bool> {
  AutoCheckUpdatesNotifier() : super(true);

  void setAutoCheck(bool val, {bool persist = true}) {
    state = val;
    if (persist) {
      rust_storage.setSetting(key: 'auto_check_updates', value: val.toString());
    }
  }
}

// 4.1. Update channel provider (Stable / Beta/Dev)
final updateChannelProvider = StateNotifierProvider<UpdateChannelNotifier, UpdateChannel>(
  (ref) => UpdateChannelNotifier(),
);

class UpdateChannelNotifier extends StateNotifier<UpdateChannel> {
  UpdateChannelNotifier() : super(UpdateChannel.stable);

  void setChannel(UpdateChannel channel, {bool persist = true}) {
    state = channel;
    if (persist) {
      rust_storage.setSetting(
        key: 'update_channel',
        value: channel == UpdateChannel.beta ? 'beta' : 'stable',
      );
    }
  }
}

final availableUpdateProvider = StateProvider<AppUpdateInfo?>((ref) => null);
final updateDownloadStateProvider = StateProvider<UpdateDownloadState>((ref) => const UpdateDownloadState());
final appVersionProvider = FutureProvider<String>((ref) async {
  return await UpdateChecker.getCurrentVersion();
});

// 5. Download Concurrency Providers with persistence
final downloadConcurrencyImagesProvider = StateNotifierProvider<ConcurrencyImagesNotifier, int>(
  (ref) => ConcurrencyImagesNotifier(),
);

class ConcurrencyImagesNotifier extends StateNotifier<int> {
  ConcurrencyImagesNotifier() : super(10);

  void setConcurrency(int val, {bool persist = true}) {
    state = val;
    if (persist) {
      rust_storage.setSetting(key: 'download_concurrency_images', value: val.toString());
    }
  }
}

final downloadConcurrencyChaptersProvider = StateNotifierProvider<ConcurrencyChaptersNotifier, int>(
  (ref) => ConcurrencyChaptersNotifier(),
);

class ConcurrencyChaptersNotifier extends StateNotifier<int> {
  ConcurrencyChaptersNotifier() : super(3);

  void setConcurrency(int val, {bool persist = true}) {
    state = val;
    if (persist) {
      rust_storage.setSetting(key: 'download_concurrency_chapters', value: val.toString());
    }
  }
}

// 6. Auto clear cache duration in days with persistence
final autoClearCacheDaysProvider = StateNotifierProvider<AutoClearCacheNotifier, int>(
  (ref) => AutoClearCacheNotifier(),
);

class AutoClearCacheNotifier extends StateNotifier<int> {
  AutoClearCacheNotifier() : super(7);

  void setDays(int val, {bool persist = true}) {
    state = val;
    if (persist) {
      rust_storage.setSetting(key: 'auto_clear_cache_days', value: val.toString());
    }
  }
}

// 7. Streak push notifications toggle with persistence
final streakNotificationsEnabledProvider = StateNotifierProvider<StreakNotificationsNotifier, bool>(
  (ref) => StreakNotificationsNotifier(),
);

class StreakNotificationsNotifier extends StateNotifier<bool> {
  StreakNotificationsNotifier() : super(true);

  void setEnabled(bool val, {bool persist = true}) {
    state = val;
    if (persist) {
      rust_storage.setSetting(key: 'streak_notifications_enabled', value: val.toString());
    }
  }
}

// 8. Smart Offline Auto-Download count with persistence
final smartAutoDownloadCountProvider = StateNotifierProvider<SmartAutoDownloadNotifier, int>(
  (ref) => SmartAutoDownloadNotifier(),
);

class SmartAutoDownloadNotifier extends StateNotifier<int> {
  SmartAutoDownloadNotifier() : super(0);

  void setCount(int val, {bool persist = true}) {
    state = val;
    if (persist) {
      rust_storage.setSetting(key: 'smart_auto_download_count', value: val.toString());
    }
  }
}

// 9. Auto-delete read downloaded chapters toggle with persistence
final autoDeleteReadChaptersProvider = StateNotifierProvider<AutoDeleteReadNotifier, bool>(
  (ref) => AutoDeleteReadNotifier(),
);

class AutoDeleteReadNotifier extends StateNotifier<bool> {
  AutoDeleteReadNotifier() : super(false);

  void setAutoDelete(bool val, {bool persist = true}) {
    state = val;
    if (persist) {
      rust_storage.setSetting(key: 'auto_delete_read_chapters', value: val.toString());
    }
  }
}

// 10. Background Chapter Updates Notifications toggle with persistence
final chapterNotificationsEnabledProvider = StateNotifierProvider<ChapterNotificationsNotifier, bool>(
  (ref) => ChapterNotificationsNotifier(),
);

class ChapterNotificationsNotifier extends StateNotifier<bool> {
  ChapterNotificationsNotifier() : super(true);

  void setEnabled(bool val, {bool persist = true}) {
    state = val;
    if (persist) {
      rust_storage.setSetting(key: 'chapter_notifications_enabled', value: val.toString());
    }
  }
}

// 11. Search History Provider with persistence
final searchHistoryProvider = StateNotifierProvider<SearchHistoryNotifier, List<String>>(
  (ref) => SearchHistoryNotifier(),
);

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super(const []);

  void loadHistory(List<String> list) {
    state = list;
  }

  void addQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final updated = [trimmed, ...state.where((q) => q.toLowerCase() != trimmed.toLowerCase())];
    if (updated.length > 12) {
      state = updated.sublist(0, 12);
    } else {
      state = updated;
    }
    rust_storage.setSetting(key: 'search_history', value: jsonEncode(state));
  }

  void removeQuery(String query) {
    state = state.where((q) => q != query).toList();
    rust_storage.setSetting(key: 'search_history', value: jsonEncode(state));
  }

  void clearAll() {
    state = const [];
    rust_storage.setSetting(key: 'search_history', value: '[]');
  }
}

// 13. Reader preferences (mode, scale, filters) persisted as a single JSON blob
class ReaderPrefs {
  final String mode;
  final String background;
  final String boxFit;
  final String dualPage;
  final String tapZones;
  final String colorFilter;
  final String sharpen;
  final bool cropBorders;
  final double cropPercent;
  final double brightness;
  final double autoScrollSpeed;

  /// How many pages ahead of the current one are preloaded (1-12).
  final int preloadRadius;

  const ReaderPrefs({
    this.mode = 'vertical',
    this.background = 'black',
    this.boxFit = 'contain',
    this.dualPage = 'auto',
    this.tapZones = 'standard',
    this.colorFilter = 'none',
    this.sharpen = 'off',
    this.cropBorders = false,
    this.cropPercent = 3.0,
    this.brightness = 1.0,
    this.autoScrollSpeed = 1.0,
    this.preloadRadius = 4,
  });

  ReaderPrefs copyWith({
    String? mode,
    String? background,
    String? boxFit,
    String? dualPage,
    String? tapZones,
    String? colorFilter,
    String? sharpen,
    bool? cropBorders,
    double? cropPercent,
    double? brightness,
    double? autoScrollSpeed,
    int? preloadRadius,
  }) {
    return ReaderPrefs(
      mode: mode ?? this.mode,
      background: background ?? this.background,
      boxFit: boxFit ?? this.boxFit,
      dualPage: dualPage ?? this.dualPage,
      tapZones: tapZones ?? this.tapZones,
      colorFilter: colorFilter ?? this.colorFilter,
      sharpen: sharpen ?? this.sharpen,
      cropBorders: cropBorders ?? this.cropBorders,
      cropPercent: cropPercent ?? this.cropPercent,
      brightness: brightness ?? this.brightness,
      autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
      preloadRadius: preloadRadius ?? this.preloadRadius,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'background': background,
        'boxFit': boxFit,
        'dualPage': dualPage,
        'tapZones': tapZones,
        'colorFilter': colorFilter,
        'sharpen': sharpen,
        'cropBorders': cropBorders,
        'cropPercent': cropPercent,
        'brightness': brightness,
        'autoScrollSpeed': autoScrollSpeed,
        'preloadRadius': preloadRadius,
      };

  factory ReaderPrefs.fromJson(Map<String, dynamic> json) {
    double readDouble(String key, double fallback) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    String readString(String key, String fallback) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : fallback;
    }

    return ReaderPrefs(
      mode: readString('mode', 'vertical'),
      background: readString('background', 'black'),
      boxFit: readString('boxFit', 'contain'),
      dualPage: readString('dualPage', 'auto'),
      tapZones: readString('tapZones', 'standard'),
      colorFilter: readString('colorFilter', 'none'),
      sharpen: readString('sharpen', 'off'),
      cropBorders: json['cropBorders'] == true,
      cropPercent: readDouble('cropPercent', 3.0),
      brightness: readDouble('brightness', 1.0),
      autoScrollSpeed: readDouble('autoScrollSpeed', 1.0),
      preloadRadius: (json['preloadRadius'] is num
              ? (json['preloadRadius'] as num).toInt()
              : 4)
          .clamp(1, 12),
    );
  }
}

final readerPrefsProvider = StateNotifierProvider<ReaderPrefsNotifier, ReaderPrefs>(
  (ref) => ReaderPrefsNotifier(),
);

class ReaderPrefsNotifier extends StateNotifier<ReaderPrefs> {
  ReaderPrefsNotifier() : super(const ReaderPrefs());

  void update(ReaderPrefs prefs, {bool persist = true}) {
    state = prefs;
    if (persist) {
      rust_storage.setSetting(key: 'reader_prefs', value: jsonEncode(prefs.toJson()));
    }
  }

  void load(ReaderPrefs prefs) {
    state = prefs;
  }
}

/// Per-title reader overrides keyed by slugUrl. Manga (RTL) and webtoon titles need
/// different defaults, which a single global profile cannot express.
final titleReaderPrefsProvider =
    StateNotifierProvider<TitleReaderPrefsNotifier, Map<String, ReaderPrefs>>(
  (ref) => TitleReaderPrefsNotifier(),
);

class TitleReaderPrefsNotifier extends StateNotifier<Map<String, ReaderPrefs>> {
  TitleReaderPrefsNotifier() : super(const {});

  void load(Map<String, ReaderPrefs> overrides) {
    state = overrides;
  }

  ReaderPrefs? forTitle(String slugUrl) =>
      slugUrl.isEmpty ? null : state[slugUrl];

  void setForTitle(String slugUrl, ReaderPrefs prefs) {
    if (slugUrl.isEmpty) return;
    state = {...state, slugUrl: prefs};
    _persist();
  }

  void clearForTitle(String slugUrl) {
    if (!state.containsKey(slugUrl)) return;
    final next = Map<String, ReaderPrefs>.from(state)..remove(slugUrl);
    state = next;
    _persist();
  }

  void _persist() {
    final encoded = jsonEncode(
      state.map((key, value) => MapEntry(key, value.toJson())),
    );
    rust_storage.setSetting(key: 'reader_prefs_titles', value: encoded);
  }
}

/// Download over Wi-Fi only.
final wifiOnlyDownloadsProvider =
    StateNotifierProvider<WifiOnlyDownloadsNotifier, bool>(
  (ref) => WifiOnlyDownloadsNotifier(),
);

class WifiOnlyDownloadsNotifier extends StateNotifier<bool> {
  WifiOnlyDownloadsNotifier() : super(false);

  void setEnabled(bool value, {bool persist = true}) {
    state = value;
    if (persist) {
      rust_storage.setSetting(key: 'downloads_wifi_only', value: value.toString());
    }
  }
}

/// Storage cap for downloaded chapters in megabytes (0 = unlimited).
final downloadsStorageLimitProvider =
    StateNotifierProvider<DownloadsStorageLimitNotifier, int>(
  (ref) => DownloadsStorageLimitNotifier(),
);

class DownloadsStorageLimitNotifier extends StateNotifier<int> {
  DownloadsStorageLimitNotifier() : super(0);

  void setLimitMb(int value, {bool persist = true}) {
    state = value < 0 ? 0 : value;
    if (persist) {
      rust_storage.setSetting(
        key: 'downloads_storage_limit_mb',
        value: state.toString(),
      );
    }
  }
}

/// Quiet hours suppress per-chapter notifications during the night.
class QuietHours {
  final bool enabled;
  final int startHour;
  final int endHour;

  const QuietHours({
    this.enabled = false,
    this.startHour = 23,
    this.endHour = 8,
  });

  QuietHours copyWith({bool? enabled, int? startHour, int? endHour}) {
    return QuietHours(
      enabled: enabled ?? this.enabled,
      startHour: startHour ?? this.startHour,
      endHour: endHour ?? this.endHour,
    );
  }

  /// Handles ranges that wrap over midnight (23:00 - 08:00).
  bool contains(DateTime time) {
    if (!enabled) return false;
    final hour = time.hour;
    if (startHour == endHour) return false;
    return startHour < endHour
        ? hour >= startHour && hour < endHour
        : hour >= startHour || hour < endHour;
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'startHour': startHour,
        'endHour': endHour,
      };

  factory QuietHours.fromJson(Map<String, dynamic> json) {
    return QuietHours(
      enabled: json['enabled'] == true,
      startHour: json['startHour'] is num ? (json['startHour'] as num).toInt() : 23,
      endHour: json['endHour'] is num ? (json['endHour'] as num).toInt() : 8,
    );
  }
}

final quietHoursProvider = StateNotifierProvider<QuietHoursNotifier, QuietHours>(
  (ref) => QuietHoursNotifier(),
);

class QuietHoursNotifier extends StateNotifier<QuietHours> {
  QuietHoursNotifier() : super(const QuietHours());

  void update(QuietHours value, {bool persist = true}) {
    state = value;
    if (persist) {
      rust_storage.setSetting(key: 'quiet_hours', value: jsonEncode(value.toJson()));
    }
  }

  void load(QuietHours value) {
    state = value;
  }
}

/// One digest per day instead of a notification for every released chapter.
final chapterDigestProvider =
    StateNotifierProvider<ChapterDigestNotifier, bool>(
  (ref) => ChapterDigestNotifier(),
);

class ChapterDigestNotifier extends StateNotifier<bool> {
  ChapterDigestNotifier() : super(false);

  void setEnabled(bool value, {bool persist = true}) {
    state = value;
    if (persist) {
      rust_storage.setSetting(key: 'chapter_digest', value: value.toString());
    }
  }
}

/// Automatic JSON backup interval in days (0 = disabled).
final autoBackupIntervalProvider =
    StateNotifierProvider<AutoBackupIntervalNotifier, int>(
  (ref) => AutoBackupIntervalNotifier(),
);

class AutoBackupIntervalNotifier extends StateNotifier<int> {
  AutoBackupIntervalNotifier() : super(0);

  void setDays(int value, {bool persist = true}) {
    state = value < 0 ? 0 : value;
    if (persist) {
      rust_storage.setSetting(
        key: 'auto_backup_interval_days',
        value: state.toString(),
      );
    }
  }
}

// 12. Cookies & User Profile with persistence
final cookiesProvider = StateNotifierProvider<CookiesNotifier, String>(
  (ref) => CookiesNotifier(),
);

class CookiesNotifier extends StateNotifier<String> {
  CookiesNotifier() : super('');

  void setCookies(String cookies, {bool persist = true}) {
    state = cookies;
    if (persist) {
      rust_storage.setSetting(key: 'cookies', value: cookies);
    }
    rust_api.setCookies(cookies: cookies);
  }
}

final currentUserProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfile?>(
  (ref) => UserProfileNotifier(),
);

class UserProfileNotifier extends StateNotifier<UserProfile?> {
  UserProfileNotifier() : super(null);

  void setProfile(UserProfile? profile, {bool persist = true}) {
    state = profile;
    if (persist) {
      if (profile != null) {
        final map = {
          'id': profile.id,
          'username': profile.username,
          'avatar_url': profile.avatarUrl,
          'created_at': profile.createdAt,
          'login_streak': profile.loginStreak,
        };
        rust_storage.setSetting(key: 'user_profile', value: jsonEncode(map));
      } else {
        rust_storage.setSetting(key: 'user_profile', value: '');
      }
    }
  }
}

