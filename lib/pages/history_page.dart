import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/desktop/desktop_layout.dart';
import 'package:mangaloader/desktop/desktop_platform.dart';
import 'package:mangaloader/desktop/desktop_providers.dart';
import 'package:mangaloader/desktop/desktop_widgets.dart';
import 'package:mangaloader/l10n/strings/desktop_strings.dart';
import 'package:mangaloader/l10n/strings/history_strings.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:shimmer/shimmer.dart';

import 'package:mangaloader/services/content_filter.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/theme/app_tokens.dart';

final historyProvider = FutureProvider.autoDispose<List<ReadingHistoryItem>>((ref) async {
  final items = await rust_storage.getReadingHistory(limit: 200, offset: 0);
  if (!isRuStoreBuild) return items;
  return items
      .where((i) =>
          !ContentFilter.isBlockedText(i.name) &&
          !ContentFilter.isBlockedText(i.rusName) &&
          !ContentFilter.isBlockedText(i.slugUrl))
      .toList();
});

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _formatDate(String isoDate, bool isRu) {
    final s = HistoryStrings(isRu);
    try {
      final dt = DateTime.parse(isoDate.replaceAll(' ', 'T')).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final itemDate = DateTime(dt.year, dt.month, dt.day);

      final diffDays = today.difference(itemDate).inDays;
      final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

      if (diffDays == 0) {
        return s.todayAt(timeStr);
      } else if (diffDays == 1) {
        return s.yesterdayAt(timeStr);
      } else if (diffDays < 7) {
        return s.daysAgo('$diffDays');
      } else {
        return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
      }
    } catch (_) {
      return isoDate;
    }
  }

  String _getDateGroup(String isoDate, bool isRu) {
    final s = HistoryStrings(isRu);
    try {
      final dt = DateTime.parse(isoDate.replaceAll(' ', 'T')).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final itemDate = DateTime(dt.year, dt.month, dt.day);

      final diffDays = today.difference(itemDate).inDays;

      if (diffDays == 0) {
        return s.today;
      } else if (diffDays == 1) {
        return s.yesterday;
      } else if (diffDays < 7) {
        return s.thisWeek;
      } else if (diffDays < 30) {
        return s.thisMonth;
      } else {
        return s.earlier;
      }
    } catch (_) {
      return s.earlier;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRu = ref.watch(localeProvider)?.languageCode != 'en';
    final s = HistoryStrings(isRu);
    final historyAsync = ref.watch(historyProvider);

    if (isDesktopPlatform) {
      ref.listen<int>(desktopRefreshProvider, (_, __) {
        ref.invalidate(historyProvider);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: s.clearHistory,
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(s.clearHistoryTitle),
                  content: Text(s.clearHistoryMessage),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(s.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                      child: Text(s.clear),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await rust_storage.clearReadingHistory();
                ref.invalidate(historyProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.historyCleared)),
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
                    s.emptyTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.emptySubtitle,
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

          if (isDesktopPlatform) {
            return _buildDesktopHistory(groups, isRu);
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
                      final chapStr = s.chapterLabel(item.volume, item.number);

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
                                                  s.completed,
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
                                                  s.page(
                                                    '${item.pageIndex + 1}${item.totalPages > 0 ? "/${item.totalPages}" : ""}',
                                                  ),
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
                                        '/read/${item.slugUrl}/${item.volume}/${item.number}?mangaId=${item.mangaId}',
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
          child: Text(s.errorLoading('$err')),
        ),
      ),
    );
  }

  Widget _buildDesktopHistory(
    Map<String, List<ReadingHistoryItem>> groups,
    bool isRu,
  ) {
    final d = DesktopStrings(isRu);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(historyProvider),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesktopLayout.tableMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Row(
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.value.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(
                      color: AppTokens.borderStrong,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DesktopTableHeader(
                        children: [
                          const SizedBox(width: 52),
                          DesktopTableHeaderCell(
                            label: d.columnTitle,
                            flex: 5,
                          ),
                          DesktopTableHeaderCell(
                            label: d.columnChapter,
                            flex: 3,
                          ),
                          DesktopTableHeaderCell(
                            label: d.columnReadAt,
                            flex: 2,
                          ),
                          DesktopTableHeaderCell(
                            label: d.columnProgress,
                            flex: 2,
                          ),
                          const SizedBox(width: 88),
                        ],
                      ),
                      for (var index = 0; index < entry.value.length; index++)
                        _buildDesktopHistoryRow(
                          entry.value[index],
                          isRu,
                          showDivider: index > 0,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopHistoryRow(
    ReadingHistoryItem item,
    bool isRu, {
    required bool showDivider,
  }) {
    final s = HistoryStrings(isRu);
    final d = DesktopStrings(isRu);
    final title = item.rusName.isNotEmpty ? item.rusName : item.name;

    return DesktopHoverSurface(
      onTap: () => context.push('/manga/${item.slugUrl}'),
      onSecondaryTapDown: (details) => _showDesktopHistoryMenu(
        item,
        details.globalPosition,
        isRu,
      ),
      builder: (context, hovered) {
        return Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: hovered
                ? Colors.white.withValues(alpha: 0.035)
                : Colors.transparent,
            border: showDivider
                ? const Border(
                    top: BorderSide(color: AppTokens.border, width: 1),
                  )
                : null,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: CachedNetworkImage(
                  imageUrl: item.coverUrl,
                  width: 38,
                  height: 50,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppTokens.border),
                  errorWidget: (_, __, ___) => Container(
                    color: AppTokens.border,
                    child: const Icon(
                      Icons.menu_book_rounded,
                      size: 15,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  s.chapterLabel(item.volume, item.number),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTokens.textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _formatDate(item.lastReadAt, isRu),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildDesktopProgress(item, s),
                ),
              ),
              SizedBox(
                width: 88,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: d.openReader,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.play_arrow_rounded, size: 19),
                      onPressed: () => context.push(
                        '/read/${item.slugUrl}/${item.volume}/${item.number}?mangaId=${item.mangaId}',
                      ),
                    ),
                    IconButton(
                      tooltip: d.removeFromHistory,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 17,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _removeHistoryItem(item),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopProgress(ReadingHistoryItem item, HistoryStrings s) {
    if (item.isCompleted) {
      return _desktopProgressChip(
        s.completed,
        const Color(0xFF4CAF50),
      );
    }
    if (item.pageIndex > 0) {
      return _desktopProgressChip(
        s.page(
          '${item.pageIndex + 1}${item.totalPages > 0 ? "/${item.totalPages}" : ""}',
        ),
        Colors.amber,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _desktopProgressChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Future<void> _removeHistoryItem(ReadingHistoryItem item) async {
    await rust_storage.deleteReadingHistoryItem(
      mangaId: item.mangaId,
      volume: item.volume,
      number: item.number,
    );
    ref.invalidate(historyProvider);
  }

  Future<void> _showDesktopHistoryMenu(
    ReadingHistoryItem item,
    Offset position,
    bool isRu,
  ) async {
    final d = DesktopStrings(isRu);
    final action = await showDesktopMenu<String>(
      context: context,
      globalPosition: position,
      items: [
        desktopMenuItem(
          value: 'details',
          icon: Icons.open_in_new_rounded,
          label: d.openDetails,
        ),
        desktopMenuItem(
          value: 'read',
          icon: Icons.play_arrow_rounded,
          label: d.continueReading,
        ),
        const PopupMenuDivider(),
        desktopMenuItem(
          value: 'remove',
          icon: Icons.delete_outline_rounded,
          label: d.removeFromHistory,
          destructive: true,
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'details') {
      await context.push('/manga/${item.slugUrl}');
    } else if (action == 'read') {
      await context.push(
        '/read/${item.slugUrl}/${item.volume}/${item.number}?mangaId=${item.mangaId}',
      );
    } else if (action == 'remove') {
      await _removeHistoryItem(item);
    }
  }
}
