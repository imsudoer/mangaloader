import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mangaloader/src/rust/api/models.dart' show MalImportResult;
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;

/// Automatic library snapshots plus the MAL "import from link" downloader.
///
/// Everything here runs without a provider container: the Workmanager isolate
/// owns no Riverpod scope, so configuration is read from persisted settings.
class BackupService {
  const BackupService._();

  static const String intervalSettingKey = 'auto_backup_interval_days';
  static const String lastBackupSettingKey = 'last_backup_at';
  static const String backupsDirectoryName = 'backups';
  static const int maxKeptBackups = 5;

  static const String _filePrefix = 'mangaloader_backup_';

  /// Runs a backup when the configured interval has elapsed.
  ///
  /// Returns the written file path, or null when backups are off, not due yet,
  /// or the export failed.
  static Future<String?> runIfDue() async {
    try {
      final intervalDays = int.tryParse(
            await rust_storage.getSetting(key: intervalSettingKey) ?? '',
          ) ??
          0;
      if (intervalDays <= 0) return null;

      final last = await lastBackupAt();
      if (last != null) {
        final dueAt = last.add(Duration(days: intervalDays));
        if (DateTime.now().isBefore(dueAt)) return null;
      }

      return await backupNow();
    } catch (e) {
      debugPrint('BackupService: interval check failed: $e');
      return null;
    }
  }

  /// Writes a snapshot into `{documents}/backups` and prunes older ones.
  ///
  /// Never throws: a failing export must not interrupt the caller, which can be
  /// a background isolate or a settings button.
  static Future<String?> backupNow() async {
    try {
      final json = await rust_storage.exportBackupJson();
      final directory = await _backupsDirectory();
      final now = DateTime.now();
      final file = File('${directory.path}/$_filePrefix${_fileTimestamp(now)}.json');
      await file.writeAsString(json, flush: true);
      await _pruneOldBackups(directory);
      await rust_storage.setSetting(
        key: lastBackupSettingKey,
        value: now.toIso8601String(),
      );
      return file.path;
    } catch (e) {
      debugPrint('BackupService: backup failed: $e');
      return null;
    }
  }

  /// Timestamp of the newest stored backup, or null when there is none yet.
  static Future<DateTime?> lastBackupAt() async {
    try {
      final raw = await rust_storage.getSetting(key: lastBackupSettingKey);
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    } catch (e) {
      debugPrint('BackupService: failed to read last backup timestamp: $e');
      return null;
    }
  }

  static Future<Directory> _backupsDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/$backupsDirectoryName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<void> _pruneOldBackups(Directory directory) async {
    final backups = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.startsWith(_filePrefix) && name.toLowerCase().endsWith('.json')) {
        backups.add(entity);
      }
    }
    if (backups.length <= maxKeptBackups) return;

    // Snapshot names embed a zero padded `YYYYMMDD_HHmm` stamp, so a reverse
    // lexical sort is the newest-first order.
    backups.sort((a, b) => b.path.compareTo(a.path));
    for (final file in backups.skip(maxKeptBackups)) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('BackupService: failed to delete ${file.path}: $e');
      }
    }
  }

  static String _fileTimestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}_${two(time.hour)}${two(time.minute)}';
  }
}

/// Failure kinds of [MalUrlImporter], kept transport-neutral so the UI decides
/// how to phrase them.
enum MalUrlImportError {
  invalidUrl,
  timeout,
  tooLarge,
  httpStatus,
  network,
  importFailed,
}

class MalUrlImportException implements Exception {
  const MalUrlImportException(this.kind, {this.detail});

  final MalUrlImportError kind;
  final String? detail;

  @override
  String toString() =>
      'MalUrlImportException(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// Downloads a MyAnimeList XML export over http(s) and hands it to the core.
class MalUrlImporter {
  const MalUrlImporter._();

  static const Duration requestTimeout = Duration(seconds: 15);
  static const int maxDownloadBytes = 5 * 1024 * 1024;

  static Future<MalImportResult> importFromUrl(String rawUrl) async {
    final uri = _parse(rawUrl);
    final client = HttpClient()..connectionTimeout = requestTimeout;

    try {
      final request = await client.getUrl(uri).timeout(requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/xml, text/xml, */*');
      final response = await request.close().timeout(requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        try {
          await response.drain<void>();
        } catch (_) {}
        throw MalUrlImportException(
          MalUrlImportError.httpStatus,
          detail: 'HTTP ${response.statusCode}',
        );
      }

      if (response.contentLength > maxDownloadBytes) {
        throw const MalUrlImportException(MalUrlImportError.tooLarge);
      }

      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(requestTimeout)) {
        buffer.add(chunk);
        if (buffer.length > maxDownloadBytes) {
          throw const MalUrlImportException(MalUrlImportError.tooLarge);
        }
      }

      final xml = utf8.decode(buffer.takeBytes(), allowMalformed: true);
      if (!xml.contains('<manga')) {
        throw const MalUrlImportException(
          MalUrlImportError.importFailed,
          detail: 'no <manga> entries',
        );
      }

      try {
        return await rust_storage.importMalXml(xmlContent: xml);
      } catch (e) {
        throw MalUrlImportException(MalUrlImportError.importFailed, detail: e.toString());
      }
    } on MalUrlImportException {
      rethrow;
    } on TimeoutException catch (e) {
      throw MalUrlImportException(MalUrlImportError.timeout, detail: e.toString());
    } on SocketException catch (e) {
      throw MalUrlImportException(MalUrlImportError.network, detail: e.message);
    } on HttpException catch (e) {
      throw MalUrlImportException(MalUrlImportError.network, detail: e.message);
    } finally {
      client.close(force: true);
    }
  }

  static Uri _parse(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const MalUrlImportException(MalUrlImportError.invalidUrl);
    }
    return uri;
  }
}