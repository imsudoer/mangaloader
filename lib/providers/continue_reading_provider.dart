import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/services/content_filter.dart';
import 'package:mangaloader/services/update_checker.dart';

final continueReadingProvider = FutureProvider<List<ContinueReadingItem>>((ref) async {
  final items = await rust_storage.getContinueReadingManga();
  if (!isRuStoreBuild) return items;
  return items
      .where((i) =>
          !ContentFilter.isBlockedText(i.name) &&
          !ContentFilter.isBlockedText(i.rusName) &&
          !ContentFilter.isBlockedText(i.slugUrl))
      .toList();
});
