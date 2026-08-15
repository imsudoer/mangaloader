import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';

final continueReadingProvider = FutureProvider<List<ContinueReadingItem>>((ref) async {
  return await rust_storage.getContinueReadingManga();
});
