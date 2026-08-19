import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/services/streak_notification_service.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;

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

  /// Check library manga for newly released chapters
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
          // Fetch remote chapters
          final remoteChapters = await rust_api.getChapters(slugUrl: entry.slugUrl);
          if (remoteChapters.isEmpty) continue;

          // Check against known total_chapters or entry unread
          final currentKnownCount = entry.totalChapters.toInt();
          if (remoteChapters.length > currentKnownCount && currentKnownCount > 0) {
            final diff = remoteChapters.length - currentKnownCount;
            final latest = remoteChapters.last;
            final chapterStr = 'Том ${latest.volume} Гл ${latest.number}';
            final title = entry.rusName.isNotEmpty ? entry.rusName : entry.name;

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
}
