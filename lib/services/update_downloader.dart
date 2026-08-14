import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_checker.dart';

enum UpdateDownloadStatus {
  idle,
  downloading,
  completed,
  failed,
}

class UpdateDownloadState {
  final UpdateDownloadStatus status;
  final double progress; // 0.0 to 1.0
  final int receivedBytes;
  final int totalBytes;
  final File? downloadedFile;
  final String? error;

  const UpdateDownloadState({
    this.status = UpdateDownloadStatus.idle,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.downloadedFile,
    this.error,
  });

  UpdateDownloadState copyWith({
    UpdateDownloadStatus? status,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    File? downloadedFile,
    String? error,
  }) {
    return UpdateDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedFile: downloadedFile ?? this.downloadedFile,
      error: error ?? this.error,
    );
  }
}

class AppUpdateDownloader {
  static const MethodChannel _installerChannel = MethodChannel('bshv.mangaloader.app/installer');
  static HttpClient? _activeClient;
  static bool _isCancelled = false;

  static Future<void> download({
    required ReleaseAsset asset,
    required Function(UpdateDownloadState) onStateChanged,
  }) async {
    _isCancelled = false;
    _activeClient = HttpClient()..connectionTimeout = const Duration(seconds: 15);

    try {
      final tempDir = await getTemporaryDirectory();
      final updatesDir = Directory('${tempDir.path}/mangaloader_updates');
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }

      final saveFile = File('${updatesDir.path}/${asset.name}');

      // If file already exists and is complete size, mark complete
      if (await saveFile.exists() && asset.size > 0 && await saveFile.length() == asset.size) {
        onStateChanged(UpdateDownloadState(
          status: UpdateDownloadStatus.completed,
          progress: 1.0,
          receivedBytes: asset.size,
          totalBytes: asset.size,
          downloadedFile: saveFile,
        ));
        return;
      }

      onStateChanged(UpdateDownloadState(
        status: UpdateDownloadStatus.downloading,
        progress: 0.0,
        receivedBytes: 0,
        totalBytes: asset.size,
      ));

      final request = await _activeClient!.getUrl(Uri.parse(asset.downloadUrl));
      request.headers.set('User-Agent', 'MangaLoader-App');

      final response = await request.close();
      if (response.statusCode != 200 && response.statusCode != 302) {
        throw 'HTTP Error: ${response.statusCode}';
      }

      final totalBytes = response.contentLength > 0 ? response.contentLength : asset.size;
      int receivedBytes = 0;

      final fileSink = saveFile.openWrite();

      await for (final chunk in response) {
        if (_isCancelled) {
          await fileSink.flush();
          await fileSink.close();
          if (await saveFile.exists()) await saveFile.delete();
          onStateChanged(const UpdateDownloadState(status: UpdateDownloadStatus.idle));
          return;
        }

        fileSink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

        onStateChanged(UpdateDownloadState(
          status: UpdateDownloadStatus.downloading,
          progress: progress,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
        ));
      }

      await fileSink.flush();
      await fileSink.close();

      onStateChanged(UpdateDownloadState(
        status: UpdateDownloadStatus.completed,
        progress: 1.0,
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
        downloadedFile: saveFile,
      ));
    } catch (e) {
      debugPrint('Update download failed: $e');
      onStateChanged(UpdateDownloadState(
        status: UpdateDownloadStatus.failed,
        error: e.toString(),
      ));
    } finally {
      _activeClient = null;
    }
  }

  static void cancel() {
    _isCancelled = true;
    _activeClient?.close(force: true);
  }

  static Future<bool> installOrOpen(File file) async {
    try {
      if (Platform.isAndroid) {
        final res = await _installerChannel.invokeMethod<bool>('installApk', {'filePath': file.path});
        return res ?? false;
      } else if (Platform.isWindows) {
        // Open the folder containing the downloaded update archive
        await Process.run('explorer.exe', ['/select,', file.path]);
        return true;
      } else if (Platform.isLinux || Platform.isMacOS) {
        final uri = Uri.file(file.parent.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Install error: $e');
      return false;
    }
  }
}
