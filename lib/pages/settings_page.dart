import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/providers/library_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/services/update_downloader.dart';
import 'package:mangaloader/services/streak_notification_service.dart';
import 'package:mangaloader/widgets/update_bottom_sheet.dart';
import 'package:mangaloader/widgets/manga_recap_modal.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _readerDefaultMode = 'vertical';
  String _readerDefaultBg = 'black';
  bool _smartStatusBar = true;
  bool _cropBorders = false;
  String _sharpeningMode = 'subtle';
  bool _isCheckingUpdates = false;
  bool _isClearingCache = false;

  Future<void> _clearAllCaches(bool isRu) async {
    setState(() => _isClearingCache = true);
    try {
      int bytesFreed = 0;

      // 1. In-memory Flutter image cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 2. Temp Directory files
      try {
        final tempDir = await getTemporaryDirectory();
        if (await tempDir.exists()) {
          await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              try {
                final len = await entity.length();
                bytesFreed += len;
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      // 3. Cache directory files
      try {
        final cacheDir = await getApplicationCacheDirectory();
        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              try {
                final len = await entity.length();
                bytesFreed += len;
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() => _isClearingCache = false);

      final mbFreed = (bytesFreed / (1024 * 1024)).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRu 
              ? 'Кэш очищен ($mbFreed МБ освобождено)' 
              : 'Cache cleared ($mbFreed MB freed)'
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isClearingCache = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка очистки: $e')),
        );
      }
    }
  }

  Future<void> _checkUpdates(bool isRu) async {
    setState(() => _isCheckingUpdates = true);
    try {
      final channel = ref.read(updateChannelProvider);
      final updateInfo = await UpdateChecker.checkForUpdates(channel: channel);
      if (!mounted) return;
      setState(() => _isCheckingUpdates = false);

      if (updateInfo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isRu ? 'Не удалось проверить обновления' : 'Failed to check for updates')),
        );
        return;
      }

      final currentVer = await UpdateChecker.getCurrentVersion();
      if (!mounted) return;

      if (!updateInfo.hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRu 
              ? 'У вас установлена последняя версия ($currentVer)' 
              : 'You have the latest version ($currentVer)'),
          ),
        );
        return;
      }

      ref.read(availableUpdateProvider.notifier).state = updateInfo;
      StreakNotificationService.showUpdateNotificationOnce(updateInfo, isRu: isRu);
      _showUpdateSheet(context, updateInfo, isRu);
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingUpdates = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка проверки: $e')),
        );
      }
    }
  }

  void _showUpdateSheet(BuildContext context, AppUpdateInfo update, bool isRu) {
    AppUpdateBottomSheet.show(context, ref, update, isRu);
  }


  Future<void> _exportBackup(bool isRu) async {
    try {
      final jsonStr = await rust_storage.exportBackupJson();
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${tempDir.path}/mangaloader_backup_$now.json');
      await file.writeAsString(jsonStr);

      if (mounted) {
        await SharePlus.instance.share(ShareParams(
          text: isRu ? 'Резервная копия библиотеки MangaLoader' : 'MangaLoader Backup',
          files: [XFile(file.path)],
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  Future<void> _importBackup(bool isRu) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final success = await rust_storage.importBackupJson(jsonContent: content);
        if (success) {
          await ref.read(libraryProvider.notifier).loadAll();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(isRu ? 'Резервная копия успешно восстановлена!' : 'Backup restored successfully!')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка восстановления: $e')),
        );
      }
    }
  }

  Future<void> _exportMalXml(bool isRu) async {
    try {
      final xmlStr = await rust_storage.exportMalXml();
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${tempDir.path}/mal_export_$now.xml');
      await file.writeAsString(xmlStr);

      if (mounted) {
        await SharePlus.instance.share(ShareParams(
          text: isRu ? 'Экспорт библиотеки MyAnimeList (MAL)' : 'MyAnimeList Export (XML)',
          files: [XFile(file.path)],
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта MAL: $e')),
        );
      }
    }
  }

  Future<void> _importMalXml(bool isRu) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final res = await rust_storage.importMalXml(xmlContent: content);
        await ref.read(libraryProvider.notifier).loadAll();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isRu
                    ? 'Импорт MAL завершен: добавлено ${res.importedCount}, обновлено ${res.updatedCount}'
                    : 'MAL Import done: ${res.importedCount} added, ${res.updatedCount} updated',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка импорта MAL: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedLocale = ref.watch(localeProvider);
    final isRu = (selectedLocale?.languageCode ?? Localizations.localeOf(context).languageCode) == 'ru';
    final currentTheme = ref.watch(themeModeProvider);
    final currentLocaleCode = selectedLocale == null ? 'system' : selectedLocale.languageCode;
    final availableUpdate = ref.watch(availableUpdateProvider);
    final downloadState = ref.watch(updateDownloadStateProvider);
    final appVersionAsync = ref.watch(appVersionProvider);
    final currentVersionStr = appVersionAsync.value ?? UpdateChecker.currentVersion;

    return Scaffold(
      appBar: AppBar(title: Text(isRu ? 'Настройки' : 'Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Theme & Appearance
          _buildSectionHeader(isRu ? 'Оформление и язык' : 'Appearance & Language', Icons.palette_outlined),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRu ? 'Режим темы' : 'Theme Mode',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: const Color(0xFF8A897C),
                      selectedForegroundColor: Colors.white,
                      foregroundColor: const Color(0xFFD2D7DF),
                    ),
                    segments: [
                      ButtonSegment(value: ThemeMode.system, label: Text(isRu ? 'Система' : 'System')),
                      ButtonSegment(value: ThemeMode.dark, label: Text(isRu ? 'Тёмная' : 'Dark')),
                      ButtonSegment(value: ThemeMode.light, label: Text(isRu ? 'Светлая' : 'Light')),
                    ],
                    selected: {currentTheme},
                    onSelectionChanged: (val) {
                      ref.read(themeModeProvider.notifier).setThemeMode(val.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isRu ? 'Язык интерфейса' : 'Interface Language',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: const Color(0xFF8A897C),
                      selectedForegroundColor: Colors.white,
                      foregroundColor: const Color(0xFFD2D7DF),
                    ),
                    segments: [
                      ButtonSegment(value: 'system', label: Text(isRu ? 'Авто' : 'Auto')),
                      const ButtonSegment(value: 'ru', label: Text('Русский')),
                      const ButtonSegment(value: 'en', label: Text('English')),
                    ],
                    selected: {currentLocaleCode},
                    onSelectionChanged: (val) {
                      final code = val.first;
                      if (code == 'system') {
                        ref.read(localeProvider.notifier).setLocale(null);
                      } else {
                        ref.read(localeProvider.notifier).setLocale(Locale(code));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.brightness_2_rounded, color: Color(0xFF8A897C)),
                    title: Text(isRu ? 'Режим Pure AMOLED' : 'Pure AMOLED Black'),
                    subtitle: Text(
                      isRu ? 'Глубокий черный фон для OLED экранов' : 'Pitch black background for OLED screens',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                    ),
                    value: ref.watch(amoledModeProvider),
                    onChanged: (val) => ref.read(amoledModeProvider.notifier).setAmoled(val),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF9800)),
                    title: Text(isRu ? 'Напоминания об огоньке' : 'Daily Streak Reminders'),
                    subtitle: Text(
                      isRu ? 'Ежедневное напоминание почитать главу и сохранить стрик' : 'Daily reminder to read a chapter and keep flame burning',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                    ),
                    value: ref.watch(streakNotificationsEnabledProvider),
                    onChanged: (val) {
                      ref.read(streakNotificationsEnabledProvider.notifier).setEnabled(val);
                      if (val) {
                        StreakNotificationService.scheduleDailyStreakReminder(isRu: isRu, enabled: true);
                      } else {
                        StreakNotificationService.cancelReminder();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8A897C)),
                    title: Text(isRu ? 'Manga Recap / Итоги чтения' : 'Manga Recap Summary'),
                    subtitle: Text(
                      isRu ? 'Красивая карточка с вашей статистикой чтения и топами' : 'Beautiful summary card with reading stats & tops',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => MangaRecapModal.show(context),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD700)),
                    title: Text(isRu ? 'Достижения' : 'Achievements'),
                    subtitle: Text(
                      isRu ? 'Просмотр всех наград, уровней и прогресса' : 'View all rewards, levels & progress',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => GoRouter.of(context).push('/achievements'),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bar_chart_rounded, color: Color(0xFF64B5F6)),
                    title: Text(isRu ? 'Статистика чтения' : 'Reading Statistics'),
                    subtitle: Text(
                      isRu ? 'Аналитика жанров, времени активности и прогресса' : 'Analytics of genres, activity time & progress',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => GoRouter.of(context).push('/statistics'),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.notifications_active_rounded, color: Color(0xFF8A897C)),
                    title: Text(isRu ? 'Уведомления о новых главах' : 'New Chapters Notifications'),
                    subtitle: Text(
                      isRu ? 'Отслеживание выхода свежих глав для тайтлов в библиотеке' : 'Track newly uploaded chapters for bookmarked titles',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                    ),
                    value: ref.watch(chapterNotificationsEnabledProvider),
                    onChanged: (val) => ref.read(chapterNotificationsEnabledProvider.notifier).setEnabled(val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Reader Defaults
          _buildSectionHeader(isRu ? 'Читалка по умолчанию' : 'Reader Defaults', Icons.chrome_reader_mode_outlined),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.swap_vert_rounded, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Направление чтения' : 'Reading Direction'),
                  subtitle: Text(
                    _readerDefaultMode == 'vertical'
                      ? (isRu ? 'Вертикальный вебтун (Сверху вниз)' : 'Vertical Webtoon')
                      : (_readerDefaultMode == 'rtl'
                          ? (isRu ? 'Справа налево (Манга)' : 'Right to Left')
                          : (isRu ? 'Слева направо' : 'Left to Right')),
                    style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 12),
                  ),
                  trailing: PopupMenuButton<String>(
                    initialValue: _readerDefaultMode,
                    color: const Color(0xFF2C2C2C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onSelected: (val) => setState(() => _readerDefaultMode = val),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'vertical', child: Text(isRu ? 'Вертикальный вебтун' : 'Vertical Webtoon')),
                      PopupMenuItem(value: 'rtl', child: Text(isRu ? 'Справа налево (Манга)' : 'Right to Left')),
                      PopupMenuItem(value: 'ltr', child: Text(isRu ? 'Слева направо' : 'Left to Right')),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.format_color_fill_rounded, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Фон читалки' : 'Reader Background'),
                  subtitle: Text(
                    _readerDefaultBg == 'black' ? (isRu ? 'Чёрный' : 'Black') : (_readerDefaultBg == 'darkGrey' ? (isRu ? 'Тёмно-серый' : 'Dark Grey') : (isRu ? 'Белый' : 'White')),
                    style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 12),
                  ),
                  trailing: PopupMenuButton<String>(
                    initialValue: _readerDefaultBg,
                    color: const Color(0xFF2C2C2C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onSelected: (val) => setState(() => _readerDefaultBg = val),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'black', child: Text(isRu ? 'Чёрный' : 'Black')),
                      PopupMenuItem(value: 'darkGrey', child: Text(isRu ? 'Тёмно-серый' : 'Dark Grey')),
                      PopupMenuItem(value: 'white', child: Text(isRu ? 'Белый' : 'White')),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Фильтр резкости' : 'Sharpening Filter'),
                  subtitle: Text(
                    _sharpeningMode == 'subtle' ? (isRu ? 'Мягкая резкость' : 'Subtle') : (_sharpeningMode == 'high' ? (isRu ? 'Высокая резкость' : 'High') : (isRu ? 'Отключено' : 'Off')),
                    style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 12),
                  ),
                  trailing: PopupMenuButton<String>(
                    initialValue: _sharpeningMode,
                    color: const Color(0xFF2C2C2C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onSelected: (val) => setState(() => _sharpeningMode = val),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'off', child: Text(isRu ? 'Отключено' : 'Off')),
                      PopupMenuItem(value: 'subtle', child: Text(isRu ? 'Мягкая резкость' : 'Subtle')),
                      PopupMenuItem(value: 'high', child: Text(isRu ? 'Высокая резкость' : 'High')),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.crop_free_rounded, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Обрезка белых полей' : 'Crop White Borders'),
                  subtitle: Text(isRu ? 'Автоматически удаляет белые поля' : 'Trim empty borders', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
                  value: _cropBorders,
                  onChanged: (val) => setState(() => _cropBorders = val),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.battery_charging_full_rounded, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Умный статус-бар' : 'Smart Status Bar'),
                  subtitle: Text(isRu ? 'Отображение времени и заряда батареи' : 'Show clock and battery', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
                  value: _smartStatusBar,
                  onChanged: (val) => setState(() => _smartStatusBar = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Downloads Configuration
          _buildSectionHeader(isRu ? 'Движок загрузки' : 'Download Engine', Icons.downloading_rounded),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isRu ? 'Параллельные потоки изображений:' : 'Concurrent images:', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${ref.watch(downloadConcurrencyImagesProvider)}', style: const TextStyle(color: Color(0xFF8A897C), fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Slider(
                    value: ref.watch(downloadConcurrencyImagesProvider).toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    activeColor: const Color(0xFF8A897C),
                    onChanged: (v) => ref.read(downloadConcurrencyImagesProvider.notifier).setConcurrency(v.toInt()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isRu ? 'Параллельные главы:' : 'Concurrent chapters:', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${ref.watch(downloadConcurrencyChaptersProvider)}', style: const TextStyle(color: Color(0xFF8A897C), fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Slider(
                    value: ref.watch(downloadConcurrencyChaptersProvider).toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    activeColor: const Color(0xFF8A897C),
                    onChanged: (v) => ref.read(downloadConcurrencyChaptersProvider.notifier).setConcurrency(v.toInt()),
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.offline_pin_outlined, color: Color(0xFF8A897C)),
                    title: Text(isRu ? 'Умный оффлайн' : 'Smart Offline'),
                    subtitle: Text(
                      isRu ? 'Автоскачивание следующих глав во время чтения' : 'Auto-download next chapters while reading',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                    ),
                    trailing: DropdownButton<int>(
                      value: ref.watch(smartAutoDownloadCountProvider),
                      dropdownColor: const Color(0xFF2C2C2C),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      underline: const SizedBox(),
                      items: [
                        DropdownMenuItem(value: 0, child: Text(isRu ? 'Отключено' : 'Disabled')),
                        DropdownMenuItem(value: 1, child: Text(isRu ? '1 след. глава' : '1 next chapter')),
                        DropdownMenuItem(value: 2, child: Text(isRu ? '2 главы' : '2 chapters')),
                        DropdownMenuItem(value: 3, child: Text(isRu ? '3 главы' : '3 chapters')),
                        DropdownMenuItem(value: 5, child: Text(isRu ? '5 глав' : '5 chapters')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(smartAutoDownloadCountProvider.notifier).setCount(val);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.auto_delete_rounded, color: Color(0xFF8A897C)),
                    title: Text(isRu ? 'Автоудаление прочитанного' : 'Auto-Delete Read Chapters'),
                    subtitle: Text(
                      isRu ? 'Автоматически удалять скачанную главу с устройства после прочтения' : 'Automatically delete downloaded chapter file after finishing reading',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                    ),
                    value: ref.watch(autoDeleteReadChaptersProvider),
                    onChanged: (val) => ref.read(autoDeleteReadChaptersProvider.notifier).setAutoDelete(val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 4. Backup & Restore
          _buildSectionHeader(isRu ? 'Резервное копирование и экспорт' : 'Backup & Export', Icons.backup_rounded),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_download_outlined, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Экспорт базы данных (JSON)' : 'Export Backup (JSON)'),
                  subtitle: Text(isRu ? 'Сохраняет библиотеку, историю и закладки' : 'Save library, history & bookmarks', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _exportBackup(isRu),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Импорт базы данных (JSON)' : 'Import Backup (JSON)'),
                  subtitle: Text(isRu ? 'Восстановить библиотеку из JSON-файла' : 'Restore library from JSON file', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _importBackup(isRu),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.import_export_rounded, color: Color(0xFF2E7D32)),
                  title: Text(isRu ? 'Экспорт в MyAnimeList (XML)' : 'Export to MyAnimeList (XML)'),
                  subtitle: Text(isRu ? 'Экспорт библиотеки в формат MAL' : 'Export library to MAL format', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _exportMalXml(isRu),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined, color: Color(0xFF2E7D32)),
                  title: Text(isRu ? 'Импорт из MyAnimeList (XML)' : 'Import from MyAnimeList (XML)'),
                  subtitle: Text(isRu ? 'Импорт манги из экспорта MyAnimeList' : 'Import manga from MyAnimeList export', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _importMalXml(isRu),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 5. Cache & Storage
          _buildSectionHeader(isRu ? 'Хранилище и кэш' : 'Storage & Cache', Icons.storage_rounded),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_delete_outlined, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Автоочистка кэша' : 'Auto-Clear Cache'),
                  subtitle: Text(
                    isRu ? 'Удалять кэшированные страницы старше выбранного срока' : 'Remove cached pages older than selected period',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                  ),
                  trailing: DropdownButton<int>(
                    value: ref.watch(autoClearCacheDaysProvider),
                    dropdownColor: const Color(0xFF2C2C2C),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(value: 0, child: Text(isRu ? 'Отключено' : 'Disabled')),
                      DropdownMenuItem(value: 3, child: Text(isRu ? '3 дня' : '3 days')),
                      DropdownMenuItem(value: 7, child: Text(isRu ? '7 дней (рек.)' : '7 days (rec.)')),
                      DropdownMenuItem(value: 14, child: Text(isRu ? '14 дней' : '14 days')),
                      DropdownMenuItem(value: 30, child: Text(isRu ? '30 дней' : '30 days')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(autoClearCacheDaysProvider.notifier).setDays(val);
                      }
                    },
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Очистить кэш приложения' : 'Clear Application Cache'),
                  subtitle: Text(
                    isRu ? 'Очищает сетевой дисковый кэш и оперативную память' : 'Clears disk network cache & RAM memory',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                  ),
                  trailing: OutlinedButton(
                    onPressed: _isClearingCache ? null : () => _clearAllCaches(isRu),
                    child: _isClearingCache
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(isRu ? 'Очистить' : 'Clear'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 5. Updates
          _buildSectionHeader(isRu ? 'Обновления' : 'Updates', Icons.system_update_rounded),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  isRu ? 'Версия: v$currentVersionStr' : 'Version: v$currentVersionStr',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                ),
                                if (availableUpdate != null && availableUpdate.hasUpdate) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8A897C),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      availableUpdate.tagName,
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (downloadState.status == UpdateDownloadStatus.downloading) ...[
                              Text(
                                '${isRu ? "Загрузка:" : "Downloading:"} ${(downloadState.progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(color: Color(0xFF8A897C), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: downloadState.progress > 0 ? downloadState.progress : null,
                                  backgroundColor: const Color(0xFF353535),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8A897C)),
                                  minHeight: 4,
                                ),
                              ),
                            ] else if (downloadState.status == UpdateDownloadStatus.completed) ...[
                              Text(
                                isRu ? 'Обновление готово к установке' : 'Update ready to install',
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ] else ...[
                              Text(
                                isRu ? 'Проверка новых релизов на GitHub' : 'Check for new releases on GitHub',
                                style: const TextStyle(color: Color(0xFFBDBBB0), fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Builder(
                        builder: (context) {
                          if (downloadState.status == UpdateDownloadStatus.completed && downloadState.downloadedFile != null) {
                            return FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade800,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => AppUpdateDownloader.installOrOpen(downloadState.downloadedFile!),
                              icon: const Icon(Icons.install_mobile_rounded, size: 18),
                              label: Text(isRu ? 'Установить' : 'Install'),
                            );
                          }
                          if (downloadState.status == UpdateDownloadStatus.downloading) {
                            return OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                              ),
                              onPressed: () {
                                AppUpdateDownloader.cancel();
                                ref.read(updateDownloadStateProvider.notifier).state = const UpdateDownloadState();
                              },
                              child: Text(isRu ? 'Отмена' : 'Cancel'),
                            );
                          }
                          if (availableUpdate != null && availableUpdate.hasUpdate) {
                            return FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF8A897C),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _showUpdateSheet(context, availableUpdate, isRu),
                              icon: const Icon(Icons.system_update_rounded, size: 18),
                              label: Text(isRu ? 'Обновить' : 'Update'),
                            );
                          }
                          return FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF8A897C),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _isCheckingUpdates ? null : () => _checkUpdates(isRu),
                            icon: _isCheckingUpdates 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(isRu ? 'Проверить' : 'Check'),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isRu ? 'Канал обновлений' : 'Update Channel', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              isRu ? 'Стабильные релизы или Dev/Beta' : 'Stable releases or Dev/Beta',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                            ),
                          ],
                        ),
                      ),
                      SegmentedButton<UpdateChannel>(
                        segments: const [
                          ButtonSegment(
                            value: UpdateChannel.stable,
                            label: Text('Stable'),
                          ),
                          ButtonSegment(
                            value: UpdateChannel.beta,
                            label: Text('Beta/Dev'),
                          ),
                        ],
                        selected: {ref.watch(updateChannelProvider)},
                        onSelectionChanged: (Set<UpdateChannel> newSelection) {
                          ref.read(updateChannelProvider.notifier).setChannel(newSelection.first);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  secondary: const Icon(Icons.schedule_rounded, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Проверять при запуске' : 'Check updates on launch'),
                  subtitle: Text(
                    isRu ? 'Тихий поиск свежих версий на главной' : 'Silent background check on startup',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                  ),
                  value: ref.watch(autoCheckUpdatesProvider),
                  onChanged: (val) => ref.read(autoCheckUpdatesProvider.notifier).setAutoCheck(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 6. About
          _buildSectionHeader(isRu ? 'О приложении' : 'About App', Icons.info_outline_rounded),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Manga Loader', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Версия $currentVersionStr (Flutter + Rust Core Engine)', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
                  const SizedBox(height: 8),
                  Text(
                    isRu
                      ? 'Современный загрузчик и ридер манги с аппаратным декодированием, масштабированием, автоскроллом и оффлайн-режимом CBZ.'
                      : 'Modern manga reader and downloader powered by Flutter and Rust.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFBDBBB0), height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF8A897C)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFD2D7DF)),
          ),
        ],
      ),
    );
  }
}
