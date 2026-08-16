import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';

final mangaDetailsProvider = FutureProvider.family<MangaDetails, String>((ref, slugUrl) async {
  try {
    final details = await rust_api.getMangaDetails(slugUrl: slugUrl);
    // Cache to SQLite for offline access
    await rust_storage.saveManga(manga: details);
    return details;
  } catch (e) {
    // Fallback to SQLite cached manga when offline
    final cached = await rust_storage.getCachedManga(slugUrl: slugUrl);
    if (cached != null) {
      return cached;
    }
    rethrow;
  }
});

final mangaChaptersProvider = FutureProvider.family<List<Chapter>, String>((ref, slugUrl) async {
  try {
    final chapters = await rust_api.getChapters(slugUrl: slugUrl);
    final cachedManga = await rust_storage.getCachedManga(slugUrl: slugUrl);
    if (cachedManga != null) {
      await rust_storage.cacheChapters(mangaId: cachedManga.id, chapters: chapters);
    }
    return chapters;
  } catch (e) {
    // Offline fallback: try reading cached chapters from SQLite
    final cachedManga = await rust_storage.getCachedManga(slugUrl: slugUrl);
    if (cachedManga != null) {
      final cachedChaps = await rust_storage.getCachedChapters(mangaId: cachedManga.id);
      if (cachedChaps.isNotEmpty) {
        return cachedChaps;
      }
    }
    rethrow;
  }
});

final mangaCommentsProvider = FutureProvider.family<CommentsData, int>((ref, mangaId) async {
  try {
    return await rust_api.getMangaComments(mangaId: mangaId, page: 1);
  } catch (_) {
    return const CommentsData(root: [], replies: [], hasNextPage: false, page: 1);
  }
});

final mangaRelationsProvider = FutureProvider.family<List<MangaRelationItem>, String>((ref, slugUrl) async {
  try {
    return await rust_api.getMangaRelations(slugUrl: slugUrl);
  } catch (_) {
    return const [];
  }
});

final mangaSimilarProvider = FutureProvider.family<List<MangaSimilarItem>, String>((ref, slugUrl) async {
  try {
    return await rust_api.getMangaSimilar(slugUrl: slugUrl);
  } catch (_) {
    return const [];
  }
});

final mangaConstantsProvider = FutureProvider<MangaConstants>((ref) async {
  try {
    return await rust_api.getConstants();
  } catch (_) {
    return const MangaConstants(
      types: [],
      statuses: [],
      scanlateStatuses: [],
      ageRestrictions: [],
      formats: [],
      genres: [],
      tags: [],
    );
  }
});
