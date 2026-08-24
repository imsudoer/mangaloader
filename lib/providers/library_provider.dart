import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';

final libraryProvider = StateNotifierProvider<LibraryNotifier, AsyncValue<List<LibraryEntry>>>((ref) {
  final notifier = LibraryNotifier();
  notifier.loadAll();
  return notifier;
});

class LibraryNotifier extends StateNotifier<AsyncValue<List<LibraryEntry>>> {
  LibraryNotifier() : super(const AsyncValue.loading());

  Future<void> loadAll() async {
    state = const AsyncValue.loading();
    try {
      final entries = await rust_storage.getAllLibraryManga();
      state = AsyncValue.data(entries);
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
