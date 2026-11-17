import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mangaloader/utils/title_match.dart';

/// One anime entry returned by the public Shikimori catalog.
class AnimeHit {
  const AnimeHit({
    required this.id,
    required this.name,
    required this.russian,
    required this.kind,
    required this.airedOn,
    required this.episodes,
    required this.score,
    required this.imageUrl,
    this.path = '',
  });

  final int id;
  final String name;
  final String russian;
  final String kind;
  final String airedOn;
  final int episodes;
  final String score;
  final String imageUrl;

  /// Canonical Shikimori path from the API (`/animes/42897-horimiya`), so the
  /// browser lands on the entry instead of a hand-built URL that may 404.
  final String path;

  String get displayTitle => russian.trim().isNotEmpty ? russian.trim() : name.trim();

  String get pageUrl {
    final normalized = path.trim();
    if (normalized.isEmpty) return 'https://shikimori.one/animes/$id';
    return normalized.startsWith('http')
        ? normalized
        : 'https://shikimori.one/${normalized.replaceFirst(RegExp(r'^/+'), '')}';
  }

  int get year {
    final parsed = DateTime.tryParse(airedOn);
    return parsed?.year ?? 0;
  }
}

/// Looks up anime adaptations by title. Shikimori is used because it is free,
/// needs no key, returns Russian titles and covers the same audience as
/// MangaLib; nothing is sent about the user, only the title being viewed.
class AnimeSearchService {
  static const String _host = 'https://shikimori.one/api/animes';
  static const String _origin = 'https://shikimori.one';

  /// Shikimori returns image paths such as `/system/animes/original/42897.jpg`
  /// unless an absolute URL is requested, which CachedNetworkImage rejects.
  static String _absoluteImageUrl(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    return '$_origin/${trimmed.replaceFirst(RegExp(r'^/+'), '')}';
  }

  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _ttl = Duration(minutes: 30);

  static Future<List<AnimeHit>> search(String title, {int limit = 6}) async {
    final query = title.trim();
    if (query.length < 3) return const [];

    final cached = _cache[query];
    if (cached != null && DateTime.now().difference(cached.at) < _ttl) {
      return cached.hits;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(
        '$_host?limit=$limit&order=ranked&search=${Uri.encodeQueryComponent(query)}',
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'MangaLoader-App');
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) return const [];

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! List) return const [];

      final hits = <AnimeHit>[];
      for (final raw in decoded) {
        if (raw is! Map<String, dynamic>) continue;
        final name = (raw['name'] as String? ?? '').trim();
        final russian = (raw['russian'] as String? ?? '').trim();
        // The catalog answers any query with loosely related entries; keep only
        // the ones that plausibly adapt the same story.
        final matchesTitle = isSameStoryTitles(name, query) ||
            (russian.isNotEmpty && isSameStoryTitles(russian, query));
        if (!matchesTitle) continue;
        final image = raw['image'];
        final imagePath = image is Map<String, dynamic>
            ? (image['original'] as String? ?? image['preview'] as String? ?? '')
            : '';
        hits.add(
          AnimeHit(
            id: (raw['id'] as num?)?.toInt() ?? 0,
            name: name,
            russian: russian,
            kind: (raw['kind'] as String? ?? '').trim(),
            airedOn: (raw['aired_on'] as String? ?? '').trim(),
            episodes: (raw['episodes'] as num?)?.toInt() ?? 0,
            score: (raw['score'] as String? ?? '').trim(),
            imageUrl: _absoluteImageUrl(imagePath),
            path: (raw['url'] as String? ?? '').trim(),
          ),
        );
        if (hits.length >= limit) break;
      }

      _cache[query] = _CacheEntry(DateTime.now(), hits);
      return hits;
    } catch (error) {
      debugPrint('Anime lookup failed: $error');
      return const [];
    } finally {
      client.close(force: true);
    }
  }
}

class _CacheEntry {
  const _CacheEntry(this.at, this.hits);

  final DateTime at;
  final List<AnimeHit> hits;
}