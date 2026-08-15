import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';

final streakProvider = StateNotifierProvider<StreakNotifier, AsyncValue<ReadingStreakInfo>>((ref) {
  return StreakNotifier();
});

class StreakNotifier extends StateNotifier<AsyncValue<ReadingStreakInfo>> {
  StreakNotifier() : super(const AsyncValue.loading()) {
    loadStreak();
  }

  Future<void> loadStreak() async {
    try {
      final info = await rust_storage.getReadingStreak();
      state = AsyncValue.data(info);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> recordChapterRead() async {
    try {
      final updated = await rust_storage.recordChapterReadForStreak();
      state = AsyncValue.data(updated);
    } catch (_) {
      loadStreak();
    }
  }

  Future<void> syncStreak(int days) async {
    try {
      final updated = await rust_storage.syncReadingStreak(days: days);
      state = AsyncValue.data(updated);
    } catch (_) {
      loadStreak();
    }
  }
}
