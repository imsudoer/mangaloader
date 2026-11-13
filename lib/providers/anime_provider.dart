import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/services/anime_search.dart';
import 'package:mangaloader/services/content_filter.dart';

/// Identifies the title whose anime adaptations should be looked up.
class AnimeLookupQuery {
  const AnimeLookupQuery(this.title);

  final String title;

  @override
  bool operator ==(Object other) =>
      other is AnimeLookupQuery && other.title == title;

  @override
  int get hashCode => title.hashCode;
}

/// Anime adaptations of a manga or light novel, matched by title. RuStore builds
/// filter the results the same way as every other list.
final animeAdaptationsProvider =
    FutureProvider.autoDispose.family<List<AnimeHit>, AnimeLookupQuery>((ref, query) async {
  if (query.title.trim().isEmpty || ContentFilter.isBlockedText(query.title)) {
    return const [];
  }
  final hits = await AnimeSearchService.search(query.title);
  return hits
      .where((hit) =>
          !ContentFilter.isBlockedText(hit.name) &&
          !ContentFilter.isBlockedText(hit.russian))
      .toList();
});