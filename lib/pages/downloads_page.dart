import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mangaloader/l10n/strings/downloads_strings.dart';
import 'package:mangaloader/providers/download_provider.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/services/content_filter.dart';
import 'package:mangaloader/services/download_queue_service.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/theme/app_tokens.dart';
import 'package:mangaloader/utils/fuzzy_search.dart';

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  List<DownloadedMangaGroup> _mangaGroups = [];
  bool _loading = true;
  String _searchQuery = '';
  String _sortBy = 'title'; // 'title', 'chapters', 'size', 'recent'
  final Map<int, bool> _groupAscending = {};
  List<DownloadQueueItem> _queueItems = DownloadQueueService.instance.items;
  bool _queuePaused = DownloadQueueService.instance.isPaused;

  @override
  void initState() {
    super.initState();
    DownloadQueueService.instance.queue.addListener(_syncQueueItems);
    DownloadQueueService.instance.paused.addListener(_syncPaused);
    _loadDownloaded();
  }

  @override
  void dispose() {
    DownloadQueueService.instance.queue.removeListener(_syncQueueItems);
    DownloadQueueService.instance.paused.removeListener(_syncPaused);
    super.dispose();
  }

  void _syncPaused() {
    if (!mounted) return;
    final next = DownloadQueueService.instance.isPaused;
    if (next == _queuePaused) return;
    setState(() => _queuePaused = next);
  }

  void _syncQueueItems() {
    if (!mounted) return;
    final next = DownloadQueueService.instance.items;
    if (identical(next, _queueItems)) return;
    setState(() => _queueItems = next);
  }

  int get _usedBytes =>
      _mangaGroups.fold<int>(0, (sum, group) => sum + group.totalSizeBytes.toInt());

  Future<void> _loadDownloaded({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await rust_storage.getDownloadedMangaGroups();
      final filtered = !isRuStoreBuild
          ? list
          : list
              .where((g) =>
                  !ContentFilter.isBlockedText(g.name) &&
                  !ContentFilter.isBlockedText(g.rusName) &&
                  !ContentFilter.isBlockedText(g.slugUrl))
              .toList();
      if (mounted) {
        setState(() {
          _mangaGroups = filtered;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Titles go through the fuzzy matcher (typos, Latin transliteration), while
  /// chapter numbers stay exact enough to find "12" inside a downloaded set.
  bool _groupMatches(DownloadedMangaGroup group, String query) {
    if (query.isEmpty) return true;
    if (fuzzyScore(group.rusName, query) > 0 ||
        fuzzyScore(group.name, query) > 0) {
      return true;
    }
    final normalized = normalizeForSearch(query);
    if (normalized.isEmpty) return true;
    return group.chapters.any((chapter) {
      final label = normalizeForSearch('${chapter.volume} ${chapter.number}');
      return label.contains(normalized);
    });
  }

  Future<void> _deleteChapter(DownloadedMangaGroup group, DownloadedChapterInfo ch, bool isRu) async {
    final s = DownloadsStrings(isRu);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceRaised,
        title: Text(s.deleteChapterTitle, style: const TextStyle(color: Colors.white)),
        content: Text(
          s.deleteChapterMessage(ch.volume, ch.number),
          style: const TextStyle(color: AppTokens.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await rust_storage.deleteDownloadedChapter(
        mangaId: ch.mangaId,
        volume: ch.volume,
        number: ch.number,
      );
      _loadDownloaded();
    }
  }

  Future<void> _deleteManga(DownloadedMangaGroup group, bool isRu) async {
    final title = group.rusName.isNotEmpty ? group.rusName : group.name;
    final s = DownloadsStrings(isRu);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceRaised,
        title: Text(s.deleteMangaTitle, style: const TextStyle(color: Colors.white)),
        content: Text(
          s.deleteMangaMessage('${group.chapters.length}', title, _formatBytes(group.totalSizeBytes.toInt())),
          style: const TextStyle(color: AppTokens.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.deleteAll),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await rust_storage.deleteDownloadedManga(mangaId: group.mangaId);
      _loadDownloaded();
    }
  }

  Future<void> _freeUpSpace(bool isRu) async {
    final s = DownloadsStrings(isRu);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceRaised,
        title: Text(
          s.freeUpSpaceTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          s.freeUpSpaceMessage,
          style: const TextStyle(color: AppTokens.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.cleanUp),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await DownloadQueueService.instance.freeUpSpace();
    await _loadDownloaded(silent: true);
    if (!mounted) return;

    final message = result.deletedChapters == 0
        ? s.noReadChapters
        : s.deletedChapters('${result.deletedChapters}', _formatBytes(result.freedBytes));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancelQueue() async {
    ref.read(downloadProvider.notifier).cancelAll();
    final pending = [
      ...DownloadQueueService.instance.pendingItems,
      ...DownloadQueueService.instance.waitingForWifiItems,
    ];
    for (final item in pending) {
      await DownloadQueueService.instance.remove(item);
    }
  }

  String _queueStatusLabel(DownloadQueueItem item, bool isRu) {
    final s = DownloadsStrings(isRu);
    final attemptsSuffix =
        item.attempts > 1 ? s.attempt('${item.attempts}') : '';
    switch (item.status) {
      case DownloadQueueStatus.queued:
        if (_queuePaused) return '${s.statusPaused}$attemptsSuffix';
        return '${s.statusQueued}$attemptsSuffix';
      case DownloadQueueStatus.downloading:
        return '${s.statusDownloading}$attemptsSuffix';
      case DownloadQueueStatus.waitingForWifi:
        return '${s.statusWaitingForWifi}$attemptsSuffix';
      case DownloadQueueStatus.failed:
        final error = item.error;
        if (error == null || error.isEmpty) {
          return '${s.statusFailed}$attemptsSuffix';
        }
        return s.failedWithError(error);
      case DownloadQueueStatus.completed:
        return s.statusDone;
    }
  }

  String _downloadStateLabel(DownloadState state, bool isRu) {
    final s = DownloadsStrings(isRu);
    switch (state) {
      case DownloadState.queued:
        return s.stateQueued;
      case DownloadState.downloading:
        return s.stateDownloading;
      case DownloadState.waitingForNetwork:
        return s.stateWaitingForNetwork;
      case DownloadState.paused:
        return s.statePaused;
      case DownloadState.completed:
        return s.stateCompleted;
      case DownloadState.failed:
        return s.stateFailed;
    }
  }

  Widget _buildStorageCard(bool isRu, int limitMb) {
    final s = DownloadsStrings(isRu);
    final limitBytes = limitMb * 1024 * 1024;
    final usage = limitMb > 0
        ? (_usedBytes / limitBytes).clamp(0.0, 1.0)
        : null;
    final nearLimit = usage != null && usage >= 0.9;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTokens.borderStrong, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sd_storage_rounded, size: 18, color: AppTokens.textPrimary),
                const SizedBox(width: 8),
                Text(
                  s.storage,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  limitMb > 0
                      ? '${_formatBytes(_usedBytes)} / $limitMb MB'
                      : '${_formatBytes(_usedBytes)} · ${s.noLimit}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: nearLimit ? Colors.amberAccent : AppTokens.textSecondary,
                  ),
                ),
              ],
            ),
            if (usage != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usage,
                  minHeight: 6,
                  backgroundColor: AppTokens.border,
                  color: nearLimit ? Colors.amberAccent : AppTokens.accent,
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _freeUpSpace(isRu),
                icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                label: Text(
                  s.freeUpSpace,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildQueueSection(bool isRu) {
    if (_queueItems.isEmpty) return const [];
    final s = DownloadsStrings(isRu);

    final hasCompleted = _queueItems
        .any((item) => item.status == DownloadQueueStatus.completed);
    final activeCount = _queueItems
        .where((item) =>
            item.status == DownloadQueueStatus.queued ||
            item.status == DownloadQueueStatus.downloading)
        .length;
    final resumeAt = DownloadQueueService.instance.scheduleResumeAt;

    return [
      Row(
        children: [
          Expanded(
            child: Text(
              s.downloadQueue,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (activeCount > 0)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _queuePaused ? s.resumeQueue : s.pauseQueue,
              icon: Icon(
                _queuePaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 20,
              ),
              onPressed: () => _queuePaused
                  ? DownloadQueueService.instance.resumeQueue()
                  : DownloadQueueService.instance.pauseQueue(),
            ),
          if (hasCompleted)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => DownloadQueueService.instance.clearCompleted(),
              child: Text(
                s.clearFinished,
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (_queuePaused)
        _buildQueueNotice(
          icon: Icons.pause_circle_outline_rounded,
          title: s.queuePaused,
          subtitle: s.queuePausedHint,
          color: AppTokens.textSecondary,
        )
      else if (resumeAt != null)
        _buildQueueNotice(
          icon: Icons.bedtime_rounded,
          title: s.queueScheduledHint,
          subtitle:
              '${resumeAt.hour.toString().padLeft(2, '0')}:${resumeAt.minute.toString().padLeft(2, '0')}',
          color: Colors.amberAccent,
        ),
      if (_queuePaused || resumeAt != null) const SizedBox(height: 8),
      for (final item in _queueItems) _buildQueueTile(item, isRu),
      const Divider(height: 32),
    ];
  }

  Widget _buildQueueNotice({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        color: color.withValues(alpha: 0.06),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueTile(DownloadQueueItem item, bool isRu) {
    final s = DownloadsStrings(isRu);
    final IconData icon;
    final Color color;
    switch (item.status) {
      case DownloadQueueStatus.queued:
        icon = Icons.schedule_rounded;
        color = AppTokens.textSecondary;
      case DownloadQueueStatus.downloading:
        icon = Icons.downloading_rounded;
        color = AppTokens.accent;
      case DownloadQueueStatus.waitingForWifi:
        icon = Icons.wifi_off_rounded;
        color = Colors.amberAccent;
      case DownloadQueueStatus.failed:
        icon = Icons.error_outline_rounded;
        color = Colors.redAccent;
      case DownloadQueueStatus.completed:
        icon = Icons.check_circle_outline_rounded;
        color = AppTokens.accent;
    }

    final isFailed = item.status == DownloadQueueStatus.failed;
    final isDownloading = item.status == DownloadQueueStatus.downloading;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFailed ? Colors.redAccent.withValues(alpha: 0.5) : AppTokens.border,
          width: 1,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 20, color: color),
        title: Text(
          '${item.slugUrl} · ${s.volumeShort} ${item.volume} ${s.chapterShort} ${item.number}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _queueStatusLabel(item, isRu),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: isFailed ? Colors.redAccent.shade100 : AppTokens.textSecondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFailed)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: s.retry,
                onPressed: () => DownloadQueueService.instance.retry(item),
              ),
            if (!isDownloading)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: s.removeFromQueue,
                onPressed: () => DownloadQueueService.instance.remove(item),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final s = DownloadsStrings.of(context);
    final storageLimitMb = ref.watch(downloadsStorageLimitProvider);

    ref.listen<int>(downloadCompletionTickProvider, (_, __) => _loadDownloaded(silent: true));

    // Filter & Sort manga groups
    final query = _searchQuery.trim();
    var filteredGroups =
        _mangaGroups.where((g) => _groupMatches(g, query)).toList();

    int relevance(DownloadedMangaGroup group) {
      if (query.isEmpty) return 0;
      return [
        fuzzyScore(group.rusName, query),
        fuzzyScore(group.name, query),
      ].reduce((a, b) => a > b ? a : b);
    }

    filteredGroups.sort((a, b) {
      if (query.isNotEmpty) {
        final byRelevance = relevance(b).compareTo(relevance(a));
        if (byRelevance != 0) return byRelevance;
      }
      if (_sortBy == 'chapters') {
        return b.chapters.length.compareTo(a.chapters.length);
      } else if (_sortBy == 'size') {
        return b.totalSizeBytes.compareTo(a.totalSizeBytes);
      } else if (_sortBy == 'recent') {
        final dateA = a.chapters.map((c) => c.downloadedAt).fold('', (p, e) => e.compareTo(p) > 0 ? e : p);
        final dateB = b.chapters.map((c) => c.downloadedAt).fold('', (p, e) => e.compareTo(p) > 0 ? e : p);
        return dateB.compareTo(dateA);
      } else {
        final titleA = a.rusName.isNotEmpty ? a.rusName : a.name;
        final titleB = b.rusName.isNotEmpty ? b.rusName : b.name;
        return titleA.toLowerCase().compareTo(titleB.toLowerCase());
      }
    });

    final sortOptions = [
      (id: 'title', label: s.sortByTitle),
      (id: 'chapters', label: s.sortByChapters),
      (id: 'size', label: s.sortBySize),
      (id: 'recent', label: s.sortByRecent),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: s.openLocalFile,
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['cbz', 'zip'],
              );
              if (result != null && result.files.single.path != null) {
                final path = result.files.single.path!;
                if (context.mounted) {
                  context.push('/read-local?path=${Uri.encodeComponent(path)}');
                }
              }
            },
          ),
          if (_queueItems.any((item) => item.status == DownloadQueueStatus.failed))
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: s.retryAllFailed,
              onPressed: () => DownloadQueueService.instance.retryAllFailed(),
            ),
          if (_queueItems.any((item) =>
              item.status == DownloadQueueStatus.queued ||
              item.status == DownloadQueueStatus.downloading))
            IconButton(
              icon: Icon(_queuePaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              tooltip: _queuePaused ? s.resumeQueue : s.pauseQueue,
              onPressed: () => _queuePaused
                  ? DownloadQueueService.instance.resumeQueue()
                  : DownloadQueueService.instance.pauseQueue(),
            ),
          if (downloads.isNotEmpty ||
              _queueItems.any((item) =>
                  item.status == DownloadQueueStatus.queued ||
                  item.status == DownloadQueueStatus.downloading ||
                  item.status == DownloadQueueStatus.waitingForWifi))
            IconButton(
              icon: const Icon(Icons.cancel_rounded),
              tooltip: s.cancel,
              onPressed: _cancelQueue,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDownloaded,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStorageCard(isRu, storageLimitMb),

            // Persistent queue: queued, waiting for Wi-Fi, failed and finished rows
            ..._buildQueueSection(isRu),

            // Active downloads section
            if (downloads.isNotEmpty) ...[
              Text(
                s.activeDownloads,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...downloads.map((d) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${d.mangaSlug} · ${s.volumeShort} ${d.chapterVolume} ${s.chapterShort} ${d.chapterNumber}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: d.totalPages > 0 ? d.currentPage / d.totalPages : null),
                      const SizedBox(height: 6),
                      Text(
                        '${d.currentPage} / ${d.totalPages} ${s.pageShort} (${_downloadStateLabel(d.state, isRu)})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )),
              const Divider(height: 32),
            ],

            // Downloaded Manga Section Header with Search and Sort
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.downloadedManga,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['cbz', 'zip'],
                    );
                    if (result != null && result.files.single.path != null) {
                      final path = result.files.single.path!;
                      if (context.mounted) {
                        context.push('/read-local?path=${Uri.encodeComponent(path)}');
                      }
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(s.openFile),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Search and Sort controls
            if (_mangaGroups.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: s.searchHint,
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: AppTokens.surfaceRaised,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    initialValue: _sortBy,
                    tooltip: s.sort,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: AppTokens.surfaceRaised,
                    onSelected: (val) => setState(() => _sortBy = val),
                    itemBuilder: (ctx) => sortOptions.map((opt) {
                      final isSel = _sortBy == opt.id;
                      return PopupMenuItem<String>(
                        value: opt.id,
                        child: Row(
                          children: [
                            Icon(
                              isSel ? Icons.check_circle_rounded : Icons.circle_outlined,
                              size: 16,
                              color: isSel ? AppTokens.accent : AppTokens.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              opt.label,
                              style: TextStyle(
                                color: isSel ? Colors.white : AppTokens.textPrimary,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTokens.surfaceRaised,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTokens.borderStrong),
                      ),
                      child: const Icon(Icons.sort_rounded, size: 20, color: AppTokens.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_mangaGroups.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(Icons.offline_pin_outlined, size: 52, color: AppTokens.accent),
                      const SizedBox(height: 12),
                      Text(
                        s.noDownloads,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.noDownloadsSubtitle,
                        style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else if (filteredGroups.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    s.noMatches(_searchQuery),
                    style: const TextStyle(color: AppTokens.textSecondary),
                  ),
                ),
              )
            else
              ...filteredGroups.map((group) {
                final title = group.rusName.isNotEmpty ? group.rusName : group.name;
                final sizeStr = _formatBytes(group.totalSizeBytes.toInt());
                final isAsc = _groupAscending[group.mangaId] ?? true;

                // Sort chapters of this group
                var groupChapters = List<DownloadedChapterInfo>.from(group.chapters);
                groupChapters.sort((a, b) {
                  final volA = double.tryParse(a.volume) ?? 0.0;
                  final volB = double.tryParse(b.volume) ?? 0.0;
                  final numA = double.tryParse(a.number) ?? 0.0;
                  final numB = double.tryParse(b.number) ?? 0.0;
                  final compVol = volA.compareTo(volB);
                  if (compVol != 0) return compVol;
                  return numA.compareTo(numB);
                });

                if (!isAsc) {
                  groupChapters = groupChapters.reversed.toList();
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppTokens.borderStrong, width: 1),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: PageStorageKey(group.mangaId),
                      initiallyExpanded: _mangaGroups.length == 1,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 60,
                          child: group.coverUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: group.coverUrl,
                                httpHeaders: const {'Referer': 'https://mangalib.org/'},
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: AppTokens.border),
                                errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 20),
                              )
                            : Container(
                                color: AppTokens.border,
                                child: const Icon(Icons.menu_book_rounded, color: AppTokens.accent),
                              ),
                        ),
                      ),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTokens.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${group.chapters.length} ${s.chapterCountShort}',
                                style: const TextStyle(color: AppTokens.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(sizeStr, style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            tooltip: s.deleteAllChapters,
                            onPressed: () => _deleteManga(group, isRu),
                          ),
                          if (group.slugUrl.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.info_outline_rounded, size: 20),
                              tooltip: s.openDetails,
                              onPressed: () => context.push('/manga/${group.slugUrl}'),
                            ),
                        ],
                      ),
                      children: [
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(
                            children: [
                              Text(
                                s.chaptersInOrder,
                                style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () {
                                  setState(() {
                                    _groupAscending[group.mangaId] = !isAsc;
                                  });
                                },
                                icon: Icon(isAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14),
                                label: Text(
                                  isAsc ? s.ascending : s.descending,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...groupChapters.map((ch) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTokens.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.archive_outlined, color: AppTokens.textPrimary, size: 18),
                            ),
                            title: Text('Том ${ch.volume} Глава ${ch.number}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('${ch.pageCount} стр. • ${ch.downloadedAt.split("T").first}', style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                  tooltip: s.read,
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppTokens.accent.withValues(alpha: 0.25),
                                    foregroundColor: AppTokens.textPrimary,
                                    minimumSize: const Size(32, 32),
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () {
                                    context.push('/read-local?path=${Uri.encodeComponent(ch.downloadPath)}');
                                  },
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                  tooltip: s.deleteChapter,
                                  onPressed: () => _deleteChapter(group, ch, isRu),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
