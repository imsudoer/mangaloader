import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:shimmer/shimmer.dart';

final historyProvider = FutureProvider.autoDispose<List<ReadingHistoryItem>>((ref) async {
  return await rust_storage.getReadingHistory(limit: 200, offset: 0);
});

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _formatDate(String isoDate, bool isRu) {
    try {
      final dt = DateTime.parse(isoDate.replaceAll(' ', 'T')).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final itemDate = DateTime(dt.year, dt.month, dt.day);

      final diffDays = today.difference(itemDate).inDays;
      final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

      if (diffDays == 0) {
        return isRu ? 'Сегодня, $timeStr' : 'Today, $timeStr';
      } else if (diffDays == 1) {
        return isRu ? 'Вчера, $timeStr' : 'Yesterday, $timeStr';
      } else if (diffDays < 7) {
        return isRu ? '$diffDays дн. назад' : '$diffDays days ago';
      } else {
        return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
      }
    } catch (_) {
      return isoDate;
    }
  }

  String _getDateGroup(String isoDate, bool isRu) {
    try {
      final dt = DateTime.parse(isoDate.replaceAll(' ', 'T')).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final itemDate = DateTime(dt.year, dt.month, dt.day);

      final diffDays = today.difference(itemDate).inDays;

      if (diffDays == 0) {
        return isRu ? 'Сегодня' : 'Today';
      } else if (diffDays == 1) {
        return isRu ? 'Вчера' : 'Yesterday';
      } else if (diffDays < 7) {
        return isRu ? 'На этой неделе' : 'This week';
      } else if (diffDays < 30) {
        return isRu ? 'В этом месяце' : 'This month';
      } else {
        return isRu ? 'Ранее' : 'Earlier';
      }
    } catch (_) {
      return isRu ? 'Ранее' : 'Earlier';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRu = ref.watch(localeProvider)?.languageCode != 'en';
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isRu ? 'История чтения' : 'Reading History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: isRu ? 'Очистить историю' : 'Clear history',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(isRu ? 'Очистить историю?' : 'Clear history?'),
                  content: Text(
                    isRu
                        ? 'Вся история прочитанных глав будет удалена. Прогресс в библиотеке сохранится.'
                        : 'All reading history will be deleted. Library progress will remain.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(isRu ? 'Отмена' : 'Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                      child: Text(isRu ? 'Очистить' : 'Clear'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await rust_storage.clearReadingHistory();
                ref.invalidate(historyProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isRu ? 'История очищена' : 'History cleared')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: historyAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 72,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isRu ? 'История чтения пуста' : 'Reading history is empty',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isRu ? 'Здесь появятся прочитанные главы' : 'Read chapters will appear here',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            );
          }

          final groups = <String, List<ReadingHistoryItem>>{};
          for (final item in items) {
            final group = _getDateGroup(item.lastReadAt, isRu);
            groups.putIfAbsent(group, () => []).add(item);
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(historyProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: groups.length,
              itemBuilder: (context, groupIndex) {
                final groupKey = groups.keys.elementAt(groupIndex);
                final groupItems = groups[groupKey]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8, left: 4),
                      child: Text(
                        groupKey,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    ...groupItems.map((item) {
                      final title = item.rusName.isNotEmpty ? item.rusName : item.name;
                      final chapStr = isRu
                          ? 'Том ${item.volume} Глава ${item.number}'
                          : 'Vol. ${item.volume} Ch. ${item.number}';

                      return Dismissible(
                        key: Key('hist_${item.mangaId}_${item.volume}_${item.number}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        onDismissed: (_) async {
                          await rust_storage.deleteReadingHistoryItem(
                            mangaId: item.mangaId,
                            volume: item.volume,
                            number: item.number,
                          );
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              context.push('/manga/${item.slugUrl}');
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: item.coverUrl,
                                      width: 48,
                                      height: 68,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: Colors.grey.withValues(alpha: 0.2),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: Colors.grey.withValues(alpha: 0.2),
                                        child: const Icon(Icons.menu_book, size: 24),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          chapStr,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (item.isCompleted)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                margin: const EdgeInsets.only(right: 6),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  isRu ? 'Прочитано' : 'Completed',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF4CAF50),
                                                  ),
                                                ),
                                              )
                                            else if (item.pageIndex > 0)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                margin: const EdgeInsets.only(right: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  isRu
                                                      ? 'Стр. ${item.pageIndex + 1}${item.totalPages > 0 ? "/${item.totalPages}" : ""}'
                                                      : 'Page ${item.pageIndex + 1}${item.totalPages > 0 ? "/${item.totalPages}" : ""}',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.amber,
                                                  ),
                                                ),
                                              ),
                                            Text(
                                              _formatDate(item.lastReadAt, isRu),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                                    onPressed: () {
                                      context.push(
                                        '/reader/${item.slugUrl}/${item.volume}/${item.number}?mangaId=${item.mangaId}',
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          );
        },
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 8,
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Shimmer.fromColors(
              baseColor: Colors.grey.withValues(alpha: 0.15),
              highlightColor: Colors.grey.withValues(alpha: 0.05),
              child: Container(
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        error: (err, _) => Center(
          child: Text('${isRu ? "Ошибка загрузки истории" : "Error loading history"}: $err'),
        ),
      ),
    );
  }
}
