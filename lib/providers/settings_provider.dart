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

    // 12. Cookies & User Profile
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

