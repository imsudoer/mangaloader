import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/services/update_checker.dart';

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

// Cookies provider
final cookiesProvider = StateProvider<String>((ref) => '');
