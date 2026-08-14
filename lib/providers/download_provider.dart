import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/src/rust/api/download_engine.dart' as rust_download;

final downloadProvider = StateNotifierProvider<DownloadNotifier, List<DownloadProgress>>((ref) {
  return DownloadNotifier();
});

class DownloadNotifier extends StateNotifier<List<DownloadProgress>> {
  DownloadNotifier() : super([]);

  void addProgress(DownloadProgress progress) {
    state = [
      for (final p in state)
        if (p.mangaSlug == progress.mangaSlug && p.chapterVolume == progress.chapterVolume && p.chapterNumber == progress.chapterNumber)
          progress
        else
          p,
      if (!state.any((p) => p.mangaSlug == progress.mangaSlug && p.chapterVolume == progress.chapterVolume && p.chapterNumber == progress.chapterNumber))
        progress
    ];
  }

  void pauseAll() {
    rust_download.pauseDownloads();
  }
  
  void resumeAll() {
    rust_download.resumeDownloads();
  }

  void cancelAll() {
    rust_download.cancelDownloads();
    state = [];
  }
}
