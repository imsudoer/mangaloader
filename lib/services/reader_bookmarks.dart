import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;

/// A single page marker inside a chapter.
class ReaderBookmark {
  const ReaderBookmark({
    required this.mangaId,
    required this.slugUrl,
    required this.volume,
    required this.number,
    required this.pageIndex,
    required this.chapterTitle,
    required this.createdAt,
  });

  final int mangaId;
  final String slugUrl;
  final String volume;
  final String number;

  /// Zero-based page index, matching what the reader uses internally.
  final int pageIndex;
  final String chapterTitle;
  final DateTime createdAt;

  String get id => '$mangaId|$volume|$number|$pageIndex';

  Map<String, dynamic> toJson() => {
        'mangaId': mangaId,
        'slugUrl': slugUrl,
        'volume': volume,
        'number': number,
        'pageIndex': pageIndex,
        'chapterTitle': chapterTitle,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ReaderBookmark.fromJson(Map<String, dynamic> json) {
    return ReaderBookmark(
      mangaId: json['mangaId'] is num ? (json['mangaId'] as num).toInt() : 0,
      slugUrl: json['slugUrl'] is String ? json['slugUrl'] as String : '',
      volume: json['volume'] is String ? json['volume'] as String : '0',
      number: json['number'] is String ? json['number'] as String : '0',
      pageIndex:
          json['pageIndex'] is num ? (json['pageIndex'] as num).toInt() : 0,
      chapterTitle:
          json['chapterTitle'] is String ? json['chapterTitle'] as String : '',
      createdAt: json['createdAt'] is String
          ? (DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

/// Page bookmarks shared by every reader screen, persisted in the settings
/// table as one JSON array. A single row keeps the whole list in memory and
/// avoids a schema change for what is a small, per-title annotation.
class ReaderBookmarkService {
  static const String _storageKey = 'reader_bookmarks';

  /// Old bookmarks fall off the end instead of growing the settings row forever.
  static const int _maxEntries = 400;

  static Future<List<ReaderBookmark>> load() async {
    try {
      final raw = await rust_storage.getSetting(key: _storageKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <ReaderBookmark>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          result.add(ReaderBookmark.fromJson(Map<String, dynamic>.from(entry)));
        } catch (error) {
          debugPrint('Skipping unreadable bookmark: $error');
        }
      }
      return result;
    } catch (error) {
      debugPrint('Unable to read bookmarks: $error');
      return const [];
    }
  }

  /// Bookmarks of one title, newest first.
  static Future<List<ReaderBookmark>> forManga(int mangaId) async {
    final all = await load();
    return all.where((bookmark) => bookmark.mangaId == mangaId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static bool contains(
    List<ReaderBookmark> bookmarks, {
    required int mangaId,
    required String volume,
    required String number,
    required int pageIndex,
  }) {
    return bookmarks.any(
      (bookmark) =>
          bookmark.mangaId == mangaId &&
          bookmark.volume == volume &&
          bookmark.number == number &&
          bookmark.pageIndex == pageIndex,
    );
  }

  /// Adds the bookmark, or removes it when the same page is already marked.
  static Future<List<ReaderBookmark>> toggle(ReaderBookmark bookmark) async {
    final all = await load();
    final exists = all.any((entry) => entry.id == bookmark.id);
    final next = exists
        ? [for (final entry in all) if (entry.id != bookmark.id) entry]
        : [bookmark, ...all];
    return _save(
      next.length > _maxEntries ? next.sublist(0, _maxEntries) : next,
    );
  }

  static Future<List<ReaderBookmark>> remove(ReaderBookmark bookmark) async {
    final all = await load();
    return _save([
      for (final entry in all)
        if (entry.id != bookmark.id) entry,
    ]);
  }

  static Future<List<ReaderBookmark>> _save(
    List<ReaderBookmark> bookmarks,
  ) async {
    try {
      await rust_storage.setSetting(
        key: _storageKey,
        value: jsonEncode([for (final entry in bookmarks) entry.toJson()]),
      );
    } catch (error) {
      debugPrint('Unable to save bookmarks: $error');
    }
    return bookmarks;
  }
}