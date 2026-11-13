/// Turns the relations of a title into a reading order, so a franchise can be
/// started from whichever entry the user opened first.
///
/// MangaLib only returns the direct neighbours of the current title (prequel,
/// sequel, spin-off, main story), never the whole franchise, so the list is
/// built from what the relations call each neighbour. Alternate formats of the
/// same story are appended last: they are the same plot in another medium, not
/// a separate step in the order.
library;

import 'package:mangaloader/src/rust/api/models.dart';

enum ReadingStepKind {
  mainLine,
  prequel,
  current,
  sequel,
  spinOff,
  related,
  alternative,
  otherFormat,
}

class ReadingStep {
  const ReadingStep({
    required this.slugUrl,
    required this.title,
    required this.kind,
    required this.formatLabel,
    this.coverUrl,
    this.relationLabel = '',
  });

  final String slugUrl;
  final String title;
  final ReadingStepKind kind;

  /// Manga, novel, one-shot - whatever the entry is published as.
  final String formatLabel;

  /// Empty for the current title.
  final String relationLabel;
  final String? coverUrl;

  bool get isCurrent => kind == ReadingStepKind.current;
}

const Map<ReadingStepKind, int> _order = {
  ReadingStepKind.mainLine: 0,
  ReadingStepKind.prequel: 1,
  ReadingStepKind.current: 2,
  ReadingStepKind.sequel: 3,
  ReadingStepKind.spinOff: 4,
  ReadingStepKind.related: 5,
  ReadingStepKind.alternative: 6,
  ReadingStepKind.otherFormat: 7,
};

ReadingStepKind readingStepKindOf(String relationLabel) {
  final label = relationLabel.toLowerCase();
  if (label.contains('основн') || label.contains('main story')) {
    return ReadingStepKind.mainLine;
  }
  if (label.contains('приквел') || label.contains('prequel')) {
    return ReadingStepKind.prequel;
  }
  if (label.contains('сиквел') || label.contains('sequel')) {
    return ReadingStepKind.sequel;
  }
  if (label.contains('спин') ||
      label.contains('spin') ||
      label.contains('побочн') ||
      label.contains('side story') ||
      label.contains('додзинси') ||
      label.contains('doujin')) {
    return ReadingStepKind.spinOff;
  }
  if (label.contains('альтернатив') || label.contains('alternative')) {
    return ReadingStepKind.alternative;
  }
  // An unlabelled neighbour still belongs to the franchise; placing it after the
  // current title is the only assumption that cannot spoil an earlier entry.
  return ReadingStepKind.related;
}

String _titleOf(MangaSearchResult manga) {
  if (manga.rusName.trim().isNotEmpty) return manga.rusName.trim();
  if (manga.name.trim().isNotEmpty) return manga.name.trim();
  return manga.engName.trim();
}

/// Builds the ordered list, or an empty list when the title has no neighbours
/// worth showing (a standalone entry, or relations that were filtered away).
List<ReadingStep> buildReadingOrder({
  required MangaDetails current,
  required List<MangaRelationItem> relations,
  required List<MangaSearchResult> otherFormats,
}) {
  final steps = <ReadingStep>[
    ReadingStep(
      slugUrl: current.slugUrl,
      title: current.rusName.trim().isNotEmpty
          ? current.rusName.trim()
          : (current.name.trim().isNotEmpty ? current.name.trim() : current.engName.trim()),
      kind: ReadingStepKind.current,
      formatLabel: current.mangaType.trim(),
      coverUrl: current.coverUrl.trim().isEmpty ? null : current.coverUrl,
    ),
  ];

  final seen = <String>{current.slugUrl};
  var neighbourCount = 0;

  for (final relation in relations) {
    final manga = relation.manga;
    if (manga.slugUrl.isEmpty || !seen.add(manga.slugUrl)) continue;
    final title = _titleOf(manga);
    if (title.isEmpty) continue;
    neighbourCount++;
    steps.add(
      ReadingStep(
        slugUrl: manga.slugUrl,
        title: title,
        kind: readingStepKindOf(relation.relationTitle),
        formatLabel: manga.mangaType.trim(),
        coverUrl: manga.coverUrl.trim().isEmpty ? null : manga.coverUrl,
        relationLabel: relation.relationTitle,
      ),
    );
  }

  for (final manga in otherFormats) {
    if (manga.slugUrl.isEmpty || !seen.add(manga.slugUrl)) continue;
    final title = _titleOf(manga);
    if (title.isEmpty) continue;
    steps.add(
      ReadingStep(
        slugUrl: manga.slugUrl,
        title: title,
        kind: ReadingStepKind.otherFormat,
        formatLabel: manga.mangaType.trim(),
        coverUrl: manga.coverUrl.trim().isEmpty ? null : manga.coverUrl,
      ),
    );
  }

  // Nothing but the current entry: no franchise to suggest.
  if (neighbourCount == 0 && steps.length == 1) return const [];

  // Dart's sort is not stable, so rank buckets keep the server order inside a rank.
  final ranked = <ReadingStepKind, List<ReadingStep>>{};
  for (final step in steps) {
    ranked.putIfAbsent(step.kind, () => <ReadingStep>[]).add(step);
  }
  final kinds = ranked.keys.toList()
    ..sort((a, b) => _order[a]!.compareTo(_order[b]!));
  return [for (final kind in kinds) ...ranked[kind]!];
}