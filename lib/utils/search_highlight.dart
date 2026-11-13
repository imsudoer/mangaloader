/// Locates the parts of a title that matched an offline search query, so the
/// results can show why a title was found.
///
/// The search index is token based, so the query is split on the same boundaries
/// and every token is looked up independently; a query with several words marks
/// each of them instead of requiring the whole phrase.
library;

import 'dart:math' as math;

/// Ranges are half-open `[start, end)` and never overlap.
List<(int, int)> highlightRanges(
  String text,
  String query, {
  int maxRanges = 24,
}) {
  if (text.isEmpty || query.trim().isEmpty || maxRanges <= 0) return const [];

  final haystack = text.toLowerCase();
  final tokens = query
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((token) => token.length >= 2)
      .toSet();

  final found = <(int, int)>[];
  for (final token in tokens) {
    var start = 0;
    while (found.length < maxRanges) {
      final index = haystack.indexOf(token, start);
      if (index < 0) break;
      found.add((index, index + token.length));
      start = index + token.length;
    }
    if (found.length >= maxRanges) break;
  }
  if (found.isEmpty) return const [];

  found.sort((a, b) => a.$1.compareTo(b.$1));

  final merged = <(int, int)>[];
  for (final range in found) {
    if (merged.isEmpty || range.$1 > merged.last.$2) {
      merged.add(range);
    } else {
      final previous = merged.removeLast();
      merged.add((previous.$1, math.max(previous.$2, range.$2)));
    }
  }
  return merged;
}