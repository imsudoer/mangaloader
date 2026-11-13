/// Local, offline-friendly text matching for lists the user already has:
/// downloads, the library, custom lists.
///
/// The MangaLib search box is backed by the server and answers exact queries;
/// this helper is for the opposite case, where the whole dataset is in memory
/// and a typo or a Latin spelling should still find the title.
///
/// Matching works on a normalized form:
/// - lowercase;
/// - `ё` folded to `е`, typographic dashes and quotes to spaces;
/// - punctuation and repeated spaces collapsed;
/// - Cyrillic text is additionally transliterated, so `tokijskij gul` matches
///   `Токийский гуль`.
///
/// Three tiers are tried, strongest first:
/// 1. the whole query appears in the text;
/// 2. every query token appears in the text (as a substring);
/// 3. every query token is within a small edit distance of a text token, which
///    absorbs typos like `фарфоравая кукла`.
library;

final RegExp _letterPattern =
    RegExp(r'[0-9a-zа-яіїєґ]', unicode: true);

const Map<String, String> _translit = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ж': 'zh',
  'з': 'z',
  'и': 'i',
  'й': 'i',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'kh',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'shch',
  'ъ': '',
  'ы': 'y',
  'ь': '',
  'э': 'e',
  'ю': 'yu',
  'я': 'ya',
  'і': 'i',
  'ї': 'i',
  'є': 'e',
  'ґ': 'g',
};

/// Normalized text used by [matchesFuzzy] and [fuzzyScore]. Exposed for tests.
String normalizeForSearch(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  var lastWasSpace = true;
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final folded = switch (char) {
      'ё' => 'е',
      '–' || '—' || '―' => ' ',
      '«' || '»' || '“' || '”' || '„' || '‘' || '’' => ' ',
      _ => char,
    };
    final isLetter = _letterPattern.hasMatch(folded);
    if (isLetter) {
      buffer.write(folded);
      lastWasSpace = false;
    } else if (!lastWasSpace) {
      buffer.write(' ');
      lastWasSpace = true;
    }
  }
  return buffer.toString().trim();
}

/// Latin form of a normalized string, used to match `tokijskij` to
/// `токийский`. Latin characters pass through unchanged apart from `j`, which
/// is folded to `i` because Russian has no `j` and users type it for `й`.
String transliterateForSearch(String normalized) {
  final buffer = StringBuffer();
  for (final rune in normalized.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_translit[char] ?? char);
  }
  return buffer.toString().replaceAll('j', 'i');
}

/// Whether [text] plausibly matches [query].
bool matchesFuzzy(String text, String query) => fuzzyScore(text, query) > 0;

/// 0 for no match, higher for closer matches. Used to rank local results.
int fuzzyScore(String text, String query) {
  final needle = normalizeForSearch(query);
  if (needle.isEmpty) return 0;

  final haystack = normalizeForSearch(text);
  if (haystack.isEmpty) return 0;
  if (haystack == needle) return 100;
  if (haystack.startsWith(needle)) return 90;
  if (haystack.contains(needle)) return 80;

  final haystackLatin = transliterateForSearch(haystack);
  final needleLatin = transliterateForSearch(needle);
  if (haystackLatin.contains(needleLatin)) return 75;

  final tokens = haystack.split(' ').where((token) => token.isNotEmpty).toList();
  final queryTokens =
      needle.split(' ').where((token) => token.isNotEmpty).toList();

  if (queryTokens.every((q) => tokens.any((t) => t.contains(q)))) {
    return 60;
  }

  if (queryTokens.every(
    (q) => tokens.any(
      (t) =>
          _withinDistance(t, q) ||
          _withinDistance(
            transliterateForSearch(t),
            transliterateForSearch(q),
          ),
    ),
  )) {
    return 40;
  }

  return 0;
}

/// Sorts `items` by [fuzzyScore] descending, keeping only matching entries.
List<T> fuzzyFilter<T>(
  List<T> items,
  String query,
  String Function(T item) textOf,
) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return items;
  final scored = <({T item, int score})>[];
  for (final item in items) {
    final score = fuzzyScore(textOf(item), trimmed);
    if (score > 0) scored.add((item: item, score: score));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return textOf(a.item).toLowerCase().compareTo(textOf(b.item).toLowerCase());
  });
  return [for (final entry in scored) entry.item];
}

bool _withinDistance(String token, String query) {
  if (query.length < 4 || token.length < 3) return false;
  // One edit per four characters keeps short titles from matching everything.
  final allowed = query.length >= 8 ? 2 : 1;
  if ((token.length - query.length).abs() > allowed) return false;
  return _levenshteinAtMost(token, query, allowed);
}

/// Bounded Levenshtein distance: true when at most [budget] edits separate the
/// strings. The rows are computed fully because a shorter intermediate row can
/// still grow again; titles here are a few dozen characters at most.
bool _levenshteinAtMost(String a, String b, int budget) {
  if ((a.length - b.length).abs() > budget) return false;
  final previous = List<int>.generate(b.length + 1, (index) => index);
  final current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + cost;
      current[j] = _min3(deletion, insertion, substitution);
    }
    previous.setAll(0, current);
  }
  return previous[b.length] <= budget;
}

int _min3(int a, int b, int c) {
  final first = a < b ? a : b;
  return first < c ? first : c;
}