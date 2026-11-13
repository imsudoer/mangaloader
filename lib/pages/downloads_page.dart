import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mangaloader/providers/download_provider.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/services/content_filter.dart';
import 'package:mangaloader/services/download_queue_service.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/theme/app_tokens.dart';

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

  @override
  void initState() {
    super.initState();
    DownloadQueueService.instance.queue.addListener(_syncQueueItems);
    _loadDownloaded();
  }

  @override
  void dispose() {
    DownloadQueueService.instance.queue.removeListener(_syncQueueItems);
    super.dispose();
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

  Future<void> _deleteChapter(DownloadedMangaGroup group, DownloadedChapterInfo ch, bool isRu) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceRaised,
        title: Text(isRu ? 'Удалить главу?' : 'Delete chapter?', style: const TextStyle(color: Colors.white)),
        content: Text(
          isRu 
            ? 'Удалить Том ${ch.volume} Гл ${ch.number} из памяти устройства?'
            : 'Delete Vol ${ch.volume} Ch ${ch.number} from storage?',
          style: const TextStyle(color: AppTokens.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isRu ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isRu ? 'Удалить' : 'Delete'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceRaised,
        title: Text(isRu ? 'Удалить всю мангу?' : 'Delete entire manga?', style: const TextStyle(color: Colors.white)),
        content: Text(
          isRu 
            ? 'Удалить все ${group.chapters.length} скачанные главы "$title" (${_formatBytes(group.totalSizeBytes.toInt())})?'
            : 'Delete all ${group.chapters.length} downloaded chapters of "$title"?',
          style: const TextStyle(color: AppTokens.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isRu ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isRu ? 'Удалить всё' : 'Delete all'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceRaised,
        title: Text(
          isRu ? 'Освободить место?' : 'Free up space?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          isRu
              ? 'Будут удалены скачанные главы, отмеченные как прочитанные.'
              : 'Downloaded chapters marked as read will be deleted.',
          style: const TextStyle(color: AppTokens.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isRu ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isRu ? 'Очистить' : 'Clean up'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await DownloadQueueService.instance.freeUpSpace();
    await _loadDownloaded(silent: true);
    if (!mounted) return;

    final message = result.deletedChapters == 0
        ? (isRu ? 'Прочитанных глав для удаления нет' : 'No read chapters to delete')
        : (isRu
            ? 'Удалено глав: ${result.deletedChapters} · ${_formatBytes(result.freedBytes)}'
            : 'Deleted ${result.deletedChapters} chapters · ${_formatBytes(result.freedBytes)}');
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
    final attemptsSuffix = item.attempts > 1
        ? (isRu ? ' · попытка ${item.attempts}' : ' · attempt ${item.attempts}')
        : '';
    switch (item.status) {
      case DownloadQueueStatus.queued:
        return isRu ? 'В очереди$attemptsSuffix' : 'Queued$attemptsSuffix';
      case DownloadQueueStatus.downloading:
        return isRu ? 'Загружается$attemptsSuffix' : 'Downloading$attemptsSuffix';
      case DownloadQueueStatus.waitingForWifi:
        return isRu ? 'Ожидает Wi-Fi$attemptsSuffix' : 'Waiting for Wi-Fi$attemptsSuffix';
      case DownloadQueueStatus.failed:
        final error = item.error;
        if (error == null || error.isEmpty) {
          return isRu ? 'Ошибка загрузки$attemptsSuffix' : 'Download failed$attemptsSuffix';
        }
        return isRu ? 'Ошибка: $error' : 'Failed: $error';
      case DownloadQueueStatus.completed:
        return isRu ? 'Готово' : 'Done';
    }
  }

  String _downloadStateLabel(DownloadState state, bool isRu) {
    switch (state) {
      case DownloadState.queued:
        return isRu ? 'в очереди' : 'queued';
      case DownloadState.downloading:
        return isRu ? 'загрузка' : 'downloading';
      case DownloadState.waitingForNetwork:
        return isRu ? 'ожидание сети' : 'waiting for network';
      case DownloadState.paused:
        return isRu ? 'пауза' : 'paused';
      case DownloadState.completed:
        return isRu ? 'готово' : 'done';
      case DownloadState.failed:
        return isRu ? 'ошибка' : 'failed';
    }
  }

  Widget _buildStorageCard(bool isRu, int limitMb) {
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
                  isRu ? 'Хранилище' : 'Storage',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  limitMb > 0
                      ? '${_formatBytes(_usedBytes)} / $limitMb MB'
                      : '${_formatBytes(_usedBytes)} · ${isRu ? "без лимита" : "no limit"}',
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
                  isRu ? 'Освободить место' : 'Free up space',
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

    final hasCompleted = _queueItems
        .any((item) => item.status == DownloadQueueStatus.completed);

    return [
      Row(
        children: [
          Expanded(
            child: Text(
              isRu ? 'Очередь загрузок' : 'Download queue',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (hasCompleted)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => DownloadQueueService.instance.clearCompleted(),
              child: Text(
                isRu ? 'Очистить готовые' : 'Clear finished',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      for (final item in _queueItems) _buildQueueTile(item, isRu),
      const Divider(height: 32),
    ];
  }

  Widget _buildQueueTile(DownloadQueueItem item, bool isRu) {
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
          '${item.slugUrl} · ${isRu ? "Том" : "Vol"} ${item.volume} ${isRu ? "Гл" : "Ch"} ${item.number}',
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
                tooltip: isRu ? 'Повторить' : 'Retry',
                onPressed: () => DownloadQueueService.instance.retry(item),
              ),
            if (!isDownloading)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: isRu ? 'Убрать из очереди' : 'Remove from queue',
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
    final storageLimitMb = ref.watch(downloadsStorageLimitProvider);

    ref.listen<int>(downloadCompletionTickProvider, (_, __) => _loadDownloaded(silent: true));

    // Filter & Sort manga groups
    var filteredGroups = _mangaGroups.where((g) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final inTitle = g.name.toLowerCase().contains(q) || g.rusName.toLowerCase().contains(q);
      final inChapters = g.chapters.any((c) => c.number.toLowerCase().contains(q) || c.volume.toLowerCase().contains(q));
      return inTitle || inChapters;
    }).toList();

    filteredGroups.sort((a, b) {
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
      {'id': 'title', 'labelRu': 'По названию (А-Я)', 'labelEn': 'By Title (A-Z)'},
      {'id': 'chapters', 'labelRu': 'По числу глав', 'labelEn': 'Most Chapters'},
      {'id': 'size', 'labelRu': 'По размеру файлов', 'labelEn': 'Largest Size'},
      {'id': 'recent', 'labelRu': 'Недавно скачанные', 'labelEn': 'Recently Downloaded'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isRu ? 'Загрузки и файлы' : 'Downloads & Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: isRu ? 'Открыть локальный файл CBZ / ZIP' : 'Open local CBZ / ZIP',
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
              tooltip: isRu ? 'Повторить все ошибки' : 'Retry all failed',
              onPressed: () => DownloadQueueService.instance.retryAllFailed(),
            ),
          if (downloads.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.pause_rounded),
              tooltip: isRu ? 'Пауза' : 'Pause',
              onPressed: () => ref.read(downloadProvider.notifier).pauseAll(),
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: isRu ? 'Продолжить' : 'Resume',
              onPressed: () => ref.read(downloadProvider.notifier).resumeAll(),
            ),
          ],
          if (downloads.isNotEmpty ||
              _queueItems.any((item) =>
                  item.status == DownloadQueueStatus.queued ||
                  item.status == DownloadQueueStatus.downloading ||
                  item.status == DownloadQueueStatus.waitingForWifi))
            IconButton(
              icon: const Icon(Icons.cancel_rounded),
              tooltip: isRu ? 'Отмена' : 'Cancel',
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
                isRu ? 'Активные загрузки' : 'Active Downloads',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...downloads.map((d) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${d.mangaSlug} · ${isRu ? "Том" : "Vol"} ${d.chapterVolume} ${isRu ? "Гл" : "Ch"} ${d.chapterNumber}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: d.totalPages > 0 ? d.currentPage / d.totalPages : null),
                      const SizedBox(height: 6),
                      Text(
                        '${d.currentPage} / ${d.totalPages} ${isRu ? "стр." : "p."} (${_downloadStateLabel(d.state, isRu)})',
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
                    isRu ? 'Скачанная манга (CBZ)' : 'Downloaded Manga (CBZ)',
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
                  label: Text(isRu ? 'Открыть файл' : 'Open file'),
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
                        hintText: isRu ? 'Поиск в скачанных...' : 'Search downloads...',
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
                    tooltip: isRu ? 'Сортировка' : 'Sort',
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: AppTokens.surfaceRaised,
                    onSelected: (val) => setState(() => _sortBy = val),
                    itemBuilder: (ctx) => sortOptions.map((opt) {
                      final isSel = _sortBy == opt['id'];
                      return PopupMenuItem<String>(
                        value: opt['id'] as String,
                        child: Row(
                          children: [
                            Icon(
                              isSel ? Icons.check_circle_rounded : Icons.circle_outlined,
                              size: 16,
                              color: isSel ? AppTokens.accent : AppTokens.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isRu ? opt['labelRu'] as String : opt['labelEn'] as String,
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
                        isRu ? 'Нет скачанных глав' : 'No downloaded chapters',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isRu ? 'Скачайте главы со страницы тайтла или откройте локальный .cbz файл' : 'Download chapters from manga page or open a local .cbz file',
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
                    isRu ? 'Ничего не найдено по запросу "$_searchQuery"' : 'No matches for "$_searchQuery"',
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
                                '${group.chapters.length} ${isRu ? "гл." : "ch."}',
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
                            tooltip: isRu ? 'Удалить все главы' : 'Delete all chapters',
                            onPressed: () => _deleteManga(group, isRu),
                          ),
                          if (group.slugUrl.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.info_outline_rounded, size: 20),
                              tooltip: isRu ? 'Открыть страницу тайтла' : 'Open details',
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
                                isRu ? 'Главы по порядку:' : 'Chapters in order:',
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
                                  isAsc ? (isRu ? 'С первых глав' : 'Ascending (1.0 ->)') : (isRu ? 'С последних глав' : 'Descending'),
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
                                  tooltip: isRu ? 'Читать' : 'Read',
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
                                  tooltip: isRu ? 'Удалить главу' : 'Delete chapter',
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
