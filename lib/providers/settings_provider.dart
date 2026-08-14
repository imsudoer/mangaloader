import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/services/update_downloader.dart';

// Theme mode provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark);

  void setThemeMode(ThemeMode mode) {
    state = mode;
  }

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

// Pure AMOLED mode provider
final amoledModeProvider = StateProvider<bool>((ref) => false);

// Locale provider: null = system default, Locale('ru') = Russian, Locale('en') = English
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>(
  (ref) => LocaleNotifier(),
);

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier() : super(null);

  void setLocale(Locale? locale) {
    state = locale;
  }
}

// Auto update check providers
final autoCheckUpdatesProvider = StateProvider<bool>((ref) => true);
final availableUpdateProvider = StateProvider<AppUpdateInfo?>((ref) => null);
final updateDownloadStateProvider = StateProvider<UpdateDownloadState>((ref) => const UpdateDownloadState());
final appVersionProvider = FutureProvider<String>((ref) async {
  return await UpdateChecker.getCurrentVersion();
});

// Download Concurrency Providers
final downloadConcurrencyImagesProvider = StateProvider<int>((ref) => 10);
final downloadConcurrencyChaptersProvider = StateProvider<int>((ref) => 3);

// Search History Provider
final searchHistoryProvider = StateNotifierProvider<SearchHistoryNotifier, List<String>>(
  (ref) => SearchHistoryNotifier(),
);

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super(const []);

  void addQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final updated = [trimmed, ...state.where((q) => q.toLowerCase() != trimmed.toLowerCase())];
    if (updated.length > 12) {
      state = updated.sublist(0, 12);
    } else {
      state = updated;
    }
  }

  void removeQuery(String query) {
    state = state.where((q) => q != query).toList();
  }

  void clearAll() {
    state = const [];
  }
}

// Cookies provider
final cookiesProvider = StateProvider<String>((ref) => '');
