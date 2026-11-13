import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mangaloader/services/streak_notification_service.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;

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

  String get formattedSize {
    if (size <= 0) return '';
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / 1024).toStringAsFixed(0)} KB';
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

  ReleaseAsset? getBestAsset(String archInfo) {
    if (assets.isEmpty) return null;

    if (Platform.isAndroid) {
      final archLower = archInfo.toLowerCase();
      if (archLower.contains('aarch64') || archLower.contains('arm64') || archLower.contains('v8a')) {
        final match = assets.where((a) => (a.name.toLowerCase().contains('arm64') || a.name.toLowerCase().contains('v8a')) && a.name.endsWith('.apk')).firstOrNull;
        if (match != null) return match;
      } else if (archLower.contains('v7a') || archLower.contains('armeabi') || archLower.contains('arm')) {
        final match = assets.where((a) => (a.name.toLowerCase().contains('armeabi') || a.name.toLowerCase().contains('v7a') || a.name.toLowerCase().contains('armv7')) && a.name.endsWith('.apk')).firstOrNull;
        if (match != null) return match;
      } else if (archLower.contains('x86_64')) {
        final match = assets.where((a) => a.name.toLowerCase().contains('x86_64') && a.name.endsWith('.apk')).firstOrNull;
        if (match != null) return match;
      }
      return assets.where((a) => a.name.endsWith('.apk')).firstOrNull ?? assets.first;
    } else if (Platform.isWindows) {
      final match = assets.where((a) => (a.name.toLowerCase().contains('windows') || a.name.toLowerCase().contains('win')) && (a.name.endsWith('.zip') || a.name.endsWith('.exe'))).firstOrNull;
      if (match != null) return match;
      return assets.where((a) => a.name.endsWith('.zip')).firstOrNull ?? assets.first;
    } else if (Platform.isLinux) {
      final match = assets.where((a) => a.name.endsWith('.tar.gz') || a.name.endsWith('.AppImage') || a.name.endsWith('.deb')).firstOrNull;
      if (match != null) return match;
    }
    return assets.first;
  }

  String getTargetArchitectureLabel(String archInfo) {
    if (Platform.isAndroid) {
      final archLower = archInfo.toLowerCase();
      if (archLower.contains('aarch64') || archLower.contains('arm64') || archLower.contains('v8a')) {
        return 'Android (arm64-v8a)';
      } else if (archLower.contains('v7a') || archLower.contains('armeabi') || archLower.contains('arm')) {
        return 'Android (armeabi-v7a)';
      } else if (archLower.contains('x86_64')) {
        return 'Android (x86_64)';
      }
      return 'Android APK';
    } else if (Platform.isWindows) {
      return 'Windows x64';
    } else if (Platform.isLinux) {
      return 'Linux';
    } else if (Platform.isMacOS) {
      return 'macOS';
    }
    return 'Universal';
  }

  String get targetArchitectureLabel => getTargetArchitectureLabel('');

  String? get androidApkUrl {
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

enum UpdateChannel { stable, beta }

/// Minimal semantic version holder that understands prerelease suffixes
/// (`1.8.3-beta.2`), which plain integer splitting used to mangle.
class _ParsedVersion {
  final List<int> core;
  final String? pre;

  const _ParsedVersion(this.core, this.pre);

  static _ParsedVersion? parse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    // Drop build metadata (1.8.2+37).
    final plusIndex = value.indexOf('+');
    if (plusIndex != -1) value = value.substring(0, plusIndex);

    String? pre;
    final dashIndex = value.indexOf('-');
    if (dashIndex != -1) {
      pre = value.substring(dashIndex + 1);
      value = value.substring(0, dashIndex);
    }

    final core = <int>[];
    for (final part in value.split('.')) {
      final number = int.tryParse(part);
      if (number == null) return null;
      core.add(number);
    }
    while (core.length < 3) {
      core.add(0);
    }
    return _ParsedVersion(core, pre);
  }
}

const bool isRuStoreBuild = bool.fromEnvironment('RUSTORE_BUILD', defaultValue: false);

class UpdateChecker {
  static String? _cachedCurrentVersion;
  static const String defaultRepo = 'imsudoer/mangaloader';

