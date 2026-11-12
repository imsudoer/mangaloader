import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/services/content_filter.dart';

final libraryProvider = StateNotifierProvider<LibraryNotifier, AsyncValue<List<LibraryEntry>>>((ref) {
  final notifier = LibraryNotifier();
  notifier.loadAll();
  return notifier;
});

/// Storage key used by `addToList` / `removeFromList` for a given list type.
String listTypeToStorageKey(ListType type) => switch (type) {
      ListType.reading => 'reading',
      ListType.planToRead => 'plan_to_read',
      ListType.completed => 'completed',
      ListType.dropped => 'dropped',
      ListType.favorites => 'favorites',
      ListType.onHold => 'on_hold',
    };

/// Library membership index, rebuilt once per library change instead of once
/// per rendered card.
final libraryListTypeIndexProvider = Provider<Map<int, ListType>>((ref) {
  final entries = ref.watch(libraryProvider).valueOrNull;
  if (entries == null) return const {};
  return {
    for (final entry in entries) entry.mangaId.toInt(): entry.listType,
  };
});

/// Library membership of a single catalog title.
///
/// Exposes only the list type so that a grid of cards rebuilds when a title
/// enters, leaves or moves inside the library instead of on every library
/// mutation. The selector compares [ListType] values, which are stable.
final mangaListTypeProvider = Provider.autoDispose.family<ListType?, int>(
  (ref, mangaId) =>
      ref.watch(libraryListTypeIndexProvider.select((index) => index[mangaId])),
);

/// Manga ids that keep at least one downloaded chapter on disk.
final downloadedMangaIdsProvider = FutureProvider<Set<int>>((ref) async {
  final chapters = await rust_storage.getAllDownloadedChapters();
  return chapters.map((chapter) => chapter.mangaId.toInt()).toSet();
});

class LibraryNotifier extends StateNotifier<AsyncValue<List<LibraryEntry>>> {
  LibraryNotifier() : super(const AsyncValue.loading());

  Future<void> loadAll() async {
    state = const AsyncValue.loading();
    try {
      final entries = await rust_storage.getAllLibraryManga();
      state = AsyncValue.data(ContentFilter.filterLibraryEntries(entries));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addToList(int mangaId, String listType, {String? slug}) async {
    await rust_storage.addToList(mangaId: mangaId, listType: listType);
    await loadAll();
    if (slug != null && slug.isNotEmpty) {
      final statusId = switch (listType) {
        'reading' => 1,
        'plan_to_read' => 2,
        'dropped' => 3,
        'completed' => 4,
        'favorites' => 5,
        'on_hold' => 6,
        _ => 1,
      };
      try {
        await rust_api.setMangaBookmark(mediaSlug: slug, statusId: statusId);
      } catch (_) {}
    }
  }

  Future<void> removeFromList(int mangaId, String listType) async {
    await rust_storage.removeFromList(mangaId: mangaId, listType: listType);
    await loadAll();
  }
}
