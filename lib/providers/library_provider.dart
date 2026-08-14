import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
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

  Future<void> addToList(int mangaId, String listType) async {
    await rust_storage.addToList(mangaId: mangaId, listType: listType);
    await loadAll();
  }

  Future<void> removeFromList(int mangaId, String listType) async {
    await rust_storage.removeFromList(mangaId: mangaId, listType: listType);
    await loadAll();
  }
}
