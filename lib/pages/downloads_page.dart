import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mangaloader/providers/download_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  List<DownloadedMangaGroup> _mangaGroups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloaded();
  }

  Future<void> _loadDownloaded() async {
    setState(() => _loading = true);
    try {
      final list = await rust_storage.getDownloadedMangaGroups();
      if (mounted) {
        setState(() {
          _mangaGroups = list;
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
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(isRu ? 'Удалить главу?' : 'Delete chapter?', style: const TextStyle(color: Colors.white)),
        content: Text(
          isRu 
            ? 'Удалить Том ${ch.volume} Гл ${ch.number} из памяти устройства?'
            : 'Delete Vol ${ch.volume} Ch ${ch.number} from storage?',
          style: const TextStyle(color: Color(0xFFD2D7DF)),
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
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(isRu ? 'Удалить всю мангу?' : 'Delete entire manga?', style: const TextStyle(color: Colors.white)),
        content: Text(
          isRu 
            ? 'Удалить все ${group.chapters.length} скачанные главы "$title" (${_formatBytes(group.totalSizeBytes.toInt())})?'
            : 'Delete all ${group.chapters.length} downloaded chapters of "$title"?',
          style: const TextStyle(color: Color(0xFFD2D7DF)),
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

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

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
            IconButton(
              icon: const Icon(Icons.cancel_rounded),
              tooltip: isRu ? 'Отмена' : 'Cancel',
              onPressed: () => ref.read(downloadProvider.notifier).cancelAll(),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDownloaded,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                  title: Text('${d.mangaSlug} - Vol ${d.chapterVolume} Ch ${d.chapterNumber}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: d.totalPages > 0 ? d.currentPage / d.totalPages : null),
                      const SizedBox(height: 6),
                      Text('${d.currentPage} / ${d.totalPages} стр. (${d.state.name})', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              )),
              const Divider(height: 32),
            ],

            // Downloaded Manga Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isRu ? 'Скачанная манга (CBZ)' : 'Downloaded Manga (CBZ)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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

            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_mangaGroups.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(Icons.offline_pin_outlined, size: 52, color: Color(0xFF8A897C)),
                      const SizedBox(height: 12),
                      Text(
                        isRu ? 'Нет скачанных глав' : 'No downloaded chapters',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isRu ? 'Скачайте главы со страницы тайтла или откройте локальный .cbz файл' : 'Download chapters from manga page or open a local .cbz file',
                        style: const TextStyle(color: Color(0xFFBDBBB0), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._mangaGroups.map((group) {
                final title = group.rusName.isNotEmpty ? group.rusName : group.name;
                final sizeStr = _formatBytes(group.totalSizeBytes.toInt());

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFF3E3E3E), width: 1),
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
                                placeholder: (_, __) => Container(color: const Color(0xFF353535)),
                                errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 20),
                              )
                            : Container(
                                color: const Color(0xFF353535),
                                child: const Icon(Icons.menu_book_rounded, color: Color(0xFF8A897C)),
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
                                color: const Color(0xFF8A897C).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${group.chapters.length} ${isRu ? "гл." : "ch."}',
                                style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(sizeStr, style: const TextStyle(color: Color(0xFFBDBBB0), fontSize: 12)),
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
                        ...group.chapters.map((ch) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8A897C).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.archive_outlined, color: Color(0xFFD2D7DF), size: 18),
                            ),
                            title: Text('Том ${ch.volume} Глава ${ch.number}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('${ch.pageCount} стр. • ${ch.downloadedAt.split("T").first}', style: const TextStyle(fontSize: 11, color: Color(0xFFBDBBB0))),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                  tooltip: isRu ? 'Читать' : 'Read',
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFF8A897C).withValues(alpha: 0.25),
                                    foregroundColor: const Color(0xFFD2D7DF),
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
