import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/services/update_downloader.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';

/// Single-value notifier that mirrors its state into the Rust settings store.
///
/// [set] updates [state] and, unless `persist: false` is passed, writes
/// [encode] of the new value under [storageKey]. [load] restores a value
/// without writing it back, which is what [loadPersistentSettings] needs.
class PersistedSetting<T> extends StateNotifier<T> {
  PersistedSetting({
    required this.defaultValue,
    required this.storageKey,
    required this.encode,
  }) : super(defaultValue);

  final T defaultValue;
  final String storageKey;
  final String Function(T value) encode;

  void set(T value, {bool persist = true}) {
    state = value;
    if (persist) {
      rust_storage.setSetting(key: storageKey, value: encode(state));
    }
  }

  void load(T value) {
    state = value;
  }
}

String _boolText(bool value) => value.toString();

String _intText(int value) => value.toString();

String _themeModeText(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      _ => 'dark',
    };

String _updateChannelText(UpdateChannel channel) =>
    channel == UpdateChannel.beta ? 'beta' : 'stable';

// Helper function to load all settings into providers upon app launch
Future<void> loadPersistentSettings(WidgetRef ref) async {
  try {
    final settings = await rust_storage.getAllSettings();
    final map = {for (var item in settings) item.key: item.value};

    bool flag(String key) => map[key] == 'true';
    int intOr(String key, int fallback) => int.tryParse(map[key] ?? '') ?? fallback;

    bool has(String key) => map.containsKey(key);
    void restoreBool(String key, StateNotifierProvider<PersistedSetting<bool>, bool> provider) {
      if (has(key)) ref.read(provider.notifier).set(flag(key), persist: false);
    }

    void restoreInt(String key, int fallback, StateNotifierProvider<PersistedSetting<int>, int> provider) {
      if (has(key)) ref.read(provider.notifier).set(intOr(key, fallback), persist: false);
    }

    // 1. Theme mode
    if (has('theme_mode')) {
      final mode = switch (map['theme_mode']) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
      ref.read(themeModeProvider.notifier).setThemeMode(mode, persist: false);
    }

    // 2. AMOLED Mode
    restoreBool('amoled_mode', amoledModeProvider);

    // 3. Locale
    if (has('locale')) {
      final code = map['locale']!;
      final locale = code == 'ru' || code == 'en' ? Locale(code) : null;
      ref.read(localeProvider.notifier).setLocale(locale, persist: false);
    }

    // 4. Auto check updates
    restoreBool('auto_check_updates', autoCheckUpdatesProvider);

    // 4.1 Update channel
    if (has('update_channel')) {
      final channel = map['update_channel'] == 'beta' ? UpdateChannel.beta : UpdateChannel.stable;
      ref.read(updateChannelProvider.notifier).setChannel(channel, persist: false);
    }

    // 5. Download Concurrency
    restoreInt('download_concurrency_images', 10, downloadConcurrencyImagesProvider);
    restoreInt('download_concurrency_chapters', 3, downloadConcurrencyChaptersProvider);

    // 6. Auto clear cache days
    restoreInt('auto_clear_cache_days', 7, autoClearCacheDaysProvider);

    // 7. Streak notifications
    restoreBool('streak_notifications_enabled', streakNotificationsEnabledProvider);

    // 8. Smart auto download count
    restoreInt('smart_auto_download_count', 0, smartAutoDownloadCountProvider);

    // 9. Auto delete read chapters
    restoreBool('auto_delete_read_chapters', autoDeleteReadChaptersProvider);

    // 10. Chapter notifications
    restoreBool('chapter_notifications_enabled', chapterNotificationsEnabledProvider);

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
    restoreBool('downloads_wifi_only', wifiOnlyDownloadsProvider);
    if (has('downloads_storage_limit_mb')) {
      ref.read(downloadsStorageLimitProvider.notifier).setLimitMb(
            intOr('downloads_storage_limit_mb', 0),
            persist: false,
          );
    }

    // 12.3 Notifications digest and quiet hours
    if (has('quiet_hours')) {
      try {
        final raw = map['quiet_hours']!;
        if (raw.isNotEmpty) {
          ref.read(quietHoursProvider.notifier).load(
                QuietHours.fromJson(jsonDecode(raw) as Map<String, dynamic>),
              );
        }
      } catch (_) {}
    }
    restoreBool('chapter_digest', chapterDigestProvider);

    // 12.4 Automatic backup interval
    if (map.containsKey('auto_backup_interval_days')) {
      ref.read(autoBackupIntervalProvider.notifier).setDays(
            intOr('auto_backup_interval_days', 0),
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

class ThemeModeNotifier extends PersistedSetting<ThemeMode> {
  ThemeModeNotifier() : super(defaultValue: ThemeMode.dark, storageKey: 'theme_mode', encode: _themeModeText);

  void setThemeMode(ThemeMode mode, {bool persist = true}) => set(mode, persist: persist);

  void toggle() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setThemeMode(next);
  }
}

// 2. Pure AMOLED mode provider with persistence
final amoledModeProvider = StateNotifierProvider<AmoledModeNotifier, bool>(
  (ref) => AmoledModeNotifier(),
);

class AmoledModeNotifier extends PersistedSetting<bool> {
  AmoledModeNotifier() : super(defaultValue: false, storageKey: 'amoled_mode', encode: _boolText);

  void setAmoled(bool value, {bool persist = true}) => set(value, persist: persist);
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

class AutoCheckUpdatesNotifier extends PersistedSetting<bool> {
  AutoCheckUpdatesNotifier() : super(defaultValue: true, storageKey: 'auto_check_updates', encode: _boolText);

  void setAutoCheck(bool val, {bool persist = true}) => set(val, persist: persist);
}

// 4.1. Update channel provider (Stable / Beta/Dev)
final updateChannelProvider = StateNotifierProvider<UpdateChannelNotifier, UpdateChannel>(
  (ref) => UpdateChannelNotifier(),
);

class UpdateChannelNotifier extends PersistedSetting<UpdateChannel> {
  UpdateChannelNotifier()
      : super(defaultValue: UpdateChannel.stable, storageKey: 'update_channel', encode: _updateChannelText);

  void setChannel(UpdateChannel channel, {bool persist = true}) => set(channel, persist: persist);
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

class ConcurrencyImagesNotifier extends PersistedSetting<int> {
  ConcurrencyImagesNotifier()
      : super(defaultValue: 10, storageKey: 'download_concurrency_images', encode: _intText);

  void setConcurrency(int val, {bool persist = true}) => set(val, persist: persist);
}

final downloadConcurrencyChaptersProvider = StateNotifierProvider<ConcurrencyChaptersNotifier, int>(
  (ref) => ConcurrencyChaptersNotifier(),
);

class ConcurrencyChaptersNotifier extends PersistedSetting<int> {
  ConcurrencyChaptersNotifier()
      : super(defaultValue: 3, storageKey: 'download_concurrency_chapters', encode: _intText);

  void setConcurrency(int val, {bool persist = true}) => set(val, persist: persist);
}

// 6. Auto clear cache duration in days with persistence
final autoClearCacheDaysProvider = StateNotifierProvider<AutoClearCacheNotifier, int>(
  (ref) => AutoClearCacheNotifier(),
);

class AutoClearCacheNotifier extends PersistedSetting<int> {
  AutoClearCacheNotifier() : super(defaultValue: 7, storageKey: 'auto_clear_cache_days', encode: _intText);

  void setDays(int val, {bool persist = true}) => set(val, persist: persist);
}

// 7. Streak push notifications toggle with persistence
final streakNotificationsEnabledProvider = StateNotifierProvider<StreakNotificationsNotifier, bool>(
  (ref) => StreakNotificationsNotifier(),
);

class StreakNotificationsNotifier extends PersistedSetting<bool> {
  StreakNotificationsNotifier()
      : super(defaultValue: true, storageKey: 'streak_notifications_enabled', encode: _boolText);

  void setEnabled(bool val, {bool persist = true}) => set(val, persist: persist);
}

// 8. Smart Offline Auto-Download count with persistence
final smartAutoDownloadCountProvider = StateNotifierProvider<SmartAutoDownloadNotifier, int>(
  (ref) => SmartAutoDownloadNotifier(),
);

class SmartAutoDownloadNotifier extends PersistedSetting<int> {
  SmartAutoDownloadNotifier() : super(defaultValue: 0, storageKey: 'smart_auto_download_count', encode: _intText);

  void setCount(int val, {bool persist = true}) => set(val, persist: persist);
}

// 9. Auto-delete read downloaded chapters toggle with persistence
final autoDeleteReadChaptersProvider = StateNotifierProvider<AutoDeleteReadNotifier, bool>(
  (ref) => AutoDeleteReadNotifier(),
);

class AutoDeleteReadNotifier extends PersistedSetting<bool> {
  AutoDeleteReadNotifier() : super(defaultValue: false, storageKey: 'auto_delete_read_chapters', encode: _boolText);

  void setAutoDelete(bool val, {bool persist = true}) => set(val, persist: persist);
}

// 10. Background Chapter Updates Notifications toggle with persistence
final chapterNotificationsEnabledProvider = StateNotifierProvider<ChapterNotificationsNotifier, bool>(
  (ref) => ChapterNotificationsNotifier(),
);

class ChapterNotificationsNotifier extends PersistedSetting<bool> {
  ChapterNotificationsNotifier()
      : super(defaultValue: true, storageKey: 'chapter_notifications_enabled', encode: _boolText);

  void setEnabled(bool val, {bool persist = true}) => set(val, persist: persist);
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

  /// Prepares the next chapter while the end of the current one is in view.
  final bool autoNextChapter;

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
    this.autoNextChapter = false,
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
    bool? autoNextChapter,
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
      autoNextChapter: autoNextChapter ?? this.autoNextChapter,
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
        'autoNextChapter': autoNextChapter,
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
      autoNextChapter: json['autoNextChapter'] == true,
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

class WifiOnlyDownloadsNotifier extends PersistedSetting<bool> {
  WifiOnlyDownloadsNotifier() : super(defaultValue: false, storageKey: 'downloads_wifi_only', encode: _boolText);

  void setEnabled(bool value, {bool persist = true}) => set(value, persist: persist);
}

/// Storage cap for downloaded chapters in megabytes (0 = unlimited).
final downloadsStorageLimitProvider =
    StateNotifierProvider<DownloadsStorageLimitNotifier, int>(
  (ref) => DownloadsStorageLimitNotifier(),
);

class DownloadsStorageLimitNotifier extends PersistedSetting<int> {
  DownloadsStorageLimitNotifier()
      : super(defaultValue: 0, storageKey: 'downloads_storage_limit_mb', encode: _intText);

  void setLimitMb(int value, {bool persist = true}) => set(value < 0 ? 0 : value, persist: persist);
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

class ChapterDigestNotifier extends PersistedSetting<bool> {
  ChapterDigestNotifier() : super(defaultValue: false, storageKey: 'chapter_digest', encode: _boolText);

  void setEnabled(bool value, {bool persist = true}) => set(value, persist: persist);
}

/// Automatic JSON backup interval in days (0 = disabled).
final autoBackupIntervalProvider =
    StateNotifierProvider<AutoBackupIntervalNotifier, int>(
  (ref) => AutoBackupIntervalNotifier(),
);

class AutoBackupIntervalNotifier extends PersistedSetting<int> {
  AutoBackupIntervalNotifier()
      : super(defaultValue: 0, storageKey: 'auto_backup_interval_days', encode: _intText);

  void setDays(int value, {bool persist = true}) => set(value < 0 ? 0 : value, persist: persist);
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