  static Future<String> getCurrentVersion() async {
    if (_cachedCurrentVersion != null) return _cachedCurrentVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedCurrentVersion = info.version;
      return info.version;
    } catch (_) {
      return '1.9.0';
    }
  }

  static String get currentVersion => _cachedCurrentVersion ?? '1.9.0';

  static Future<AppUpdateInfo?> checkForUpdates({
    String repo = defaultRepo,
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    if (isRuStoreBuild) return null;
    try {
      final curVer = await getCurrentVersion();
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      
      final uri = channel == UpdateChannel.beta
          ? Uri.parse('https://api.github.com/repos/$repo/releases?per_page=10')
          : Uri.parse('https://api.github.com/repos/$repo/releases/latest');

      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'MangaLoader-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode != 200) {
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final dynamic decoded = jsonDecode(body);
      
      Map<String, dynamic> json;
      if (decoded is List) {
        final releases = decoded.whereType<Map<String, dynamic>>().toList();
        if (releases.isEmpty) return null;
        json = releases.first;
        if (channel == UpdateChannel.beta) {
          // GitHub orders releases by creation date, which is not the same as the
          // highest version when a hotfix lands after a beta.
          var bestTag = json['tag_name'] as String? ?? '';
          for (final release in releases.skip(1)) {
            final candidateTag = release['tag_name'] as String? ?? '';
            if (isNewerVersion(bestTag, candidateTag)) {
              bestTag = candidateTag;
              json = release;
            }
          }
        }
      } else if (decoded is Map<String, dynamic>) {
        json = decoded;
      } else {
        return null;
      }

      final rawTag = json['tag_name'] as String? ?? '';
      final isPrerelease = json['prerelease'] as bool? ?? false;
      final cleanTag = rawTag.replaceAll(RegExp(r'^[vV]'), '').replaceAll('+', '.').trim();
      
      bool hasUpdate = false;
      if (rawTag == 'dev-latest' || rawTag == 'nightly') {
        hasUpdate = true;
      } else {
        hasUpdate = isNewerVersion(curVer, cleanTag);
      }

      final assetsJson = json['assets'] as List<dynamic>? ?? [];
      final assets = assetsJson.map((a) => ReleaseAsset.fromJson(a as Map<String, dynamic>)).toList();

      return AppUpdateInfo(
        tagName: rawTag,
        title: json['name'] as String? ?? (isPrerelease ? '$rawTag (Beta/Dev)' : rawTag),
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

  /// Returns true when [remote] is newer than [current], honouring prerelease
  /// suffixes so that `1.8.3-beta.1` still beats `1.8.2`.
  static bool isNewerVersion(String current, String remote) {
    final currentVersion = _ParsedVersion.parse(current);
    final remoteVersion = _ParsedVersion.parse(remote);
    if (currentVersion == null || remoteVersion == null) return false;

    for (int i = 0; i < 3; i++) {
      if (remoteVersion.core[i] != currentVersion.core[i]) {
        return remoteVersion.core[i] > currentVersion.core[i];
      }
    }

    // Same numeric core: a final release supersedes its prereleases, and two
    // prereleases are ordered by their identifiers (beta.2 > beta.1).
    if (currentVersion.pre == null && remoteVersion.pre == null) return false;
    if (currentVersion.pre == null) return false;
    if (remoteVersion.pre == null) return true;
    return _comparePrerelease(remoteVersion.pre!, currentVersion.pre!) > 0;
  }

  static int _comparePrerelease(String a, String b) {
    final left = a.split('.');
    final right = b.split('.');
    final length = left.length > right.length ? left.length : right.length;
    for (int i = 0; i < length; i++) {
      if (i >= left.length) return -1;
      if (i >= right.length) return 1;
      final leftNumber = int.tryParse(left[i]);
      final rightNumber = int.tryParse(right[i]);
      if (leftNumber != null && rightNumber != null) {
        if (leftNumber != rightNumber) return leftNumber.compareTo(rightNumber);
      } else {
        final comparison = left[i].compareTo(right[i]);
        if (comparison != 0) return comparison;
      }
    }
    return 0;
  }

  /// Silently check for update and trigger notification once
  static Future<void> checkAppUpdateSilently({bool isRu = true}) async {
    if (isRuStoreBuild) return;
    try {
      // The background isolate has no Riverpod container, so the user preference is
      // read straight from the settings table.
      final enabled = await rust_storage.getSetting(key: 'auto_check_updates');
      if (enabled == 'false') return;

      final info = await checkForUpdates();
      if (info != null && info.hasUpdate) {
        await StreakNotificationService.showUpdateNotificationOnce(info, isRu: isRu);
      }
    } catch (e) {
      debugPrint('Silent update check error: $e');
    }
  }
}
