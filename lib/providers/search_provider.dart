import 'dart:async';
import 'dart:convert';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/services/content_filter.dart';

class CatalogFilter {
  /// Settings key holding the JSON encoded filter between launches.
  static const String storageKey = 'catalog_filter';

  /// Sort ids accepted by the catalog endpoint; anything else is discarded on
  /// restore so a stale payload cannot poison the request.
  static const Set<String> sortValues = {
    'views',
    'rate_avg',
    'created_at',
    'chap_count',
    'releaseDate',
    'name',
  };

  final String sortBy;
  final List<int> typeIds;
  final List<int> statusIds;
  final List<int> genreIds;
  final List<int> excludedGenreIds;
  final List<int> tagIds;
  final List<int> excludedTagIds;
  final List<int> ageIds;
  final List<int> formatIds;
  final List<int> scanlateIds;

  const CatalogFilter({
    this.sortBy = 'views',
    this.typeIds = const [],
    this.statusIds = const [],
    this.genreIds = const [],
    this.excludedGenreIds = const [],
    this.tagIds = const [],
    this.excludedTagIds = const [],
    this.ageIds = const [],
    this.formatIds = const [],
    this.scanlateIds = const [],
  });

  int get activeFiltersCount {
    int count = 0;
    if (typeIds.isNotEmpty) count++;
    if (statusIds.isNotEmpty) count++;
    if (genreIds.isNotEmpty) count += genreIds.length;
    if (excludedGenreIds.isNotEmpty) count += excludedGenreIds.length;
    if (tagIds.isNotEmpty) count += tagIds.length;
    if (excludedTagIds.isNotEmpty) count += excludedTagIds.length;
    if (ageIds.isNotEmpty) count++;
    if (formatIds.isNotEmpty) count += formatIds.length;
    if (scanlateIds.isNotEmpty) count++;
    return count;
  }

  CatalogFilter copyWith({
    String? sortBy,
    List<int>? typeIds,
    List<int>? statusIds,
    List<int>? genreIds,
    List<int>? excludedGenreIds,
    List<int>? tagIds,
    List<int>? excludedTagIds,
    List<int>? ageIds,
    List<int>? formatIds,
    List<int>? scanlateIds,
  }) {
    return CatalogFilter(
      sortBy: sortBy ?? this.sortBy,
      typeIds: typeIds ?? this.typeIds,
      statusIds: statusIds ?? this.statusIds,
      genreIds: genreIds ?? this.genreIds,
      excludedGenreIds: excludedGenreIds ?? this.excludedGenreIds,
      tagIds: tagIds ?? this.tagIds,
      excludedTagIds: excludedTagIds ?? this.excludedTagIds,
      ageIds: ageIds ?? this.ageIds,
      formatIds: formatIds ?? this.formatIds,
      scanlateIds: scanlateIds ?? this.scanlateIds,
    );
  }

  /// True when nothing but sort state is at its default, so callers can drop
  /// the stored payload instead of keeping an empty one around.
  bool get isDefault =>
      sortBy == 'views' &&
      typeIds.isEmpty &&
      statusIds.isEmpty &&
      genreIds.isEmpty &&
      excludedGenreIds.isEmpty &&
      tagIds.isEmpty &&
      excludedTagIds.isEmpty &&
      ageIds.isEmpty &&
      formatIds.isEmpty &&
      scanlateIds.isEmpty;

  Map<String, dynamic> toJson() => {
        'sortBy': sortBy,
        'typeIds': typeIds,
        'statusIds': statusIds,
        'genreIds': genreIds,
        'excludedGenreIds': excludedGenreIds,
        'tagIds': tagIds,
        'excludedTagIds': excludedTagIds,
        'ageIds': ageIds,
        'formatIds': formatIds,
        'scanlateIds': scanlateIds,
      };

  factory CatalogFilter.fromJson(Map<String, dynamic> json) {
    List<int> readIds(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      final ids = <int>{};
      for (final value in raw) {
        final id = switch (value) {
          int v => v,
          num v => v.toInt(),
          String v => int.tryParse(v),
          _ => null,
        };
        if (id != null && id > 0) ids.add(id);
      }
      return ids.toList(growable: false);
    }

    final rawSort = json['sortBy'];
    return CatalogFilter(
      sortBy: rawSort is String && sortValues.contains(rawSort) ? rawSort : 'views',
      typeIds: readIds('typeIds'),
      statusIds: readIds('statusIds'),
      genreIds: readIds('genreIds'),
      excludedGenreIds: readIds('excludedGenreIds'),
      tagIds: readIds('tagIds'),
      excludedTagIds: readIds('excludedTagIds'),
      ageIds: readIds('ageIds'),
      formatIds: readIds('formatIds'),
      scanlateIds: readIds('scanlateIds'),
    );
  }
}

/// Result of a catalog/search request together with its pagination state.
class CatalogState {
  final List<MangaSearchResult> items;
  final int page;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isTextSearch;

  const CatalogState({
    required this.items,
    this.page = 1,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isTextSearch = false,
  });

  CatalogState copyWith({
    List<MangaSearchResult>? items,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isTextSearch,
  }) {
    return CatalogState(
      items: items ?? this.items,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isTextSearch: isTextSearch ?? this.isTextSearch,
    );
  }
}

final catalogFilterProvider = StateProvider<CatalogFilter>((ref) => const CatalogFilter());

final searchProvider =
    StateNotifierProvider<SearchNotifier, AsyncValue<CatalogState>>((ref) {
  final notifier = SearchNotifier(ref);
  notifier.init();
  return notifier;
});

