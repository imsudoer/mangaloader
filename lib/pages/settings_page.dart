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
import 'package:mangaloader/services/backup_service.dart';
import 'package:mangaloader/l10n/strings/settings_strings.dart';
import 'package:mangaloader/pages/profile_page.dart' show showMalUrlImportDialog;
import 'package:mangaloader/utils/plural.dart';
import 'package:mangaloader/widgets/update_bottom_sheet.dart';
import 'package:mangaloader/widgets/manga_recap_modal.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/theme/app_tokens.dart';

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
  bool _isBackingUp = false;
  DateTime? _lastBackupAt;
  String? _lastBackupPath;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  Future<void> _loadLastBackup() async {
    final at = await BackupService.lastBackupAt();
    if (mounted) setState(() => _lastBackupAt = at);
  }

  Future<void> _createBackupNow(bool isRu) async {
    final s = SettingsStrings(isRu);
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);
    final path = await BackupService.backupNow();
    if (!mounted) return;
    setState(() {
      _isBackingUp = false;
      if (path != null) {
        _lastBackupPath = path;
        _lastBackupAt = DateTime.now();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path == null ? s.backupFailed : s.backupSaved(path)),
      ),
    );
  }

  Future<void> _importMalFromUrl(bool isRu) async {
    final imported = await showMalUrlImportDialog(context, isRu: isRu);
    if (imported && mounted) {
      await ref.read(libraryProvider.notifier).loadAll();
    }
  }

  String _formatBackupMoment(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.day)}.${two(at.month)}.${at.year} ${two(at.hour)}:${two(at.minute)}';
  }

  Future<void> _clearAllCaches(bool isRu) async {
    final s = SettingsStrings(isRu);
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
        SnackBar(content: Text(s.cacheCleared(mbFreed))),
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
    final s = SettingsStrings(isRu);
    setState(() => _isCheckingUpdates = true);
    try {
      final channel = ref.read(updateChannelProvider);
      final updateInfo = await UpdateChecker.checkForUpdates(channel: channel);
      if (!mounted) return;
      setState(() => _isCheckingUpdates = false);

      if (updateInfo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.updateCheckFailed)),
        );
        return;
      }

      final currentVer = await UpdateChecker.getCurrentVersion();
      if (!mounted) return;

      if (!updateInfo.hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.latestVersion(currentVer)),
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
    final s = SettingsStrings(isRu);
    try {
      final jsonStr = await rust_storage.exportBackupJson();
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${tempDir.path}/mangaloader_backup_$now.json');
      await file.writeAsString(jsonStr);

      if (mounted) {
        await SharePlus.instance.share(ShareParams(
          text: s.backupShareText,
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
    final s = SettingsStrings(isRu);
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
              SnackBar(content: Text(s.backupRestored)),
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
    final s = SettingsStrings(isRu);
    try {
      final xmlStr = await rust_storage.exportMalXml();
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${tempDir.path}/mal_export_$now.xml');
      await file.writeAsString(xmlStr);

      if (mounted) {
        await SharePlus.instance.share(ShareParams(
          text: s.malExportShareText,
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
    final s = SettingsStrings(isRu);
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
                s.malImportDone(
                  '${res.importedCount}',
                  '${res.updatedCount}',
                ),
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
    final s = SettingsStrings(isRu);
    final currentTheme = ref.watch(themeModeProvider);
    final currentLocaleCode = selectedLocale == null ? 'system' : selectedLocale.languageCode;
    final availableUpdate = ref.watch(availableUpdateProvider);
    final downloadState = ref.watch(updateDownloadStateProvider);
    final appVersionAsync = ref.watch(appVersionProvider);
    final currentVersionStr = appVersionAsync.value ?? UpdateChecker.currentVersion;
    final backupInterval = ref.watch(autoBackupIntervalProvider);
    // A persisted value outside the offered set would trip the dropdown assert.
    final selectedBackupInterval =
        const [0, 1, 3, 7, 30].contains(backupInterval) ? backupInterval : 0;

    return Scaffold(
      appBar: AppBar(title: Text(s.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Theme & Appearance
          _buildSectionHeader(s.appearanceAndLanguage, Icons.palette_outlined),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTokens.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.themeMode,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppTokens.accent,
                      selectedForegroundColor: Colors.white,
                      foregroundColor: AppTokens.textPrimary,
                    ),
                    segments: [
                      ButtonSegment(value: ThemeMode.system, label: Text(s.themeSystem)),
                      ButtonSegment(value: ThemeMode.dark, label: Text(s.themeDark)),
                      ButtonSegment(value: ThemeMode.light, label: Text(s.themeLight)),
                    ],
                    selected: {currentTheme},
                    onSelectionChanged: (val) {
                      ref.read(themeModeProvider.notifier).setThemeMode(val.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.interfaceLanguage,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppTokens.accent,
                      selectedForegroundColor: Colors.white,
                      foregroundColor: AppTokens.textPrimary,
                    ),
                    segments: [
                      ButtonSegment(value: 'system', label: Text(s.languageAuto)),
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
                    secondary: const Icon(Icons.brightness_2_rounded, color: AppTokens.accent),
                    title: Text(s.amoledMode),
                    subtitle: Text(
                      s.amoledSubtitle,
                      style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                    ),
                    value: ref.watch(amoledModeProvider),
                    onChanged: (val) => ref.read(amoledModeProvider.notifier).setAmoled(val),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF9800)),
                    title: Text(s.streakReminders),
                    subtitle: Text(
                      s.streakRemindersSubtitle,
                      style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
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
                    leading: const Icon(Icons.auto_awesome_rounded, color: AppTokens.accent),
                    title: Text(s.mangaRecap),
                    subtitle: Text(
                      s.mangaRecapSubtitle,
                      style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => MangaRecapModal.show(context),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD700)),
                    title: Text(s.achievements),
                    subtitle: Text(
                      s.achievementsSubtitle,
                      style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => GoRouter.of(context).push('/achievements'),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bar_chart_rounded, color: Color(0xFF64B5F6)),
                    title: Text(s.readingStatistics),
                    subtitle: Text(
                      s.readingStatisticsSubtitle,
                      style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => GoRouter.of(context).push('/statistics'),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.notifications_active_rounded, color: AppTokens.accent),
                    title: Text(s.chapterNotifications),
                    subtitle: Text(
                      s.chapterNotificationsSubtitle,
                      style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                    ),
                    value: ref.watch(chapterNotificationsEnabledProvider),
                    onChanged: (val) => ref.read(chapterNotificationsEnabledProvider.notifier).setEnabled(val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Notification timing
          _buildSectionHeader(
            s.notificationsAndQuietHours,
            Icons.notifications_none_rounded,
          ),
          _buildNotificationTimingCard(isRu),
          const SizedBox(height: 20),

          // 3. Reader Defaults
          _buildSectionHeader(s.readerDefaults, Icons.chrome_reader_mode_outlined),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTokens.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.swap_vert_rounded, color: AppTokens.accent),
                  title: Text(s.readingDirection),
                  subtitle: Text(
                    _readerDefaultMode == 'vertical'
                      ? s.readingDirectionVerticalWebtoon
                      : (_readerDefaultMode == 'rtl'
                          ? s.readingDirectionRightToLeft
                          : s.readingDirectionLeftToRight),
                    style: const TextStyle(color: AppTokens.textPrimary, fontSize: 12),
                  ),
                  trailing: PopupMenuButton<String>(
                    initialValue: _readerDefaultMode,
                    color: AppTokens.surfaceRaised,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onSelected: (val) => setState(() => _readerDefaultMode = val),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'vertical', child: Text(s.verticalWebtoon)),
                      PopupMenuItem(value: 'rtl', child: Text(s.readingDirectionRightToLeft)),
                      PopupMenuItem(value: 'ltr', child: Text(s.readingDirectionLeftToRight)),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.format_color_fill_rounded, color: AppTokens.accent),
                  title: Text(s.readerBackground),
                  subtitle: Text(
                    _readerDefaultBg == 'black' ? s.readerBackgroundBlack : (_readerDefaultBg == 'darkGrey' ? s.readerBackgroundDarkGrey : s.readerBackgroundWhite),
                    style: const TextStyle(color: AppTokens.textPrimary, fontSize: 12),
                  ),
                  trailing: PopupMenuButton<String>(
                    initialValue: _readerDefaultBg,
                    color: AppTokens.surfaceRaised,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onSelected: (val) => setState(() => _readerDefaultBg = val),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'black', child: Text(s.readerBackgroundBlack)),
                      PopupMenuItem(value: 'darkGrey', child: Text(s.readerBackgroundDarkGrey)),
                      PopupMenuItem(value: 'white', child: Text(s.readerBackgroundWhite)),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded, color: AppTokens.accent),
                  title: Text(s.sharpeningFilter),
                  subtitle: Text(
                    _sharpeningMode == 'subtle' ? s.sharpeningSubtle : (_sharpeningMode == 'high' ? s.sharpeningHigh : s.off),
                    style: const TextStyle(color: AppTokens.textPrimary, fontSize: 12),
                  ),
                  trailing: PopupMenuButton<String>(
                    initialValue: _sharpeningMode,
                    color: AppTokens.surfaceRaised,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onSelected: (val) => setState(() => _sharpeningMode = val),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'off', child: Text(s.off)),
                      PopupMenuItem(value: 'subtle', child: Text(s.sharpeningSubtle)),
                      PopupMenuItem(value: 'high', child: Text(s.sharpeningHigh)),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.crop_free_rounded, color: AppTokens.accent),
                  title: Text(s.cropBorders),
                  subtitle: Text(s.cropBordersSubtitle, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
                  value: _cropBorders,
                  onChanged: (val) => setState(() => _cropBorders = val),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.battery_charging_full_rounded, color: AppTokens.accent),
                  title: Text(s.smartStatusBar),
                  subtitle: Text(s.smartStatusBarSubtitle, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
                  value: _smartStatusBar,
                  onChanged: (val) => setState(() => _smartStatusBar = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Downloads Configuration
          _buildSectionHeader(s.downloadEngine, Icons.downloading_rounded),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTokens.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s.concurrentImages, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${ref.watch(downloadConcurrencyImagesProvider)}', style: const TextStyle(color: AppTokens.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Slider(
                    value: ref.watch(downloadConcurrencyImagesProvider).toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    activeColor: AppTokens.accent,
                    onChanged: (v) => ref.read(downloadConcurrencyImagesProvider.notifier).setConcurrency(v.toInt()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s.concurrentChapters, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${ref.watch(downloadConcurrencyChaptersProvider)}', style: const TextStyle(color: AppTokens.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Slider(
                    value: ref.watch(downloadConcurrencyChaptersProvider).toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    activeColor: AppTokens.accent,
                    onChanged: (v) => ref.read(downloadConcurrencyChaptersProvider.notifier).setConcurrency(v.toInt()),
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.offline_pin_outlined, color: AppTokens.accent),
                    title: Text(s.smartOffline),
                    subtitle: Text(
                      s.smartOfflineSubtitle,
                      style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                    ),
                    trailing: DropdownButton<int>(
                      value: ref.watch(smartAutoDownloadCountProvider),
                      dropdownColor: AppTokens.surfaceRaised,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      underline: const SizedBox(),
                      items: [
                        DropdownMenuItem(value: 0, child: Text(s.disabled)),
                        DropdownMenuItem(value: 1, child: Text(s.smartOfflineOneChapter)),
                        DropdownMenuItem(value: 2, child: Text(s.smartOfflineTwoChapters)),
                        DropdownMenuItem(value: 3, child: Text(s.smartOfflineThreeChapters)),
                        DropdownMenuItem(value: 5, child: Text(s.smartOfflineFiveChapters)),
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
                    secondary: const Icon(Icons.auto_delete_rounded, color: AppTokens.accent),
                    title: Text(s.autoDeleteRead),
                    subtitle: Text(
                      s.autoDeleteReadSubtitle,
                      style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                    ),
                    value: ref.watch(autoDeleteReadChaptersProvider),
                    onChanged: (val) => ref.read(autoDeleteReadChaptersProvider.notifier).setAutoDelete(val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 5. Backups & Restore
          _buildSectionHeader(s.backupsAndExport, Icons.backup_rounded),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTokens.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.schedule_send_rounded, color: AppTokens.accent),
                  title: Text(s.automaticBackups),
                  subtitle: Text(
                    _backupIntervalLabel(selectedBackupInterval, isRu),
                    style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                  ),
                  trailing: DropdownButton<int>(
                    value: selectedBackupInterval,
                    dropdownColor: AppTokens.surfaceRaised,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    underline: const SizedBox(),
                    items: [
                      for (final days in const [0, 1, 3, 7, 30])
                        DropdownMenuItem(
                          value: days,
                          child: Text(
                            days == 0
                                ? s.off
                                : Plural.days(days, isRu ? 'ru' : 'en'),
                          ),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(autoBackupIntervalProvider.notifier).setDays(val);
                      }
                    },
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.save_alt_rounded, color: AppTokens.accent),
                  title: Text(s.createBackupNow),
                  subtitle: Text(
                    _lastBackupAt == null
                        ? s.noBackupsYet
                        : s.lastBackup(_formatBackupMoment(_lastBackupAt!)),
                    style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                  ),
                  trailing: OutlinedButton(
                    onPressed: _isBackingUp ? null : () => _createBackupNow(isRu),
                    child: _isBackingUp
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(s.create),
                  ),
                ),
                if (_lastBackupPath != null) ...[
                  const Divider(height: 1, indent: 56),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 10, 16, 12),
                    child: Text(
                      _lastBackupPath!,
                      style: const TextStyle(fontSize: 11, color: AppTokens.accent, height: 1.3),
                    ),
                  ),
                ],
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined, color: AppTokens.accent),
                  title: Text(s.exportBackupJson),
                  subtitle: Text(s.exportBackupJsonSubtitle, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _exportBackup(isRu),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined, color: AppTokens.accent),
                  title: Text(s.importBackupJson),
                  subtitle: Text(s.importBackupJsonSubtitle, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _importBackup(isRu),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.import_export_rounded, color: Color(0xFF2E7D32)),
                  title: Text(s.exportMal),
                  subtitle: Text(s.exportMalSubtitle, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _exportMalXml(isRu),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined, color: Color(0xFF2E7D32)),
                  title: Text(s.importMal),
                  subtitle: Text(s.importMalSubtitle, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _importMalXml(isRu),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.link_rounded, color: Color(0xFF2E7D32)),
                  title: Text(s.importMalUrl),
                  subtitle: Text(
                    s.importMalUrlSubtitle,
                    style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _importMalFromUrl(isRu),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 6. Cache & Storage
          _buildSectionHeader(s.storageAndCache, Icons.storage_rounded),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTokens.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_delete_outlined, color: AppTokens.accent),
                  title: Text(s.autoClearCache),
                  subtitle: Text(
                    s.autoClearCacheSubtitle,
                    style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                  ),
                  trailing: DropdownButton<int>(
                    value: ref.watch(autoClearCacheDaysProvider),
                    dropdownColor: AppTokens.surfaceRaised,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(value: 0, child: Text(s.disabled)),
                      DropdownMenuItem(value: 3, child: Text(s.cacheThreeDays)),
                      DropdownMenuItem(value: 7, child: Text(s.cacheSevenDaysRecommended)),
                      DropdownMenuItem(value: 14, child: Text(s.cacheFourteenDays)),
                      DropdownMenuItem(value: 30, child: Text(s.cacheThirtyDays)),
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
                  leading: const Icon(Icons.cleaning_services_rounded, color: AppTokens.accent),
                  title: Text(s.clearCache),
                  subtitle: Text(
                    s.clearCacheSubtitle,
                    style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                  ),
                  trailing: OutlinedButton(
                    onPressed: _isClearingCache ? null : () => _clearAllCaches(isRu),
                    child: _isClearingCache
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(s.clear),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 7. Updates
          _buildSectionHeader(s.updates, Icons.system_update_rounded),
          if (isRuStoreBuild)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppTokens.border),
              ),
              child: ListTile(
                leading: const Icon(Icons.storefront_rounded, color: AppTokens.accent),
                title: Text(
                  s.versionWithStore(currentVersionStr),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                subtitle: Text(
                  s.storeUpdatesNote,
                  style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                ),
              ),
            )
          else
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppTokens.border),
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
                                    s.versionLabel(currentVersionStr),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                  ),
                                  if (availableUpdate != null && availableUpdate.hasUpdate) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTokens.accent,
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
                                  s.downloading((downloadState.progress * 100).toStringAsFixed(0)),
                                  style: const TextStyle(color: AppTokens.accent, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: downloadState.progress > 0 ? downloadState.progress : null,
                                    backgroundColor: AppTokens.border,
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.accent),
                                    minHeight: 4,
                                  ),
                                ),
                              ] else if (downloadState.status == UpdateDownloadStatus.completed) ...[
                                Text(
                                  s.updateReady,
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ] else ...[
                                Text(
                                  s.checkReleasesNote,
                                  style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
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
                                label: Text(s.install),
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
                                child: Text(s.cancel),
                              );
                            }
                            if (availableUpdate != null && availableUpdate.hasUpdate) {
                              return FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTokens.accent,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _showUpdateSheet(context, availableUpdate, isRu),
                                icon: const Icon(Icons.system_update_rounded, size: 18),
                                label: Text(s.update),
                              );
                            }
                            return FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTokens.accent,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _isCheckingUpdates ? null : () => _checkUpdates(isRu),
                              icon: _isCheckingUpdates 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.refresh_rounded, size: 18),
                              label: Text(s.check),
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
                              Text(s.updateChannel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                s.updateChannelSubtitle,
                                style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
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
                    secondary: const Icon(Icons.schedule_rounded, color: AppTokens.accent),
                    title: Text(s.checkOnLaunch),
                    subtitle: Text(
                      s.checkOnLaunchSubtitle,
                      style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                    ),
                    value: ref.watch(autoCheckUpdatesProvider),
                    onChanged: (val) => ref.read(autoCheckUpdatesProvider.notifier).setAutoCheck(val),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),

          // 8. About
          _buildSectionHeader(s.aboutApp, Icons.info_outline_rounded),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTokens.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Manga Loader', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    s.version(currentVersionStr),
                    style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.aboutDescription,
                    style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary, height: 1.4),
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

  Widget _buildNotificationTimingCard(bool isRu) {
    final s = SettingsStrings(isRu);
    final quiet = ref.watch(quietHoursProvider);
    final digestEnabled = ref.watch(chapterDigestProvider);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTokens.border),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_rounded, color: AppTokens.accent),
            title: Text(s.quietHours),
            subtitle: Text(
              s.quietHoursSubtitle,
              style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
            ),
            value: quiet.enabled,
            onChanged: (val) =>
                ref.read(quietHoursProvider.notifier).update(quiet.copyWith(enabled: val)),
          ),
          if (quiet.enabled) ...[
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.nightlight_round, color: AppTokens.accent),
              title: Text(s.quietHoursStart),
              trailing: _buildHourDropdown(
                quiet.startHour,
                (hour) =>
                    ref.read(quietHoursProvider.notifier).update(quiet.copyWith(startHour: hour)),
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.wb_sunny_rounded, color: AppTokens.accent),
              title: Text(s.quietHoursEnd),
              trailing: _buildHourDropdown(
                quiet.endHour,
                (hour) =>
                    ref.read(quietHoursProvider.notifier).update(quiet.copyWith(endHour: hour)),
              ),
            ),
          ],
          const Divider(height: 1, indent: 56),
          SwitchListTile(
            secondary: const Icon(Icons.mark_email_unread_rounded, color: AppTokens.accent),
            title: Text(s.dailyDigest),
            subtitle: Text(
              s.dailyDigestSubtitle,
              style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
            ),
            value: digestEnabled,
            onChanged: (val) => ref.read(chapterDigestProvider.notifier).setEnabled(val),
          ),
        ],
      ),
    );
  }

  Widget _buildHourDropdown(int value, ValueChanged<int> onChanged) {
    final safeValue = value.clamp(0, 23);
    return DropdownButton<int>(
      value: safeValue,
      dropdownColor: AppTokens.surfaceRaised,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      underline: const SizedBox(),
      items: [
        for (var hour = 0; hour < 24; hour++)
          DropdownMenuItem(
            value: hour,
            child: Text('${hour.toString().padLeft(2, '0')}:00'),
          ),
      ],
      onChanged: (val) {
        if (val != null) onChanged(val);
      },
    );
  }

  String _backupIntervalLabel(int days, bool isRu) {
    final s = SettingsStrings(isRu);
    if (days <= 0) {
      return s.backupsOff;
    }
    return s.backupEvery(Plural.days(days, isRu ? 'ru' : 'en'));
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTokens.accent),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTokens.textPrimary),
          ),
        ],
      ),
    );
  }
}
