import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';

final customListsProvider = StateNotifierProvider<CustomListsNotifier, AsyncValue<List<CustomUserList>>>((ref) {
  return CustomListsNotifier();
});

class CustomListsNotifier extends StateNotifier<AsyncValue<List<CustomUserList>>> {
  CustomListsNotifier() : super(const AsyncValue.loading()) {
    loadLists();
  }

  Future<void> loadLists() async {
    try {
      final lists = await rust_storage.getCustomLists();
      state = AsyncValue.data(lists);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<CustomUserList?> createList(String name, {String color = '#8A897C'}) async {
    try {
      final item = await rust_storage.createCustomList(name: name, color: color);
      await loadLists();
      return item;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteList(int listId) async {
    try {
      await rust_storage.deleteCustomList(listId: listId);
      await loadLists();
    } catch (_) {}
  }

  Future<void> addMangaToList(int listId, int mangaId) async {
    try {
      await rust_storage.addToCustomList(listId: listId, mangaId: mangaId);
      await loadLists();
    } catch (_) {}
  }

  Future<void> removeMangaFromList(int listId, int mangaId) async {
    try {
      await rust_storage.removeFromCustomList(listId: listId, mangaId: mangaId);
      await loadLists();
    } catch (_) {}
  }
}

final customListEntriesProvider = FutureProvider.family<List<LibraryEntry>, int>((ref, listId) async {
  return rust_storage.getCustomListEntries(listId: listId);
});

final mangaCustomListsProvider = FutureProvider.family<List<int>, int>((ref, mangaId) async {
  final res = await rust_storage.getMangaCustomLists(mangaId: mangaId);
  return res.map((i) => i.toInt()).toList();
});

final mangaCustomTagsProvider = FutureProvider.family<List<String>, int>((ref, mangaId) async {
  return rust_storage.getCustomTags(mangaId: mangaId);
});
