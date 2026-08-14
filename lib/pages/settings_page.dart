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
import 'package:mangaloader/widgets/update_bottom_sheet.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  int _imagesConcurrent = 10;
  int _chaptersConcurrent = 3;
  String _readerDefaultMode = 'vertical';
  String _readerDefaultBg = 'black';
  bool _smartStatusBar = true;
  bool _cropBorders = false;
  String _sharpeningMode = 'subtle';
  bool _isCheckingUpdates = false;

  Future<void> _checkUpdates(bool isRu) async {
    setState(() => _isCheckingUpdates = true);
    try {
      final updateInfo = await UpdateChecker.checkForUpdates();
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
                    onChanged: (val) => ref.read(amoledModeProvider.notifier).state = val,
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
                      Text('$_imagesConcurrent', style: const TextStyle(color: Color(0xFF8A897C), fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Slider(
                    value: _imagesConcurrent.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    activeColor: const Color(0xFF8A897C),
                    onChanged: (v) => setState(() => _imagesConcurrent = v.toInt()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isRu ? 'Параллельные главы:' : 'Concurrent chapters:', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('$_chaptersConcurrent', style: const TextStyle(color: Color(0xFF8A897C), fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Slider(
                    value: _chaptersConcurrent.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    activeColor: const Color(0xFF8A897C),
                    onChanged: (v) => setState(() => _chaptersConcurrent = v.toInt()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 4. Backup & Restore
          _buildSectionHeader(isRu ? 'Резервное копирование' : 'Backup & Restore', Icons.backup_rounded),
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
                  title: Text(isRu ? 'Импорт базы данных' : 'Import Backup'),
                  subtitle: Text(isRu ? 'Восстановить библиотеку из JSON-файла' : 'Restore library from JSON file', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _importBackup(isRu),
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
            child: ListTile(
              leading: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF8A897C)),
              title: Text(isRu ? 'Очистить кэш изображений' : 'Clear Image Cache'),
              subtitle: Text(isRu ? 'Освобождает временную память' : 'Frees in-memory image cache', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
              trailing: OutlinedButton(
                onPressed: () {
                  PaintingBinding.instance.imageCache.clear();
                  PaintingBinding.instance.imageCache.clearLiveImages();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isRu ? 'Кэш изображений очищен' : 'Image cache cleared')),
                  );
                },
                child: Text(isRu ? 'Очистить' : 'Clear'),
              ),
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
                SwitchListTile(
                  secondary: const Icon(Icons.schedule_rounded, color: Color(0xFF8A897C)),
                  title: Text(isRu ? 'Проверять при запуске' : 'Check updates on launch'),
                  subtitle: Text(
                    isRu ? 'Тихий поиск свежих версий на главной' : 'Silent background check on startup',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                  ),
                  value: ref.watch(autoCheckUpdatesProvider),
                  onChanged: (val) => ref.read(autoCheckUpdatesProvider.notifier).state = val,
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
