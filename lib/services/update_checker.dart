import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;

  ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

class AppUpdateInfo {
  final String tagName;
  final String title;
  final String changelog;
  final String releaseUrl;
  final String publishedAt;
  final List<ReleaseAsset> assets;
  final bool hasUpdate;

  AppUpdateInfo({
    required this.tagName,
    required this.title,
    required this.changelog,
    required this.releaseUrl,
    required this.publishedAt,
    required this.assets,
    required this.hasUpdate,
  });

  String? get androidApkUrl {
    // Prefer arm64-v8a or universal APK
    for (final a in assets) {
      if (a.name.contains('arm64') && a.name.endsWith('.apk')) return a.downloadUrl;
    }
    for (final a in assets) {
      if (a.name.endsWith('.apk')) return a.downloadUrl;
    }
    return null;
  }

  String? get windowsZipUrl {
    for (final a in assets) {
      if (a.name.contains('windows') && (a.name.endsWith('.zip') || a.name.endsWith('.exe'))) {
        return a.downloadUrl;
      }
    }
    return null;
  }
}

class UpdateChecker {
  static const String currentVersion = '1.3.1';
  static const String defaultRepo = 'imsudoer/mangaloader';

  static Future<AppUpdateInfo?> checkForUpdates({String repo = defaultRepo}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      
      final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'MangaLoader-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode != 200) {
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final rawTag = json['tag_name'] as String? ?? '';
      final cleanTag = rawTag.replaceAll('v', '').replaceAll('+', '.').trim();
      final hasUpdate = _isNewerVersion(currentVersion, cleanTag);

      final assetsJson = json['assets'] as List<dynamic>? ?? [];
      final assets = assetsJson.map((a) => ReleaseAsset.fromJson(a as Map<String, dynamic>)).toList();

      return AppUpdateInfo(
        tagName: rawTag,
        title: json['name'] as String? ?? rawTag,
        changelog: json['body'] as String? ?? '',
        releaseUrl: json['html_url'] as String? ?? '',
        publishedAt: json['published_at'] as String? ?? '',
        assets: assets,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return null;
    }
  }

  static bool _isNewerVersion(String current, String remote) {
    try {
      final currentParts = current.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final remoteParts = remote.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      while (remoteParts.length < 3) {
        remoteParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
