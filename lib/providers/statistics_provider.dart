import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';

final statisticsProvider = FutureProvider<ReadingStatistics>((ref) async {
  return rust_storage.getReadingStatistics();
});

final readingSessionStatsProvider = FutureProvider<ReadingSessionInfo>((ref) async {
  return rust_storage.getReadingSessionStats();
});
