import 'dart:convert';

import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;

/// Small persistent counter store for achievements that cannot be derived from
/// the reading database (taps, copied logs, used reader presets, ...). Values are
/// kept in memory and flushed to the settings table after every change.
class AchievementEvents {
  AchievementEvents._();

  static final AchievementEvents instance = AchievementEvents._();
  static const String _storageKey = 'achievement_events';

  final Map<String, int> counters = <String, int>{};
  final Map<String, Set<String>> sets = <String, Set<String>>{};

  bool _loaded = false;
  Future<void>? _loading;
  Future<void> _writeQueue = Future<void>.value();

  int operator [](String key) => counters[key] ?? 0;

  bool setContains(String key, String value) => sets[key]?.contains(value) ?? false;

  Set<String> setOf(String key) => sets[key] ?? const <String>{};

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rust_storage.getSetting(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final rawCounters = decoded['counters'];
          if (rawCounters is Map<String, dynamic>) {
            rawCounters.forEach((key, value) {
              if (value is num) counters[key] = value.toInt();
            });
          }
          final rawSets = decoded['sets'];
          if (rawSets is Map<String, dynamic>) {
            rawSets.forEach((key, value) {
              if (value is List) {
                sets[key] = value.whereType<String>().toSet();
              }
            });
          }
        }
      }
    } catch (_) {
      // A malformed counter blob must never break the achievements screen.
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  void increment(String key, [int by = 1]) {
    counters[key] = (counters[key] ?? 0) + by;
    _schedulePersist();
  }

  void addToSet(String key, String value) {
    final set = sets.putIfAbsent(key, () => <String>{});
    if (!set.add(value)) return;
    _schedulePersist();
  }

  void setCounter(String key, int value) {
    if (counters[key] == value) return;
    counters[key] = value;
    _schedulePersist();
  }

  void _schedulePersist() {
    final payload = jsonEncode({
      'counters': counters,
      'sets': sets.map((key, value) => MapEntry(key, value.toList())),
    });
    _writeQueue = _writeQueue.then(
      (_) => rust_storage.setSetting(key: _storageKey, value: payload),
    ).catchError((_) {});
  }
}

String achievementDayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}