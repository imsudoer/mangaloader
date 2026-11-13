import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/services/update_checker.dart';

/// Guards the `PersistedSetting<T>` refactor: defaults, unpersisted updates and
/// the clamping setters must behave exactly like the hand-written notifiers did.
void main() {
  group('PersistedSetting', () {
    test('starts at the default and updates state without persisting', () {
      final setting = PersistedSetting<int>(
        defaultValue: 10,
        storageKey: 'test_key',
        encode: (value) => value.toString(),
      );
      addTearDown(setting.dispose);

      expect(setting.state, 10);
      setting.set(14, persist: false);
      expect(setting.state, 14);
    });

    test('load restores a stored value and keeps the default otherwise', () {
      final setting = PersistedSetting<bool>(
        defaultValue: false,
        storageKey: 'test_flag',
        encode: (value) => value.toString(),
      );
      addTearDown(setting.dispose);

      setting.load(true);
      expect(setting.state, isTrue);
      setting.load(false);
      expect(setting.state, isFalse);
    });
  });

  group('settings notifiers', () {
    test('theme mode defaults to dark and accepts an unpersisted switch', () {
      final notifier = ThemeModeNotifier();
      addTearDown(notifier.dispose);

      expect(notifier.state, ThemeMode.dark);
      notifier.setThemeMode(ThemeMode.light, persist: false);
      expect(notifier.state, ThemeMode.light);
      notifier.setThemeMode(ThemeMode.system, persist: false);
      expect(notifier.state, ThemeMode.system);
    });

    test('update channel defaults to stable', () {
      final notifier = UpdateChannelNotifier();
      addTearDown(notifier.dispose);

      expect(notifier.state, UpdateChannel.stable);
      notifier.setChannel(UpdateChannel.beta, persist: false);
      expect(notifier.state, UpdateChannel.beta);
    });

    test('download concurrency keeps the documented defaults', () {
      final images = ConcurrencyImagesNotifier();
      final chapters = ConcurrencyChaptersNotifier();
      addTearDown(images.dispose);
      addTearDown(chapters.dispose);

      expect(images.state, 10);
      expect(chapters.state, 3);
    });

    test('storage limit never goes below zero', () {
      final notifier = DownloadsStorageLimitNotifier();
      addTearDown(notifier.dispose);

      expect(notifier.state, 0);
      notifier.setLimitMb(-42, persist: false);
      expect(notifier.state, 0);
      notifier.setLimitMb(512, persist: false);
      expect(notifier.state, 512);
    });

    test('backup interval never goes below zero', () {
      final notifier = AutoBackupIntervalNotifier();
      addTearDown(notifier.dispose);

      notifier.setDays(-1, persist: false);
      expect(notifier.state, 0);
      notifier.setDays(7, persist: false);
      expect(notifier.state, 7);
    });
  });
}