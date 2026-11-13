/// Title matching helpers used to recognise the same story published in another
/// format (for example a manga and its light novel adaptation).
///
/// MangaLib does not always link such entries as official relations, so the catalog
/// is queried by title and the results are compared with these rules.
enum EditionKind { manga, novel, other }

EditionKind editionKindOf(String typeLabel) {
  final label = typeLabel.toLowerCase();
  if (label.contains('ранобэ') ||
      label.contains('новелл') ||
      label.contains('novel') ||
      label.contains('light')) {
    return EditionKind.novel;
  }
  if (label.contains('манга') ||
      label.contains('manga') ||
      label.contains('манхва') ||
      label.contains('manhwa') ||
      label.contains('маньхуа') ||
      label.contains('manhua') ||
      label.contains('комикс') ||
      label.contains('comic') ||
      label.contains('руманга')) {
    return EditionKind.manga;
  }
  return EditionKind.other;
}

/// Lowercases and collapses everything that is not a letter or a digit.
String normalizeTitle(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Drops the subtitle part: "Токийский гуль: re" and "Токийский гуль (новелла)"
/// both reduce to "токийский гуль".
String titleBase(String raw) {
  var value = raw.toLowerCase();
  final separator = RegExp(r'[:—–]|\s-\s|\(').firstMatch(value);
  if (separator != null && separator.start >= 4) {
    value = value.substring(0, separator.start);
  }
  return normalizeTitle(value);
}

/// True when both titles plausibly describe the same story.
bool isSameStoryTitles(String a, String b) {
  final baseA = titleBase(a);
  final baseB = titleBase(b);
  if (baseA.length < 3 || baseB.length < 3) return false;
  if (baseA == baseB) return true;

  final shorter = baseA.length <= baseB.length ? baseA : baseB;
  final longer = baseA.length <= baseB.length ? baseB : baseA;
  if (!longer.startsWith(shorter)) return false;
  // Allow short suffixes such as "том 2" or "official", but not a different title.
  return longer.length - shorter.length <= 12;
}

String primaryTitle({
  required String name,
  required String rusName,
  required String engName,
}) {
  if (rusName.trim().isNotEmpty) return rusName;
  if (name.trim().isNotEmpty) return name;
  return engName;
}