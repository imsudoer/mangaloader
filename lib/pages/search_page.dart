import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/search_provider.dart';
import 'package:mangaloader/providers/manga_provider.dart';
import 'package:mangaloader/widgets/manga_card.dart';
import 'package:mangaloader/widgets/collection_card.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/providers/settings_provider.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedTab = 0; // 0: Catalog, 1: Collections
  final List<MangaCollectionItem> _collections = [];
  bool _isLoadingCollections = false;
  String? _collectionsError;

  final List<Map<String, dynamic>> _sortOptions = [
    {'id': 'views', 'labelRu': 'Популярность', 'labelEn': 'Popularity'},
    {'id': 'rate_avg', 'labelRu': 'Рейтинг', 'labelEn': 'Rating'},
    {'id': 'created_at', 'labelRu': 'Новинки', 'labelEn': 'Newest'},
    {'id': 'chap_count', 'labelRu': 'По главам', 'labelEn': 'Chapters'},
    {'id': 'releaseDate', 'labelRu': 'По году', 'labelEn': 'Release Year'},
    {'id': 'name', 'labelRu': 'По имени (А-Я)', 'labelEn': 'Alphabetical'},
  ];

  final List<Map<String, dynamic>> _typeOptions = [
    {'id': 0, 'labelRu': 'Все', 'labelEn': 'All', 'typeId': null},
    {'id': 1, 'labelRu': 'Манга', 'labelEn': 'Manga', 'typeId': 1},
    {'id': 5, 'labelRu': 'Манхва', 'labelEn': 'Manhwa', 'typeId': 5},
    {'id': 6, 'labelRu': 'Маньхуа', 'labelEn': 'Manhua', 'typeId': 6},
    {'id': 8, 'labelRu': 'Руманга', 'labelEn': 'Rumanga', 'typeId': 8},
    {'id': 9, 'labelRu': 'Комикс', 'labelEn': 'Comic', 'typeId': 9},
    {'id': 3, 'labelRu': 'Сингл', 'labelEn': 'Single', 'typeId': 3},
  ];

  final List<Map<String, dynamic>> _statusOptions = [
    {'id': 0, 'labelRu': 'Все', 'labelEn': 'All', 'statusId': null},
    {'id': 1, 'labelRu': 'Онгоинг', 'labelEn': 'Ongoing', 'statusId': 1},
    {'id': 2, 'labelRu': 'Завершён', 'labelEn': 'Completed', 'statusId': 2},
    {'id': 3, 'labelRu': 'Анонс', 'labelEn': 'Announced', 'statusId': 3},
    {'id': 4, 'labelRu': 'Приостановлен', 'labelEn': 'On Hold', 'statusId': 4},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCollections({bool refresh = false}) async {
    if (_collections.isNotEmpty && !_isLoadingCollections && !refresh) return;
    setState(() {
      _isLoadingCollections = true;
      _collectionsError = null;
    });

    try {
      final items = await rust_api.getCollections(page: 1, sortBy: 'popularity');
      if (mounted) {
        setState(() {
          if (refresh) _collections.clear();
          _collections.addAll(items);
          _isLoadingCollections = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _collectionsError = e.toString();
          _isLoadingCollections = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final filter = ref.watch(catalogFilterProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final activeCount = filter.activeFiltersCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(isRu ? 'Каталог и поиск' : 'Catalog & Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link_rounded),
            tooltip: isRu ? 'Вставить ссылку' : 'Paste Link',
            onPressed: () => _showPasteLinkDialog(context, isRu),
          ),
        ],
      ),
      body: Column(
        children: [
          // Section Switcher (Catalog / Collections)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SegmentedButton<int>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: const Color(0xFF8A897C),
                selectedForegroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text(isRu ? 'Каталог' : 'Catalog'),
                  icon: const Icon(Icons.grid_view_rounded, size: 16),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(isRu ? 'Коллекции' : 'Collections'),
                  icon: const Icon(Icons.collections_bookmark_rounded, size: 16),
                ),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (val) {
                setState(() => _selectedTab = val.first);
                if (val.first == 1) {
                  _loadCollections();
                }
              },
            ),
          ),

          if (_selectedTab == 0) ...[
            // Search Input Bar with Filter Button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: isRu ? 'Поиск по названию или автору...' : 'Search by title or author...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(searchProvider.notifier).search('');
                                setState(() {});
                              },
                            )
                          : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: const Color(0xFF2C2C2C),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          ref.read(searchHistoryProvider.notifier).addQuery(val);
                        }
                      },
                      onChanged: (val) {
                        setState(() {});
                        ref.read(searchProvider.notifier).search(val);
                      },
                    ),
                  ),
                const SizedBox(width: 8),
                // Filter Modal Opener Button
                Badge(
                  isLabelVisible: activeCount > 0,
                  label: Text('$activeCount', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  backgroundColor: const Color(0xFF8A897C),
                  textColor: Colors.white,
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: activeCount > 0
                        ? const Color(0xFF8A897C).withValues(alpha: 0.3)
                        : const Color(0xFF2C2C2C),
                      foregroundColor: activeCount > 0 ? Colors.white : const Color(0xFFD2D7DF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: activeCount > 0 ? const Color(0xFF8A897C) : const Color(0xFF3E3E3E),
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                    ),
                    tooltip: isRu ? 'Расширенные фильтры' : 'Advanced Filters',
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    onPressed: () => _showFilterBottomSheet(context, isRu),
                  ),
                ),
              ],
            ),
          ),

          // Search History Chips (visible when search bar has no text)
          Builder(
            builder: (context) {
              final history = ref.watch(searchHistoryProvider);
              if (history.isEmpty || _searchController.text.isNotEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                height: 34,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.history_rounded, size: 16, color: Color(0xFF8A897C)),
                    ),
                    ...history.map((h) => Container(
                      margin: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        label: Text(h, style: const TextStyle(fontSize: 11, color: Color(0xFFD2D7DF))),
                        backgroundColor: const Color(0xFF2C2C2C),
                        side: const BorderSide(color: Color(0xFF383838)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _searchController.text = h;
                          ref.read(searchProvider.notifier).search(h);
                          ref.read(searchHistoryProvider.notifier).addQuery(h);
                          setState(() {});
                        },
                        onDeleted: () => ref.read(searchHistoryProvider.notifier).removeQuery(h),
                        deleteIconColor: const Color(0xFFBDBBB0),
                      ),
                    )),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: Color(0xFFBDBBB0)),
                      tooltip: isRu ? 'Очистить историю' : 'Clear history',
                      onPressed: () => ref.read(searchHistoryProvider.notifier).clearAll(),
                    ),
                  ],
                ),
              );
            },
          ),

          // Horizontal Sort and Quick Type Filter Bar (shown when not searching by text)
          if (_searchController.text.isEmpty) ...[
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Sort Dropdown Menu
                  PopupMenuButton<String>(
                    initialValue: filter.sortBy,
                    tooltip: isRu ? 'Сортировка' : 'Sort',
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: const Color(0xFF2C2C2C),
                    onSelected: (val) {
                      ref.read(searchProvider.notifier).updateFilter(filter.copyWith(sortBy: val));
                    },
                    itemBuilder: (ctx) => _sortOptions.map((opt) {
                      final isSel = filter.sortBy == opt['id'];
                      return PopupMenuItem<String>(
                        value: opt['id'] as String,
                        child: Row(
                          children: [
                            Icon(
                              isSel ? Icons.check_circle_rounded : Icons.circle_outlined,
                              size: 16,
                              color: isSel ? const Color(0xFF8A897C) : const Color(0xFFBDBBB0),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isRu ? opt['labelRu'] as String : opt['labelEn'] as String,
                              style: TextStyle(
                                color: isSel ? Colors.white : const Color(0xFFD2D7DF),
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF353535),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF8A897C).withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sort_rounded, size: 16, color: Color(0xFFD2D7DF)),
                          const SizedBox(width: 6),
                          Text(
                            _sortOptions.firstWhere((e) => e['id'] == filter.sortBy, orElse: () => _sortOptions.first)[isRu ? 'labelRu' : 'labelEn'] as String,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Color(0xFFD2D7DF)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Quick Type Chips
                  ..._typeOptions.map((opt) {
                    final tid = opt['typeId'] as int?;
                    final isSelected = (tid == null && filter.typeIds.isEmpty) || (tid != null && filter.typeIds.contains(tid));
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(isRu ? opt['labelRu'] as String : opt['labelEn'] as String),
                        selected: isSelected,
                        selectedColor: const Color(0xFF8A897C),
                        backgroundColor: const Color(0xFF2C2C2C),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : const Color(0xFFD2D7DF),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF8A897C) : const Color(0xFF3E3E3E),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        onSelected: (_) {
                          List<int> newTypes;
                          if (tid == null) {
                            newTypes = [];
                          } else {
                            newTypes = [tid];
                          }
                          ref.read(searchProvider.notifier).updateFilter(filter.copyWith(typeIds: newTypes));
                        },
                      ),
                    );
                  }),

                  const VerticalDivider(width: 12, indent: 6, endIndent: 6, color: Color(0xFF3E3E3E)),

                  // Quick Status Chips
                  ..._statusOptions.map((opt) {
                    final sid = opt['statusId'] as int?;
                    final isSelected = (sid == null && filter.statusIds.isEmpty) || (sid != null && filter.statusIds.contains(sid));
                    final label = isRu ? opt['labelRu'] as String : opt['labelEn'] as String;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        selectedColor: const Color(0xFF8A897C),
                        backgroundColor: const Color(0xFF2C2C2C),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : const Color(0xFFD2D7DF),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF8A897C) : const Color(0xFF3E3E3E),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        onSelected: (_) {
                          List<int> newStatuses;
                          if (sid == null) {
                            newStatuses = [];
                          } else {
                            newStatuses = [sid];
                          }
                          ref.read(searchProvider.notifier).updateFilter(filter.copyWith(statusIds: newStatuses));
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Results Grid
          Expanded(
            child: searchState.when(
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off_rounded, size: 56, color: Color(0xFF8A897C)),
                          const SizedBox(height: 16),
                          Text(
                            isRu ? 'Ничего не найдено' : 'No manga found',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isRu ? 'Попробуйте изменить поисковый запрос или фильтры' : 'Try adjusting your search query or filters',
                            style: const TextStyle(color: Color(0xFFBDBBB0), fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          if (activeCount > 0) ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () {
                                ref.read(searchProvider.notifier).updateFilter(const CatalogFilter());
                              },
                              icon: const Icon(Icons.clear_all_rounded),
                              label: Text(isRu ? 'Сбросить все фильтры' : 'Reset all filters'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = (constraints.maxWidth / 160).floor().clamp(2, 6);
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final manga = items[index];
                        return MangaCard(
                          manga: manga,
                          onTap: () => context.push('/manga/${manga.slugUrl}'),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(isRu ? 'Ошибка загрузки: $err' : 'Loading error: $err', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => ref.read(searchProvider.notifier).loadCatalog(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(isRu ? 'Повторить' : 'Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ] else ...[
            // Collections Tab View
            Expanded(
              child: _isLoadingCollections
                ? const Center(child: CircularProgressIndicator())
                : _collectionsError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(isRu ? 'Ошибка загрузки коллекций: $_collectionsError' : 'Error loading collections: $_collectionsError', textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => _loadCollections(refresh: true),
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(isRu ? 'Повторить' : 'Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _collections.isEmpty
                    ? Center(
                        child: Text(
                          isRu ? 'Коллекции не найдены' : 'No collections found',
                          style: const TextStyle(color: Color(0xFF888888)),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadCollections(refresh: true),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount = constraints.maxWidth > 700 ? 3 : (constraints.maxWidth > 400 ? 2 : 1);
                            return GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: 1.35,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: _collections.length,
                              itemBuilder: (context, index) {
                                return CollectionCard(collection: _collections[index]);
                              },
                            );
                          },
                        ),
                      ),
            ),
          ],
        ],
      ),
    );
  }

  void _showPasteLinkDialog(BuildContext context, bool isRu) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(isRu ? 'Вставить ссылку' : 'Paste Link'),
        content: TextField(
          decoration: const InputDecoration(hintText: 'https://mangalib.me/...'),
          onSubmitted: (val) {
            Navigator.pop(ctx);
            final parsedUrl = rust_api.parseMangaUrl(url: val);
            if (parsedUrl != null) {
              context.push('/manga/$parsedUrl');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(isRu ? 'Неверная ссылка' : 'Invalid link')),
              );
            }
          },
        ),
      ),
    );
  }

  void _showFilterBottomSheet(BuildContext context, bool isRu) {
    final currentFilter = ref.read(catalogFilterProvider);
    final constantsAsync = ref.read(mangaConstantsProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return _FilterBottomSheetContent(
          initialFilter: currentFilter,
          constantsAsync: constantsAsync,
          isRu: isRu,
          onApply: (newFilter) {
            ref.read(searchProvider.notifier).updateFilter(newFilter);
          },
        );
      },
    );
  }
}

class _FilterBottomSheetContent extends StatefulWidget {
  final CatalogFilter initialFilter;
  final AsyncValue<MangaConstants> constantsAsync;
  final bool isRu;
  final ValueChanged<CatalogFilter> onApply;

  const _FilterBottomSheetContent({
    required this.initialFilter,
    required this.constantsAsync,
    required this.isRu,
    required this.onApply,
  });

  @override
  State<_FilterBottomSheetContent> createState() => _FilterBottomSheetContentState();
}

class _FilterBottomSheetContentState extends State<_FilterBottomSheetContent> {
  late String _sortBy;
  late List<int> _typeIds;
  late List<int> _statusIds;
  late List<int> _genreIds;
  late List<int> _excludedGenreIds;
  late List<int> _tagIds;
  late List<int> _excludedTagIds;
  late List<int> _ageIds;
  late List<int> _formatIds;
  late List<int> _scanlateIds;

  String _genreSearch = '';
  String _tagSearch = '';

  @override
  void initState() {
    super.initState();
    _sortBy = widget.initialFilter.sortBy;
    _typeIds = List.from(widget.initialFilter.typeIds);
    _statusIds = List.from(widget.initialFilter.statusIds);
    _genreIds = List.from(widget.initialFilter.genreIds);
    _excludedGenreIds = List.from(widget.initialFilter.excludedGenreIds);
    _tagIds = List.from(widget.initialFilter.tagIds);
    _excludedTagIds = List.from(widget.initialFilter.excludedTagIds);
    _ageIds = List.from(widget.initialFilter.ageIds);
    _formatIds = List.from(widget.initialFilter.formatIds);
    _scanlateIds = List.from(widget.initialFilter.scanlateIds);
  }

  void _toggleId(List<int> list, int id) {
    setState(() {
      if (list.contains(id)) {
        list.remove(id);
      } else {
        list.add(id);
      }
    });
  }

  void _resetAll() {
    setState(() {
      _sortBy = 'views';
      _typeIds.clear();
      _statusIds.clear();
      _genreIds.clear();
      _excludedGenreIds.clear();
      _tagIds.clear();
      _excludedTagIds.clear();
      _ageIds.clear();
      _formatIds.clear();
      _scanlateIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRu = widget.isRu;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF8A897C),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isRu ? 'Расширенный поиск' : 'Advanced Filters',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  TextButton.icon(
                    onPressed: _resetAll,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(isRu ? 'Сбросить' : 'Reset'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF353535)),

            // Content List
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. Sort Options
                  _buildSectionTitle(isRu ? 'Сортировка' : 'Sort By'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildRadioChip('views', isRu ? 'По популярности' : 'Popularity'),
                      _buildRadioChip('rate_avg', isRu ? 'По рейтингу' : 'Rating'),
                      _buildRadioChip('created_at', isRu ? 'Новинки' : 'Newest'),
                      _buildRadioChip('chap_count', isRu ? 'По главам' : 'Chapters'),
                      _buildRadioChip('releaseDate', isRu ? 'По году' : 'Release Year'),
                      _buildRadioChip('name', isRu ? 'По алфавиту' : 'Alphabetical'),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 2. Types & Formats
                  widget.constantsAsync.when(
                    data: (constants) {
                      final filteredGenres = constants.genres.where((g) {
                        if (_genreSearch.isEmpty) return true;
                        return g.name.toLowerCase().contains(_genreSearch.toLowerCase());
                      }).toList();

                      final filteredTags = constants.tags.where((t) {
                        if (_tagSearch.isEmpty) return true;
                        return t.name.toLowerCase().contains(_tagSearch.toLowerCase());
                      }).toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Types
                          if (constants.types.isNotEmpty) ...[
                            _buildSectionTitle(isRu ? 'Тип произведения' : 'Manga Type'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: constants.types.map((t) => _buildFilterChip(t.name, _typeIds.contains(t.id), () => _toggleId(_typeIds, t.id))).toList(),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Statuses
                          if (constants.statuses.isNotEmpty) ...[
                            _buildSectionTitle(isRu ? 'Статус тайтла' : 'Title Status'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: constants.statuses.map((s) => _buildFilterChip(s.name, _statusIds.contains(s.id), () => _toggleId(_statusIds, s.id))).toList(),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Scanlate Statuses
                          if (constants.scanlateStatuses.isNotEmpty) ...[
                            _buildSectionTitle(isRu ? 'Статус перевода' : 'Translation Status'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: constants.scanlateStatuses.map((s) => _buildFilterChip(s.name, _scanlateIds.contains(s.id), () => _toggleId(_scanlateIds, s.id))).toList(),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Age Restrictions
                          if (constants.ageRestrictions.isNotEmpty) ...[
                            _buildSectionTitle(isRu ? 'Возрастной рейтинг' : 'Age Rating'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: constants.ageRestrictions.map((a) => _buildFilterChip(a.name, _ageIds.contains(a.id), () => _toggleId(_ageIds, a.id))).toList(),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Formats
                          if (constants.formats.isNotEmpty) ...[
                            _buildSectionTitle(isRu ? 'Формат выпуска' : 'Release Format'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: constants.formats.map((f) => _buildFilterChip(f.name, _formatIds.contains(f.id), () => _toggleId(_formatIds, f.id))).toList(),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Genres with search
                          _buildSectionTitle(isRu ? 'Включить жанры (${_genreIds.length} выбр.)' : 'Include Genres (${_genreIds.length} sel.)'),
                          TextField(
                            decoration: InputDecoration(
                              hintText: isRu ? 'Поиск жанров...' : 'Search genres...',
                              prefixIcon: const Icon(Icons.search_rounded, size: 16),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: const Color(0xFF2C2C2C),
                            ),
                            onChanged: (v) => setState(() => _genreSearch = v),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: filteredGenres.map((g) => _buildFilterChip(g.name, _genreIds.contains(g.id), () {
                              _excludedGenreIds.remove(g.id);
                              _toggleId(_genreIds, g.id);
                            })).toList(),
                          ),
                          const SizedBox(height: 16),

                          // Exclude Genres
                          _buildSectionTitle(isRu ? 'Исключить жанры (${_excludedGenreIds.length} искл.)' : 'Exclude Genres (${_excludedGenreIds.length} excl.)'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: filteredGenres.map((g) => _buildExcludeFilterChip(g.name, _excludedGenreIds.contains(g.id), () {
                              _genreIds.remove(g.id);
                              _toggleId(_excludedGenreIds, g.id);
                            })).toList(),
                          ),
                          const SizedBox(height: 20),

                          // Tags with search
                          _buildSectionTitle(isRu ? 'Теги (${_tagIds.length} выбр.)' : 'Tags (${_tagIds.length} sel.)'),
                          TextField(
                            decoration: InputDecoration(
                              hintText: isRu ? 'Поиск тегов...' : 'Search tags...',
                              prefixIcon: const Icon(Icons.search_rounded, size: 16),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: const Color(0xFF2C2C2C),
                            ),
                            onChanged: (v) => setState(() => _tagSearch = v),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: filteredTags.map((t) => _buildFilterChip(t.name, _tagIds.contains(t.id), () => _toggleId(_tagIds, t.id))).toList(),
                          ),
                        ],
                      );
                    },
                    loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
                    error: (e, _) => Text('Ошибка загрузки фильтров: $e', style: const TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),

            // Bottom Action Bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8A897C),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final newFilter = CatalogFilter(
                      sortBy: _sortBy,
                      typeIds: _typeIds,
                      statusIds: _statusIds,
                      genreIds: _genreIds,
                      excludedGenreIds: _excludedGenreIds,
                      tagIds: _tagIds,
                      excludedTagIds: _excludedTagIds,
                      ageIds: _ageIds,
                      formatIds: _formatIds,
                      scanlateIds: _scanlateIds,
                    );
                    widget.onApply(newFilter);
                    Navigator.pop(context);
                  },
                  child: Text(
                    isRu ? 'Применить фильтры' : 'Apply Filters',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFD2D7DF)),
      ),
    );
  }

  Widget _buildRadioChip(String id, String label) {
    final isSelected = _sortBy == id;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF8A897C),
      backgroundColor: const Color(0xFF2C2C2C),
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSelected ? Colors.white : const Color(0xFFD2D7DF),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFF8A897C) : const Color(0xFF3E3E3E),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
      onSelected: (_) => setState(() => _sortBy = id),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF8A897C),
      backgroundColor: const Color(0xFF2C2C2C),
      labelStyle: TextStyle(
        fontSize: 11,
        color: isSelected ? Colors.white : const Color(0xFFD2D7DF),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFF8A897C) : const Color(0xFF3E3E3E),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }

  Widget _buildExcludeFilterChip(String label, bool isExcluded, VoidCallback onTap) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          decoration: isExcluded ? TextDecoration.lineThrough : null,
          color: isExcluded ? Colors.redAccent : const Color(0xFFD2D7DF),
          fontWeight: isExcluded ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isExcluded,
      selectedColor: Colors.red.shade900.withValues(alpha: 0.35),
      backgroundColor: const Color(0xFF2C2C2C),
      side: BorderSide(
        color: isExcluded ? Colors.redAccent : const Color(0xFF3E3E3E),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }
}
