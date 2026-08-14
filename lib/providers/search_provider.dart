import 'dart:async';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';

class CatalogFilter {
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
}

final catalogFilterProvider = StateProvider<CatalogFilter>((ref) => const CatalogFilter());

final searchProvider = StateNotifierProvider<SearchNotifier, AsyncValue<List<MangaSearchResult>>>((ref) {
  final notifier = SearchNotifier(ref);
  notifier.init();
  return notifier;
});

class SearchNotifier extends StateNotifier<AsyncValue<List<MangaSearchResult>>> {
  final Ref _ref;
  Timer? _debounce;
  String _currentQuery = '';

  SearchNotifier(this._ref) : super(const AsyncValue.loading());

  void init() {
    loadCatalog();
  }

  Future<void> loadCatalog({int page = 1}) async {
    final filter = _ref.read(catalogFilterProvider);
    state = const AsyncValue.loading();
    try {
      final results = await rust_api.getCatalog(
        page: page,
        sortBy: filter.sortBy,
        typeIds: Int64List.fromList(filter.typeIds),
        statusIds: Int64List.fromList(filter.statusIds),
        genreIds: Int64List.fromList(filter.genreIds),
        tagIds: Int64List.fromList(filter.tagIds),
        ageIds: Int64List.fromList(filter.ageIds),
        formatIds: Int64List.fromList(filter.formatIds),
        scanlateIds: Int64List.fromList(filter.scanlateIds),
      );
      state = AsyncValue.data(results);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void search(String query) {
    _currentQuery = query.trim();
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (_currentQuery.isEmpty) {
        await loadCatalog();
        return;
      }
      state = const AsyncValue.loading();
      try {
        final results = await rust_api.searchManga(query: _currentQuery);
        state = AsyncValue.data(results);
      } catch (e, st) {
        state = AsyncValue.error(e, st);
      }
    });
  }

  void updateFilter(CatalogFilter newFilter) {
    _ref.read(catalogFilterProvider.notifier).state = newFilter;
    if (_currentQuery.isEmpty) {
      loadCatalog();
    }
  }
}
