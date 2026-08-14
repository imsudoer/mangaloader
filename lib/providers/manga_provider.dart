import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';

final mangaDetailsProvider = FutureProvider.family<MangaDetails, String>((ref, slugUrl) async {
  return rust_api.getMangaDetails(slugUrl: slugUrl);
});

final mangaChaptersProvider = FutureProvider.family<List<Chapter>, String>((ref, slugUrl) async {
  return rust_api.getChapters(slugUrl: slugUrl);
});

final mangaCommentsProvider = FutureProvider.family<CommentsData, int>((ref, mangaId) async {
  return rust_api.getMangaComments(mangaId: mangaId, page: 1);
});

final mangaRelationsProvider = FutureProvider.family<List<MangaRelationItem>, String>((ref, slugUrl) async {
  return rust_api.getMangaRelations(slugUrl: slugUrl);
});

final mangaSimilarProvider = FutureProvider.family<List<MangaSimilarItem>, String>((ref, slugUrl) async {
  return rust_api.getMangaSimilar(slugUrl: slugUrl);
});

final mangaConstantsProvider = FutureProvider<MangaConstants>((ref) async {
  return rust_api.getConstants();
});
