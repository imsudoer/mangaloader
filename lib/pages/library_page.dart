import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/library_provider.dart';
import 'package:mangaloader/providers/continue_reading_provider.dart';
import 'package:mangaloader/providers/streak_provider.dart';
import 'package:mangaloader/providers/custom_lists_provider.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mangaloader/utils/plural.dart';
import 'package:mangaloader/theme/app_tokens.dart';

enum LibrarySortMode { recent, title, rating, progress, chapters }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchOpen = false;
  bool _isGridView = true;
  LibrarySortMode _sortMode = LibrarySortMode.recent;
  bool _isSyncingWithMangaLib = false;

  bool _selectionMode = false;
  final Set<int> _selectedMangaIds = {};

  Future<void> _syncWithMangaLib(BuildContext context, bool isRu) async {
    final profile = ref.read(currentUserProfileProvider);
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRu ? 'Войдите в аккаунт MangaLib для синхронизации' : 'Sign in to MangaLib to sync'),
          action: SnackBarAction(
            label: isRu ? 'Войти' : 'Sign In',
            onPressed: () => context.push('/login'),
          ),
        ),
      );
      return;
    }

    setState(() => _isSyncingWithMangaLib = true);
    try {
      int imported = 0;
      final statusMap = {
        1: 'reading',
        2: 'plan_to_read',
        3: 'dropped',
        4: 'completed',
        5: 'favorites',
        6: 'on_hold',
      };

      for (final entry in statusMap.entries) {
        final bookmarks = await rust_api.getUserBookmarks(userId: profile.id, status: entry.key);
        if (bookmarks.isNotEmpty) {
          final count = await rust_storage.bulkImportBookmarks(items: bookmarks, listType: entry.value);
          imported += count.toInt();
        }
      }

      await ref.read(libraryProvider.notifier).loadAll();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRu ? 'Синхронизировано $imported тайтлов из MangaLib' : 'Synced $imported titles from MangaLib'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка синхронизации: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingWithMangaLib = false);
    }
  }

  final List<Map<String, dynamic>> _categoryTabs = [
    {'type': null, 'labelRu': 'Все', 'labelEn': 'All', 'icon': Icons.grid_view_rounded},
    {'type': ListType.reading, 'labelRu': 'Читаю', 'labelEn': 'Reading', 'icon': Icons.auto_stories_rounded, 'color': Color(0xFF64B5F6)},
    {'type': ListType.planToRead, 'labelRu': 'В планах', 'labelEn': 'Plan to Read', 'icon': Icons.bookmark_rounded, 'color': Color(0xFFFFB74D)},
    {'type': ListType.completed, 'labelRu': 'Прочитано', 'labelEn': 'Completed', 'icon': Icons.check_circle_rounded, 'color': Color(0xFF81C784)},
    {'type': ListType.favorites, 'labelRu': 'Любимое', 'labelEn': 'Favorites', 'icon': Icons.favorite_rounded, 'color': Color(0xFFF06292)},
    {'type': ListType.onHold, 'labelRu': 'Отложено', 'labelEn': 'On Hold', 'icon': Icons.pause_circle_outline_rounded, 'color': Colors.grey},
    {'type': ListType.dropped, 'labelRu': 'Брошено', 'labelEn': 'Dropped', 'icon': Icons.delete_outline_rounded, 'color': Colors.redAccent},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categoryTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<LibraryEntry> _filterAndSort(List<LibraryEntry> all, ListType? filterType, String query) {
    // Copy first: the provider state list must never be reordered in place.
    var list = List<LibraryEntry>.of(all);
    if (filterType != null) {
      list = list.where((e) => e.listType == filterType).toList();
    }
    if (query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q) || e.rusName.toLowerCase().contains(q)).toList();
    }

    switch (_sortMode) {
      case LibrarySortMode.recent:
        break;
      case LibrarySortMode.title:
        list.sort((a, b) {
          final tA = a.rusName.isNotEmpty ? a.rusName : a.name;
          final tB = b.rusName.isNotEmpty ? b.rusName : b.name;
          return tA.compareTo(tB);
        });
        break;
      case LibrarySortMode.rating:
        list.sort((a, b) {
          final rA = double.tryParse(a.ratingAverage) ?? 0.0;
          final rB = double.tryParse(b.ratingAverage) ?? 0.0;
          return rB.compareTo(rA);
        });
        break;
      case LibrarySortMode.progress:
        list.sort((a, b) {
          final pA = a.totalChapters > 0 ? a.readChapters / a.totalChapters : 0.0;
          final pB = b.totalChapters > 0 ? b.readChapters / b.totalChapters : 0.0;
          return pB.compareTo(pA);
        });
        break;
      case LibrarySortMode.chapters:
        list.sort((a, b) => b.totalChapters.compareTo(a.totalChapters));
        break;
    }
    return list;
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

  void _showCreateListDialog(bool isRu) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceCard,
        title: Text(isRu ? 'Новый список' : 'New Custom List'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isRu ? 'Название списка' : 'List name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isRu ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(customListsProvider.notifier).createList(name);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: Text(isRu ? 'Создать' : 'Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelectionMode();
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final libState = ref.watch(libraryProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final allEntries = libState.valueOrNull ?? const <LibraryEntry>[];
    final selectedEntries =
        allEntries.where((e) => _selectedMangaIds.contains(e.mangaId.toInt())).toList();
    final downloadedIds =
        ref.watch(downloadedMangaIdsProvider).valueOrNull ?? const <int>{};
    final hasSelectedDownloads = selectedEntries
        .any((entry) => downloadedIds.contains(entry.mangaId.toInt()));

    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
          ? IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: isRu ? 'Выйти из выбора' : 'Exit selection',
              onPressed: _exitSelectionMode,
            )
          : null,
        title: _selectionMode
          ? Text(isRu ? 'Выбрано: ${_selectedMangaIds.length}' : 'Selected: ${_selectedMangaIds.length}')
          : _isSearchOpen
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: isRu ? 'Поиск в библиотеке...' : 'Search library...',
                border: InputBorder.none,
                hintStyle: const TextStyle(color: AppTokens.textSecondary),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
            )
          : Text(isRu ? 'Моя библиотека' : 'My Library'),
        actions: _selectionMode
          ? _buildSelectionActions(isRu, selectedEntries, hasSelectedDownloads)
          : [
          IconButton(
            icon: _isSyncingWithMangaLib
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync_rounded),
            tooltip: isRu ? 'Синхронизировать с MangaLib' : 'Sync with MangaLib',
            onPressed: _isSyncingWithMangaLib ? null : () => _syncWithMangaLib(context, isRu),
          ),
          IconButton(
            icon: Icon(_isSearchOpen ? Icons.close_rounded : Icons.search_rounded),
            tooltip: isRu ? 'Поиск' : 'Search',
            onPressed: () {
              setState(() {
                _isSearchOpen = !_isSearchOpen;
                if (!_isSearchOpen) _searchController.clear();
              });
            },
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
            tooltip: isRu ? (_isGridView ? 'Список' : 'Сетка') : (_isGridView ? 'List' : 'Grid'),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          PopupMenuButton<LibrarySortMode>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: isRu ? 'Сортировка' : 'Sort',
            color: AppTokens.surfaceRaised,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: LibrarySortMode.recent,
                child: Row(
                  children: [
                    Icon(
                      _sortMode == LibrarySortMode.recent ? Icons.check_rounded : Icons.access_time_rounded,
                      size: 18,
                      color: _sortMode == LibrarySortMode.recent ? AppTokens.accent : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(isRu ? 'По дате добавления' : 'Date added'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: LibrarySortMode.title,
                child: Row(
                  children: [
                    Icon(
                      _sortMode == LibrarySortMode.title ? Icons.check_rounded : Icons.sort_by_alpha_rounded,
                      size: 18,
                      color: _sortMode == LibrarySortMode.title ? AppTokens.accent : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(isRu ? 'По названию (А-Я)' : 'Title (A-Z)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: LibrarySortMode.rating,
                child: Row(
                  children: [
                    Icon(
                      _sortMode == LibrarySortMode.rating ? Icons.check_rounded : Icons.star_rounded,
                      size: 18,
                      color: _sortMode == LibrarySortMode.rating ? AppTokens.accent : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(isRu ? 'По рейтингу' : 'Rating'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: LibrarySortMode.progress,
                child: Row(
                  children: [
                    Icon(
                      _sortMode == LibrarySortMode.progress ? Icons.check_rounded : Icons.percent_rounded,
                      size: 18,
                      color: _sortMode == LibrarySortMode.progress ? AppTokens.accent : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(isRu ? 'По прогрессу чтения' : 'Reading progress'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: LibrarySortMode.chapters,
                child: Row(
                  children: [
                    Icon(
                      _sortMode == LibrarySortMode.chapters ? Icons.check_rounded : Icons.numbers_rounded,
                      size: 18,
                      color: _sortMode == LibrarySortMode.chapters ? AppTokens.accent : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(isRu ? 'По количеству глав' : 'Total chapters'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: isRu ? 'Статистика чтения' : 'Reading Statistics',
            onPressed: () => context.push('/statistics'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: isRu ? 'Действия' : 'Actions',
            color: AppTokens.surfaceRaised,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (action) {
              if (action == 'new_list') _showCreateListDialog(isRu);
              if (action == 'export') _exportBackup(isRu);
              if (action == 'import') _importBackup(isRu);
              if (action == 'export_mal') _exportMalXml(isRu);
              if (action == 'import_mal') _importMalXml(isRu);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'new_list',
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline_rounded, size: 18, color: AppTokens.accent),
                    const SizedBox(width: 8),
                    Text(isRu ? 'Новый список' : 'New Custom List'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    const Icon(Icons.backup_rounded, size: 18, color: AppTokens.accent),
                    const SizedBox(width: 8),
                    Text(isRu ? 'Экспорт базы (JSON)' : 'Export Backup (JSON)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    const Icon(Icons.restore_rounded, size: 18, color: AppTokens.accent),
                    const SizedBox(width: 8),
                    Text(isRu ? 'Импорт базы (JSON)' : 'Import Backup (JSON)'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'export_mal',
                child: Row(
                  children: [
                    const Icon(Icons.import_export_rounded, size: 18, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Text(isRu ? 'Экспорт в MyAnimeList' : 'Export to MyAnimeList'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import_mal',
                child: Row(
                  children: [
                    const Icon(Icons.download_for_offline_outlined, size: 18, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Text(isRu ? 'Импорт из MyAnimeList' : 'Import from MyAnimeList'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: isRu ? 'Локальный файл CBZ / ZIP' : 'Local CBZ / ZIP',
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
        ],
        bottom: _selectionMode
          ? null
          : TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: AppTokens.accent.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTokens.accent, width: 1),
          ),
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: AppTokens.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          tabs: _categoryTabs.map((tab) {
            final entries = libState.value ?? [];
            final count = tab['type'] == null
              ? entries.length
              : entries.where((e) => e.listType == tab['type']).length;
            final label = isRu ? tab['labelRu'] : tab['labelEn'];
            return Tab(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab['icon'] as IconData, size: 16, color: tab['color'] as Color?),
                    const SizedBox(width: 6),
                    Text('$label ($count)'),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
      body: libState.when(
        data: (allEntries) {
          if (allEntries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bookmarks_outlined, size: 64, color: AppTokens.accent),
                    const SizedBox(height: 16),
                    Text(
                      isRu ? 'Библиотека пуста' : 'Your library is empty',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isRu ? 'Добавляйте тайтлы из каталога или поиска' : 'Add manga from catalog or search',
                      style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
                      onPressed: () => context.go('/search'),
                      icon: const Icon(Icons.search_rounded),
                      label: Text(isRu ? 'Перейти в каталог' : 'Browse Catalog'),
                    ),
                  ],
                ),
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: _categoryTabs.map((tab) {
              final listType = tab['type'] as ListType?;
              final filtered = _filterAndSort(allEntries, listType, _searchController.text);

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      isRu ? 'В этой категории пока ничего нет' : 'No items in this category',
                      style: const TextStyle(color: AppTokens.textSecondary),
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => ref.read(libraryProvider.notifier).loadAll(),
                child: _isGridView
                  ? _buildGridView(filtered, isRu)
                  : _buildListView(filtered, isRu),
              );
            }).toList(),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка загрузки библиотеки: $e')),
      ),
    );
  }

  Widget _buildGridView(List<LibraryEntry> items, bool isRu) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 160).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          // ignore: deprecated_member_use
          cacheExtent: 600.0,
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.65,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final entry = items[i];
            final title = entry.rusName.isNotEmpty ? entry.rusName : entry.name;
            final isSelected = _selectedMangaIds.contains(entry.mangaId.toInt());
            final unreadLabel = _unreadLabel(entry, isRu);

            return Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isSelected ? AppTokens.accent : const Color(0xFF333333),
                  width: isSelected ? 1.8 : 1,
                ),
              ),
              child: InkWell(
                onTap: _selectionMode
                  ? () => _toggleSelection(entry)
                  : () => context.push('/manga/${entry.slugUrl}'),
                onLongPress: _selectionMode
                  ? () => _toggleSelection(entry)
                  : () => _enterSelectionMode(entry),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Cover
                    CachedNetworkImage(
                      imageUrl: entry.coverUrl,
                      memCacheWidth: 320,
                      memCacheHeight: 460,
                      httpHeaders: const {'Referer': 'https://mangalib.org/'},
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppTokens.surfaceCard),
                      errorWidget: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white38),
                    ),
                    // Gradient
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.2),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.92),
                            ],
                            stops: const [0.0, 0.4, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Dim unselected covers while picking a bulk action.
                    if (_selectionMode && !isSelected)
                      Positioned.fill(
                        child: ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
                      ),
                    // Title and Progress Bar
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 3),
                              ],
                            ),
                          ),
                          if (entry.lastReadChapter != null) ...[
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: _calculateProgress(entry),
                                minHeight: 3.5,
                                backgroundColor: const Color(0xFF333333),
                                valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.accent),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Т.${entry.lastReadVolume ?? "1"} Гл.${entry.lastReadChapter}',
                                    style: const TextStyle(color: AppTokens.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_calculateProgress(entry) > 0)
                                  Text(
                                    '${(_calculateProgress(entry) * 100).toInt()}%',
                                    style: const TextStyle(color: AppTokens.accent, fontSize: 9.5, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                          ],
                          if (unreadLabel.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              unreadLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 9.5, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Three-Dots Menu (Top-Right)
                    if (!_selectionMode)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.more_vert_rounded, size: 16, color: Colors.white),
                          ),
                          onPressed: () => _showMangaActionSheet(context, entry, isRu),
                        ),
                      ),
                    // Quick Play Button (Center-Bottom)
                    if (!_selectionMode)
                      Positioned(
                        bottom: 38,
                        right: 8,
                        child: IconButton.filled(
                          onPressed: () => _startReadingEntry(entry),
                          style: IconButton.styleFrom(
                            backgroundColor: AppTokens.accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(34, 34),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        ),
                      ),
                    if (_selectionMode)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: _selectionIndicator(isSelected),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildListView(List<LibraryEntry> items, bool isRu) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      // ignore: deprecated_member_use
      cacheExtent: 600.0,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final entry = items[i];
        final title = entry.rusName.isNotEmpty ? entry.rusName : entry.name;
        final progressVal = _calculateProgress(entry);
        final progressPercent = (progressVal * 100).toInt();
        final isSelected = _selectedMangaIds.contains(entry.mangaId.toInt());
        final unreadLabel = _unreadLabel(entry, isRu);
        final cover = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: entry.coverUrl,
            memCacheWidth: 150,
            memCacheHeight: 210,
            httpHeaders: const {'Referer': 'https://mangalib.org/'},
            width: 50,
            height: 70,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(width: 50, height: 70, color: AppTokens.surfaceRaised),
          ),
        );

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? AppTokens.accent : AppTokens.border,
              width: isSelected ? 1.8 : 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            leading: _selectionMode
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _selectionIndicator(isSelected),
                    const SizedBox(width: 8),
                    cover,
                  ],
                )
              : cover,
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.lastReadChapter != null) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progressVal,
                      minHeight: 3,
                      backgroundColor: AppTokens.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.accent),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Посл. чтение: Том ${entry.lastReadVolume ?? "1"} Гл ${entry.lastReadChapter}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppTokens.textPrimary),
                        ),
                      ),
                      if (entry.totalChapters > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${entry.readChapters}/${entry.totalChapters}',
                          style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
                        ),
                      ],
                      if (progressPercent > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '$progressPercent%',
                          style: const TextStyle(fontSize: 11, color: AppTokens.accent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                ],
                if (unreadLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    unreadLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFFFFB74D), fontWeight: FontWeight.w600),
                  ),
                ],
                Text(
                  _getListTypeName(entry.listType, isRu),
                  style: TextStyle(fontSize: 11, color: _getListTypeColor(entry.listType)),
                ),
              ],
            ),
            trailing: _selectionMode
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      style: IconButton.styleFrom(
                        backgroundColor: AppTokens.accent.withValues(alpha: 0.2),
                        foregroundColor: AppTokens.textPrimary,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      onPressed: () => _startReadingEntry(entry),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      onPressed: () => _showMangaActionSheet(context, entry, isRu),
                    ),
                  ],
                ),
            onTap: _selectionMode
              ? () => _toggleSelection(entry)
              : () async {
                  await context.push('/manga/${entry.slugUrl}');
                  if (mounted) {
                    ref.read(libraryProvider.notifier).loadAll();
                  }
                },
            onLongPress: _selectionMode
              ? () => _toggleSelection(entry)
              : () => _enterSelectionMode(entry),
          ),
        );
      },
    );
  }

  double _calculateProgress(LibraryEntry entry) {
    if (entry.totalChapters > 0) {
      if (entry.readChapters > 0) {
        return (entry.readChapters / entry.totalChapters).clamp(0.0, 1.0);
      }
      final chNum = double.tryParse(entry.lastReadChapter ?? '') ?? 0.0;
      if (chNum > 0) {
        return (chNum / entry.totalChapters).clamp(0.0, 1.0);
      }
    }
    if (entry.lastReadChapter != null) {
      return 0.05;
    }
    return 0.0;
  }

  Future<void> _startReadingEntry(LibraryEntry entry) async {
    if (entry.lastReadChapter != null && entry.lastReadVolume != null) {
      await context.push('/read/${entry.slugUrl}/${entry.lastReadVolume}/${entry.lastReadChapter}');
    } else {
      await context.push('/manga/${entry.slugUrl}');
    }
    if (mounted) {
      ref.read(libraryProvider.notifier).loadAll();
      ref.invalidate(continueReadingProvider);
      ref.read(streakProvider.notifier).loadStreak();
    }
  }

  String _getListTypeName(ListType type, bool isRu) {
    switch (type) {
      case ListType.reading: return isRu ? 'Читаю' : 'Reading';
      case ListType.planToRead: return isRu ? 'В планах' : 'Plan to read';
      case ListType.completed: return isRu ? 'Прочитано' : 'Completed';
      case ListType.favorites: return isRu ? 'Любимое' : 'Favorites';
      case ListType.onHold: return isRu ? 'Отложено' : 'On hold';
      case ListType.dropped: return isRu ? 'Брошено' : 'Dropped';
    }
  }

  Color _getListTypeColor(ListType type) {
    switch (type) {
      case ListType.reading: return const Color(0xFF64B5F6);
      case ListType.planToRead: return const Color(0xFFFFB74D);
      case ListType.completed: return const Color(0xFF81C784);
      case ListType.favorites: return const Color(0xFFF06292);
      case ListType.onHold: return Colors.grey;
      case ListType.dropped: return Colors.redAccent;
    }
  }

  static const List<({String key, String labelRu, String labelEn, IconData icon, Color color})>
      _listTypeOptions = [
    (key: 'reading', labelRu: 'Читаю', labelEn: 'Reading', icon: Icons.auto_stories_rounded, color: Color(0xFF64B5F6)),
    (key: 'plan_to_read', labelRu: 'В планах', labelEn: 'Plan to Read', icon: Icons.bookmark_rounded, color: Color(0xFFFFB74D)),
    (key: 'completed', labelRu: 'Прочитано', labelEn: 'Completed', icon: Icons.check_circle_rounded, color: Color(0xFF81C784)),
    (key: 'on_hold', labelRu: 'Отложено', labelEn: 'On Hold', icon: Icons.pause_circle_outline_rounded, color: Colors.grey),
    (key: 'dropped', labelRu: 'Брошено', labelEn: 'Dropped', icon: Icons.delete_outline_rounded, color: Colors.redAccent),
    (key: 'favorites', labelRu: 'Любимое', labelEn: 'Favorites', icon: Icons.favorite_rounded, color: Color(0xFFF06292)),
  ];

  String _unreadLabel(LibraryEntry entry, bool isRu) {
    final unread = entry.unreadCount.toInt();
    if (unread <= 0) return '';
    return isRu
        ? '${Plural.chapters(unread, 'ru')} не прочитано'
        : '${Plural.chapters(unread, 'en')} unread';
  }

  Widget _selectionIndicator(bool selected) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppTokens.accent : Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.4),
      ),
      child: selected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
    );
  }

  void _enterSelectionMode(LibraryEntry entry) {
    // Refresh the download index so the destructive action is enabled correctly.
    ref.invalidate(downloadedMangaIdsProvider);
    setState(() {
      _selectionMode = true;
      _selectedMangaIds.add(entry.mangaId.toInt());
    });
  }

  void _toggleSelection(LibraryEntry entry) {
    setState(() {
      final id = entry.mangaId.toInt();
      if (_selectedMangaIds.remove(id)) {
        if (_selectedMangaIds.isEmpty) _selectionMode = false;
      } else {
        _selectedMangaIds.add(id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedMangaIds.clear();
    });
  }

  List<LibraryEntry> _selectedEntries() {
    final entries = ref.read(libraryProvider).valueOrNull ?? const <LibraryEntry>[];
    return entries.where((e) => _selectedMangaIds.contains(e.mangaId.toInt())).toList();
  }

  List<Widget> _buildSelectionActions(
    bool isRu,
    List<LibraryEntry> selectedEntries,
    bool hasDownloads,
  ) {
    final hasSelection = selectedEntries.isNotEmpty;
    return [
      IconButton(
        icon: const Icon(Icons.drive_file_move_rounded),
        tooltip: isRu ? 'Переместить в список' : 'Move to list',
        onPressed: hasSelection ? () => _moveSelectedToList(isRu) : null,
      ),
      IconButton(
        icon: const Icon(Icons.delete_sweep_rounded),
        tooltip: isRu ? 'Удалить загрузки' : 'Delete downloads',
        onPressed: hasSelection && hasDownloads ? () => _deleteSelectedDownloads(isRu) : null,
      ),
      IconButton(
        icon: const Icon(Icons.playlist_remove_rounded),
        tooltip: isRu ? 'Убрать из библиотеки' : 'Remove from library',
        onPressed: hasSelection ? () => _removeSelectedFromLibrary(isRu) : null,
      ),
    ];
  }

  Future<String?> _showListTypeSheet(bool isRu) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF222222),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isRu ? 'Переместить в список' : 'Move to list',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              ..._listTypeOptions.map(
                (option) => ListTile(
                  leading: Icon(option.icon, color: option.color),
                  title: Text(isRu ? option.labelRu : option.labelEn),
                  onTap: () => Navigator.pop(ctx, option.key),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmBulkAction({
    required bool isRu,
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceCard,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isRu ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _showBulkSnackBar(String message, {int failed = 0}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: failed > 0 ? const Color(0xFF8E2F2F) : null,
      ),
    );
  }

  Future<void> _moveSelectedToList(bool isRu) async {
    final entries = _selectedEntries();
    if (entries.isEmpty) return;

    final targetListType = await _showListTypeSheet(isRu);
    if (targetListType == null || !mounted) return;

    var moved = 0;
    var failed = 0;
    for (final entry in entries) {
      try {
        await rust_storage.removeFromList(
          mangaId: entry.mangaId,
          listType: listTypeToStorageKey(entry.listType),
        );
        await rust_storage.addToList(mangaId: entry.mangaId, listType: targetListType);
        moved++;
      } catch (_) {
        failed++;
      }
    }

    await ref.read(libraryProvider.notifier).loadAll();
    if (!mounted) return;
    _exitSelectionMode();
    _showBulkSnackBar(
      failed == 0
          ? (isRu ? 'Перемещено тайтлов: $moved' : 'Titles moved: $moved')
          : (isRu ? 'Перемещено: $moved, ошибок: $failed' : 'Moved: $moved, failed: $failed'),
      failed: failed,
    );
  }

  Future<void> _deleteSelectedDownloads(bool isRu) async {
    final entries = _selectedEntries();
    if (entries.isEmpty) return;

    final confirmed = await _confirmBulkAction(
      isRu: isRu,
      title: isRu ? 'Удалить загрузки?' : 'Delete downloads?',
      message: isRu
          ? 'Скачанные главы выбранных тайтлов (${entries.length}) будут удалены с устройства.'
          : 'Downloaded chapters of the selected titles (${entries.length}) will be deleted from this device.',
      confirmLabel: isRu ? 'Удалить' : 'Delete',
    );
    if (confirmed != true || !mounted) return;

    var deleted = 0;
    var failed = 0;
    for (final entry in entries) {
      try {
        await rust_storage.deleteDownloadedManga(mangaId: entry.mangaId);
        deleted++;
      } catch (_) {
        failed++;
      }
    }

    ref.invalidate(downloadedMangaIdsProvider);
    if (!mounted) return;
    _exitSelectionMode();
    _showBulkSnackBar(
      failed == 0
          ? (isRu ? 'Загрузки удалены у тайтлов: $deleted' : 'Downloads deleted for titles: $deleted')
          : (isRu ? 'Удалено: $deleted, ошибок: $failed' : 'Deleted: $deleted, failed: $failed'),
      failed: failed,
    );
  }

  Future<void> _removeSelectedFromLibrary(bool isRu) async {
    final entries = _selectedEntries();
    if (entries.isEmpty) return;

    final confirmed = await _confirmBulkAction(
      isRu: isRu,
      title: isRu ? 'Убрать из библиотеки?' : 'Remove from library?',
      message: isRu
          ? 'Выбранные тайтлы (${entries.length}) будут убраны из библиотеки. Скачанные главы останутся на устройстве.'
          : 'The selected titles (${entries.length}) will be removed from your library. Downloaded chapters stay on this device.',
      confirmLabel: isRu ? 'Убрать' : 'Remove',
    );
    if (confirmed != true || !mounted) return;

    var removed = 0;
    var failed = 0;
    for (final entry in entries) {
      try {
        await rust_storage.removeFromList(
          mangaId: entry.mangaId,
          listType: listTypeToStorageKey(entry.listType),
        );
        removed++;
      } catch (_) {
        failed++;
      }
    }

    await ref.read(libraryProvider.notifier).loadAll();
    if (!mounted) return;
    _exitSelectionMode();
    _showBulkSnackBar(
      failed == 0
          ? (isRu ? 'Убрано из библиотеки: $removed' : 'Removed from library: $removed')
          : (isRu ? 'Убрано: $removed, ошибок: $failed' : 'Removed: $removed, failed: $failed'),
      failed: failed,
    );
  }

  void _showMangaActionSheet(BuildContext context, LibraryEntry entry, bool isRu) {
    final title = entry.rusName.isNotEmpty ? entry.rusName : entry.name;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Divider(height: 16),

              // Open Details
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: AppTokens.textPrimary),
                title: Text(isRu ? 'Открыть страницу тайтла' : 'View manga details'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/manga/${entry.slugUrl}');
                },
              ),

              // Change Category Submenu
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded, color: AppTokens.accent),
                title: Text(isRu ? 'Сменить категорию / статус' : 'Move to another category'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showChangeCategoryDialog(context, entry, isRu);
                },
              ),

              // Remove from Library
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: Text(isRu ? 'Удалить из библиотеки' : 'Remove from library', style: const TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref.read(libraryProvider.notifier).removeFromList(entry.mangaId.toInt(), 'all');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isRu ? 'Тайтл удалён из библиотеки' : 'Removed from library')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangeCategoryDialog(BuildContext context, LibraryEntry entry, bool isRu) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppTokens.surfaceRaised,
        title: Text(isRu ? 'Выберите категорию' : 'Select Category'),
        children: [
          _buildCategoryOption(ctx, entry, 'reading', isRu ? 'Читаю' : 'Reading', Icons.auto_stories_rounded, const Color(0xFF64B5F6)),
          _buildCategoryOption(ctx, entry, 'plan_to_read', isRu ? 'В планах' : 'Plan to Read', Icons.bookmark_rounded, const Color(0xFFFFB74D)),
          _buildCategoryOption(ctx, entry, 'completed', isRu ? 'Прочитано' : 'Completed', Icons.check_circle_rounded, const Color(0xFF81C784)),
          _buildCategoryOption(ctx, entry, 'favorites', isRu ? 'Любимое' : 'Favorites', Icons.favorite_rounded, const Color(0xFFF06292)),
          _buildCategoryOption(ctx, entry, 'on_hold', isRu ? 'Отложено' : 'On Hold', Icons.pause_circle_outline_rounded, Colors.grey),
          _buildCategoryOption(ctx, entry, 'dropped', isRu ? 'Брошено' : 'Dropped', Icons.delete_outline_rounded, Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildCategoryOption(BuildContext ctx, LibraryEntry entry, String listTypeStr, String label, IconData icon, Color color) {
    return SimpleDialogOption(
      onPressed: () async {
        Navigator.pop(ctx);
        await ref.read(libraryProvider.notifier).addToList(entry.mangaId.toInt(), listTypeStr);
      },
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