class SearchNotifier extends StateNotifier<AsyncValue<CatalogState>> {
  final Ref _ref;
  Timer? _debounce;
  String _currentQuery = '';
  int _requestId = 0;

  SearchNotifier(this._ref) : super(const AsyncValue.loading());

  /// A catalog page is considered to have more results while the API keeps
  /// returning a full page.
  static const int _pageThreshold = 20;

  void init() {
    unawaited(_initFromStorage());
  }

  /// Restores the last used filter set before the first catalog request so the
  /// grid does not flash the default feed and then reload.
  Future<void> _initFromStorage() async {
    try {
      final raw = await rust_storage.getSetting(key: CatalogFilter.storageKey);
      if (!mounted) return;
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _ref.read(catalogFilterProvider.notifier).state =
              CatalogFilter.fromJson(decoded.cast<String, dynamic>());
        }
      }
    } catch (_) {
      // A corrupt or outdated payload must never keep the catalog from loading.
    }
    if (!mounted) return;
    // A query typed while the settings read was in flight owns the grid now.
    if (_currentQuery.isEmpty) {
      await loadCatalog();
    }
  }

  Future<void> loadCatalog({int page = 1}) async {
    final filter = _ref.read(catalogFilterProvider);
    final requestId = ++_requestId;
    state = const AsyncValue.loading();
    try {
      final results = await rust_api.getCatalog(
        page: page,
        sortBy: filter.sortBy,
        typeIds: Int64List.fromList(filter.typeIds),
        statusIds: Int64List.fromList(filter.statusIds),
        genreIds: Int64List.fromList(filter.genreIds),
        excludedGenreIds: Int64List.fromList(filter.excludedGenreIds),
        tagIds: Int64List.fromList(filter.tagIds),
        excludedTagIds: Int64List.fromList(filter.excludedTagIds),
        ageIds: Int64List.fromList(filter.ageIds),
        formatIds: Int64List.fromList(filter.formatIds),
        scanlateIds: Int64List.fromList(filter.scanlateIds),
      );
      if (!mounted || requestId != _requestId) return;
      state = AsyncValue.data(CatalogState(
        items: ContentFilter.filterSearchResults(results),
        page: page,
        hasMore: results.length >= _pageThreshold,
      ));
    } catch (e, st) {
      if (!mounted || requestId != _requestId) return;
      state = AsyncValue.error(e, st);
    }
  }

  /// Appends the next catalog page. Text searches are single-shot because the API
  /// does not paginate them.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    final requestId = _requestId;
    final nextPage = current.page + 1;
    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final filter = _ref.read(catalogFilterProvider);
      final results = await rust_api.getCatalog(
        page: nextPage,
        sortBy: filter.sortBy,
        typeIds: Int64List.fromList(filter.typeIds),
        statusIds: Int64List.fromList(filter.statusIds),
        genreIds: Int64List.fromList(filter.genreIds),
        excludedGenreIds: Int64List.fromList(filter.excludedGenreIds),
        tagIds: Int64List.fromList(filter.tagIds),
        excludedTagIds: Int64List.fromList(filter.excludedTagIds),
        ageIds: Int64List.fromList(filter.ageIds),
        formatIds: Int64List.fromList(filter.formatIds),
        scanlateIds: Int64List.fromList(filter.scanlateIds),
      );
      if (!mounted || requestId != _requestId) return;

      final known = current.items.map((m) => m.id).toSet();
      final fresh = ContentFilter.filterSearchResults(results)
          .where((m) => known.add(m.id))
          .toList();

      state = AsyncValue.data(current.copyWith(
        items: [...current.items, ...fresh],
        page: nextPage,
        hasMore: results.length >= _pageThreshold,
        isLoadingMore: false,
      ));
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      // Keep the already loaded results; the next scroll retries the page.
      state = AsyncValue.data(current.copyWith(isLoadingMore: false, hasMore: false));
    }
  }

  void search(String query) {
    _currentQuery = query.trim();
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (ContentFilter.isBlockedText(_currentQuery)) {
      _requestId++;
      state = const AsyncValue.data(CatalogState(items: []));
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (_currentQuery.isEmpty) {
        await loadCatalog();
        return;
      }

      final requestId = ++_requestId;
      state = const AsyncValue.loading();
      try {
        final results = await rust_api.searchManga(query: _currentQuery);
        if (!mounted || requestId != _requestId) return;
        state = AsyncValue.data(CatalogState(
          items: ContentFilter.filterSearchResults(results),
          isTextSearch: true,
        ));
      } catch (e, st) {
        if (!mounted || requestId != _requestId) return;
        state = AsyncValue.error(e, st);
      }
    });
  }

  void updateFilter(CatalogFilter newFilter) {
    _ref.read(catalogFilterProvider.notifier).state = newFilter;
    _persistFilter(newFilter);
    if (_currentQuery.isEmpty) {
      loadCatalog();
    }
  }

  /// Drops every filter (and its stored payload) and returns to the default feed.
  void resetFilters() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _currentQuery = '';
    _ref.read(catalogFilterProvider.notifier).state = const CatalogFilter();
    _persistFilter(const CatalogFilter());
    loadCatalog();
  }

  void _persistFilter(CatalogFilter filter) {
    if (filter.isDefault) {
      _clearStoredFilter();
      return;
    }
    rust_storage.setSetting(
      key: CatalogFilter.storageKey,
      value: jsonEncode(filter.toJson()),
    );
  }

  void _clearStoredFilter() {
    rust_storage.setSetting(key: CatalogFilter.storageKey, value: '');
  }
}