import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/src/rust/api/models.dart';

/// Content filtering service to comply with RuStore and local regulatory requirements.
/// Only active when [isRuStoreBuild] is true (compiled with --dart-define=RUSTORE_BUILD=true).
class ContentFilter {
  /// Returns true if the text matches prohibited manga patterns in RuStore builds.
  static bool isBlockedText(String? text, {bool forceCheck = false}) {
    if ((!isRuStoreBuild && !forceCheck) || text == null || text.isEmpty) return false;

    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[-_:.,/\\+]+'), ' ')
        .trim();

    // Tokyo Ghoul check (any variation: original, re, jack, spin-offs)
    if ((normalized.contains('токийск') && normalized.contains('гул')) ||
        (normalized.contains('tokyo') && normalized.contains('ghoul')) ||
        normalized.contains('tokyoghoul') ||
        normalized.contains('tokiyskiy gul')) {
      return true;
    }

    // Death Note check (any variation: original, short stories, one-shots)
    if ((normalized.contains('тетрад') && normalized.contains('смерт')) ||
        (normalized.contains('death') && normalized.contains('note')) ||
        normalized.contains('deathnote') ||
        normalized.contains('tetrad smerti')) {
      return true;
    }

    // Elfen Lied check
    if ((normalized.contains('эльфийск') && normalized.contains('песн')) ||
        (normalized.contains('elfen') && normalized.contains('lied')) ||
        normalized.contains('elfenlied')) {
      return true;
    }

    // Inuyashiki check
    if (normalized.contains('инуяшики') ||
        normalized.contains('инуясики') ||
        normalized.contains('inuyashiki')) {
      return true;
    }

    // Interspecies Reviewers check
    if ((normalized.contains('межвидов') && normalized.contains('реценз')) ||
        normalized.contains('ishuzoku') ||
        (normalized.contains('interspecies') && normalized.contains('reviewer'))) {
      return true;
    }

    return false;
  }

  /// Check if a MangaSearchResult is prohibited in RuStore build
  static bool isBlockedSearchResult(MangaSearchResult manga, {bool forceCheck = false}) {
    if (!isRuStoreBuild && !forceCheck) return false;
    return isBlockedText(manga.name, forceCheck: forceCheck) ||
        isBlockedText(manga.rusName, forceCheck: forceCheck) ||
        isBlockedText(manga.engName, forceCheck: forceCheck) ||
        isBlockedText(manga.slug, forceCheck: forceCheck) ||
        isBlockedText(manga.slugUrl, forceCheck: forceCheck);
  }

  /// Check if MangaDetails is prohibited in RuStore build
  static bool isBlockedDetails(MangaDetails manga, {bool forceCheck = false}) {
    if (!isRuStoreBuild && !forceCheck) return false;
    return isBlockedText(manga.name, forceCheck: forceCheck) ||
        isBlockedText(manga.rusName, forceCheck: forceCheck) ||
        isBlockedText(manga.engName, forceCheck: forceCheck) ||
        isBlockedText(manga.slug, forceCheck: forceCheck) ||
        isBlockedText(manga.slugUrl, forceCheck: forceCheck);
  }

  /// Filter a list of MangaSearchResult
  static List<MangaSearchResult> filterSearchResults(List<MangaSearchResult> list, {bool forceCheck = false}) {
    if (!isRuStoreBuild && !forceCheck) return list;
    return list.where((m) => !isBlockedSearchResult(m, forceCheck: forceCheck)).toList();
  }

  /// Filter a list of LibraryEntry
  static List<LibraryEntry> filterLibraryEntries(List<LibraryEntry> list, {bool forceCheck = false}) {
    if (!isRuStoreBuild && !forceCheck) return list;
    return list
        .where((m) =>
            !isBlockedText(m.name, forceCheck: forceCheck) &&
            !isBlockedText(m.rusName, forceCheck: forceCheck) &&
            !isBlockedText(m.slugUrl, forceCheck: forceCheck))
        .toList();
  }
}
