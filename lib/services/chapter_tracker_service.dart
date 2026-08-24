import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/services/streak_notification_service.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/src/rust/frb_generated.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;

const String kBackgroundSyncTask = 'mangaloader_background_sync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await RustLib.init();
      final appDir = await getApplicationDocumentsDirectory();
      await rust_storage.initDatabase(appDir: appDir.path);
      await StreakNotificationService.init();

      // Check library updates and app updates
      await ChapterTrackerService.checkBackgroundUpdates();
      await UpdateChecker.checkAppUpdateSilently();
    } catch (e) {
      debugPrint('Background sync task error: $e');
    }
    return Future.value(true);
  });
}

class LibraryUpdateInfo {
  final int mangaId;
  final String slugUrl;
  final String name;
  final String rusName;
  final String coverUrl;
  final int newChaptersCount;
  final String latestChapter;

  const LibraryUpdateInfo({
    required this.mangaId,
    required this.slugUrl,
    required this.name,
    required this.rusName,
    required this.coverUrl,
    required this.newChaptersCount,
    required this.latestChapter,
  });
}

class ChapterTrackerService {
  static bool _isChecking = false;
  static Timer? _periodicTimer;

  /// Initialize background periodic worker for Android and periodic timer for active app
  static Future<void> initBackgroundWork() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      try {
        await Workmanager().initialize(
          callbackDispatcher,
          isInDebugMode: false,
        );
        await Workmanager().registerPeriodicTask(
          kBackgroundSyncTask,
          kBackgroundSyncTask,
          frequency: const Duration(hours: 3),
          constraints: Constraints(
            networkType: NetworkType.connected,
          ),
          existingWorkPolicy: ExistingWorkPolicy.keep,
        );
      } catch (e) {
        debugPrint('Workmanager init error: $e');
      }
    }
  }

  /// Start periodic tracking while the app is active in foreground
  static void startForegroundPeriodicTracking(WidgetRef ref) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 60), (_) {
      checkLibraryUpdates(ref);
      UpdateChecker.checkAppUpdateSilently(
        isRu: ref.read(localeProvider)?.languageCode != 'en',
      );
    });
  }

  /// Check library manga for newly released chapters (called from UI / Riverpod)
  static Future<List<LibraryUpdateInfo>> checkLibraryUpdates(WidgetRef ref) async {
    if (_isChecking) return const [];
    _isChecking = true;

    final updates = <LibraryUpdateInfo>[];

    try {
      final readingList = await rust_storage.getList(listType: 'reading');
      final planList = await rust_storage.getList(listType: 'plan_to_read');
      final allToTrack = [...readingList, ...planList];

      final isRu = ref.read(localeProvider)?.languageCode != 'en';
      final notificationsEnabled = ref.read(chapterNotificationsEnabledProvider);

      for (final entry in allToTrack) {
        if (entry.slugUrl.isEmpty || entry.slugUrl.startsWith('mal-')) continue;

        try {
          final remoteChapters = await rust_api.getChapters(slugUrl: entry.slugUrl);
          if (remoteChapters.isEmpty) continue;

          final currentKnownCount = entry.totalChapters.toInt();

          if (remoteChapters.length > currentKnownCount && currentKnownCount > 0) {
            final diff = remoteChapters.length - currentKnownCount;
            final latest = remoteChapters.last;
            final chapterStr = 'Том ${latest.volume} Гл ${latest.number}';
            final title = entry.rusName.isNotEmpty ? entry.rusName : entry.name;

            // Update database baseline so subsequent checks won't repeat this notification
            await rust_storage.updateMangaChaptersCount(
              mangaId: entry.mangaId.toInt(),
              chaptersCount: remoteChapters.length,
            );

            updates.add(LibraryUpdateInfo(
              mangaId: entry.mangaId.toInt(),
              slugUrl: entry.slugUrl,
              name: entry.name,
              rusName: entry.rusName,
              coverUrl: entry.coverUrl,
              newChaptersCount: diff,
              latestChapter: chapterStr,
            ));

            if (notificationsEnabled) {
              await StreakNotificationService.showChapterUpdateNotification(
                mangaId: entry.mangaId.toInt(),
                mangaTitle: title,
                chapterInfo: chapterStr,
                isRu: isRu,
              );
            }
          } else if (currentKnownCount == 0 && remoteChapters.isNotEmpty) {
            // Set initial baseline
            await rust_storage.updateMangaChaptersCount(
              mangaId: entry.mangaId.toInt(),
              chaptersCount: remoteChapters.length,
            );
          }
        } catch (e) {
          debugPrint('Error checking updates for ${entry.slugUrl}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error in checkLibraryUpdates: $e');
    } finally {
      _isChecking = false;
    }

    return updates;
  }

  /// Headless background checker for Workmanager
  static Future<void> checkBackgroundUpdates({bool isRu = true}) async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final readingList = await rust_storage.getList(listType: 'reading');
      final planList = await rust_storage.getList(listType: 'plan_to_read');
      final allToTrack = [...readingList, ...planList];

      for (final entry in allToTrack) {
        if (entry.slugUrl.isEmpty || entry.slugUrl.startsWith('mal-')) continue;

        try {
          final remoteChapters = await rust_api.getChapters(slugUrl: entry.slugUrl);
          if (remoteChapters.isEmpty) continue;

          final currentKnownCount = entry.totalChapters.toInt();

          if (remoteChapters.length > currentKnownCount && currentKnownCount > 0) {
            final latest = remoteChapters.last;
            final chapterStr = 'Том ${latest.volume} Гл ${latest.number}';
            final title = entry.rusName.isNotEmpty ? entry.rusName : entry.name;

            await rust_storage.updateMangaChaptersCount(
              mangaId: entry.mangaId.toInt(),
              chaptersCount: remoteChapters.length,
            );

            await StreakNotificationService.showChapterUpdateNotification(
              mangaId: entry.mangaId.toInt(),
              mangaTitle: title,
              chapterInfo: chapterStr,
              isRu: isRu,
            );
          } else if (currentKnownCount == 0 && remoteChapters.isNotEmpty) {
            await rust_storage.updateMangaChaptersCount(
              mangaId: entry.mangaId.toInt(),
              chaptersCount: remoteChapters.length,
            );
          }
        } catch (e) {
          debugPrint('Background check error for ${entry.slugUrl}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error in checkBackgroundUpdates: $e');
    } finally {
      _isChecking = false;
    }
  }
}
