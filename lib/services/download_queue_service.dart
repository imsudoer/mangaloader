import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mangaloader/l10n/strings/notification_strings.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mangaloader/providers/download_provider.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/download_engine.dart' as rust_download;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/theme/app_tokens.dart';

enum DownloadQueueStatus {
  queued,
  downloading,
  waitingForWifi,
  failed,
  completed;

  static DownloadQueueStatus parse(String? value) {
    for (final status in DownloadQueueStatus.values) {
      if (status.name == value) return status;
    }
    return DownloadQueueStatus.queued;
  }
}

class DownloadQueueItem {
  final String slugUrl;
  final int mangaId;
  final String volume;
  final String number;
  final int? branchId;
  final DownloadQueueStatus status;
  final int attempts;
  final String? error;
  final DateTime addedAt;

  const DownloadQueueItem({
    required this.slugUrl,
    required this.mangaId,
    required this.volume,
    required this.number,
    required this.branchId,
    required this.status,
    required this.attempts,
    required this.error,
    required this.addedAt,
  });

  String get id => '$mangaId::$volume::$number';

  bool get isActive =>
      status == DownloadQueueStatus.queued ||
      status == DownloadQueueStatus.downloading;

  DownloadQueueItem copyWith({
    DownloadQueueStatus? status,
    int? attempts,
    String? error,
    bool clearError = false,
  }) {
    return DownloadQueueItem(
      slugUrl: slugUrl,
      mangaId: mangaId,
      volume: volume,
      number: number,
      branchId: branchId,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      error: clearError ? null : (error ?? this.error),
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'slugUrl': slugUrl,
        'mangaId': mangaId,
        'volume': volume,
        'number': number,
        'branchId': branchId,
        'status': status.name,
        'attempts': attempts,
        'error': error,
        'addedAt': addedAt.toIso8601String(),
      };

  factory DownloadQueueItem.fromJson(Map<String, dynamic> json) {
    final rawAddedAt = json['addedAt'];
    return DownloadQueueItem(
      slugUrl: json['slugUrl'] is String ? json['slugUrl'] as String : '',
      mangaId: json['mangaId'] is num ? (json['mangaId'] as num).toInt() : 0,
      volume: json['volume'] is String ? json['volume'] as String : '',
      number: json['number'] is String ? json['number'] as String : '',
      branchId: json['branchId'] is num ? (json['branchId'] as num).toInt() : null,
      status: DownloadQueueStatus.parse(json['status'] is String ? json['status'] as String : null),
      attempts: json['attempts'] is num ? (json['attempts'] as num).toInt() : 0,
      error: json['error'] is String && (json['error'] as String).isNotEmpty
          ? json['error'] as String
          : null,
      addedAt: rawAddedAt is String
          ? (DateTime.tryParse(rawAddedAt) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

class DownloadStorageCleanup {
  final int deletedChapters;
  final int freedBytes;

  const DownloadStorageCleanup({
    required this.deletedChapters,
    required this.freedBytes,
  });

  static const DownloadStorageCleanup none =
      DownloadStorageCleanup(deletedChapters: 0, freedBytes: 0);
}

/// Sequential chapter download queue with SQLite-backed persistence.
///
/// All chapters are downloaded one after another so the Rust engine never runs
/// competing downloads and the progress notification always has a single source
/// of truth.
class DownloadQueueService {
  DownloadQueueService._();

  static final DownloadQueueService instance = DownloadQueueService._();

  static const String _storageKey = 'download_queue';

  final ValueNotifier<List<DownloadQueueItem>> queue =
      ValueNotifier<List<DownloadQueueItem>>(const <DownloadQueueItem>[]);

  final _DownloadProgressNotification _notification =
      _DownloadProgressNotification();

  ProviderContainer? _container;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  ProviderSubscription<bool>? _wifiOnlySubscription;
  bool _processing = false;
  bool _dirty = false;
  bool _restored = false;
  bool _unmeteredConnection = true;
  bool? _isRu;

  List<DownloadQueueItem> get items => queue.value;

  List<DownloadQueueItem> get pendingItems =>
      items.where((item) => item.status == DownloadQueueStatus.queued).toList();

  List<DownloadQueueItem> get waitingForWifiItems => items
      .where((item) => item.status == DownloadQueueStatus.waitingForWifi)
      .toList();

  List<DownloadQueueItem> get failedItems =>
      items.where((item) => item.status == DownloadQueueStatus.failed).toList();

  List<DownloadQueueItem> get completedItems => items
      .where((item) => item.status == DownloadQueueStatus.completed)
      .toList();

  bool get isProcessing => _processing;

  DownloadQueueItem? itemFor({
    required int mangaId,
    required String volume,
    required String number,
  }) {
    for (final item in items) {
      if (item.mangaId == mangaId &&
          item.volume == volume &&
          item.number == number) {
        return item;
      }
    }
    return null;
  }

  /// Restores the persisted queue and resumes it. Must be called once after the
  /// first frame so the provider container and the database are ready.
  Future<void> restoreAndResume(WidgetRef ref) async {
    _resolveContainer(ref);
    _attachConnectivity();
    _attachSettingsListener();

    if (_restored) {
      unawaited(_process());
      return;
    }
    _restored = true;

    final restored = await _loadPersisted();
    if (restored.isNotEmpty) {
      _setItems([
        for (final item in restored)
          // A chapter left in "downloading" was interrupted by a process exit.
          item.status == DownloadQueueStatus.downloading
              ? item.copyWith(status: DownloadQueueStatus.queued, clearError: true)
              : item,
      ]);
      await _persist();
    }

    if (waitingForWifiItems.isNotEmpty && await _allowedToDownload()) {
      await _resumeWaitingItems();
    }
    unawaited(_process());
  }

  Future<void> enqueue({
    required WidgetRef ref,
    required String slugUrl,
    required int mangaId,
    required List<ChapterDownloadRequest> chapters,
  }) async {
    _resolveContainer(ref);
    _attachConnectivity();
    _attachSettingsListener();

    final next = List<DownloadQueueItem>.from(items);
    var changed = false;

    for (final chapter in chapters) {
      if (await _isAlreadyDownloaded(mangaId, chapter.volume, chapter.number)) {
        continue;
      }

      final index = next.indexWhere(
        (item) =>
            item.mangaId == mangaId &&
            item.volume == chapter.volume &&
            item.number == chapter.number,
      );

      if (index >= 0) {
        final current = next[index];
        if (current.isActive ||
            current.status == DownloadQueueStatus.waitingForWifi) {
          continue;
        }
        // Failed or completed leftovers are recycled so the queue never holds
        // two rows for the same chapter.
        next[index] = current.copyWith(
          status: DownloadQueueStatus.queued,
          attempts: 0,
          clearError: true,
        );
        changed = true;
        continue;
      }

      next.add(DownloadQueueItem(
        slugUrl: slugUrl,
        mangaId: mangaId,
        volume: chapter.volume,
        number: chapter.number,
        branchId: chapter.branchId,
        status: DownloadQueueStatus.queued,
        attempts: 0,
        error: null,
        addedAt: DateTime.now(),
      ));
      changed = true;
    }

    if (!changed) return;
    _setItems(next);
    await _persist();
    unawaited(_process());
  }

  Future<void> retry(DownloadQueueItem item) async {
    final current = _itemById(item.id);
    if (current == null || current.status == DownloadQueueStatus.downloading) {
      return;
    }
    _replace(
      item.id,
      current.copyWith(
        status: DownloadQueueStatus.queued,
        attempts: 0,
        clearError: true,
      ),
    );
    await _persist();
    unawaited(_process());
  }

  Future<void> retryAllFailed() async {
    if (failedItems.isEmpty) return;
    _setItems([
      for (final item in items)
        item.status == DownloadQueueStatus.failed
            ? item.copyWith(
                status: DownloadQueueStatus.queued,
                attempts: 0,
                clearError: true,
              )
            : item,
    ]);
    await _persist();
    unawaited(_process());
  }

  Future<void> remove(DownloadQueueItem item) async {
    if (_itemById(item.id) == null) return;
    _setItems([for (final entry in items) if (entry.id != item.id) entry]);
    await _persist();
  }

  Future<void> clearCompleted() async {
    if (completedItems.isEmpty) return;
    _setItems([
      for (final item in items)
        if (item.status != DownloadQueueStatus.completed) item,
    ]);
    await _persist();
  }

  /// Deletes every downloaded chapter that is marked as fully read.
  Future<DownloadStorageCleanup> freeUpSpace() => _deleteReadChapters();

  /// Stops background work. Safe to call from `dispose`.
  Future<void> detach() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _wifiOnlySubscription?.close();
    _wifiOnlySubscription = null;
    await _notification.cancel();
  }

  Future<void> _process() async {
    if (_processing) {
      _dirty = true;
      return;
    }
    _processing = true;
    try {
      do {
        _dirty = false;
        // Turning the Wi-Fi-only policy off must release chapters parked earlier.
        if (waitingForWifiItems.isNotEmpty &&
            !_read<bool>(wifiOnlyDownloadsProvider, false)) {
          _setItems([
            for (final item in items)
              item.status == DownloadQueueStatus.waitingForWifi
                  ? item.copyWith(status: DownloadQueueStatus.queued, clearError: true)
                  : item,
          ]);
          await _persist();
        }
        while (true) {
          final next = _nextQueued();
          if (next == null) break;

          if (!await _allowedToDownload()) {
            _markQueuedAsWaiting();
            await _persist();
            break;
          }

          await _ensureLocale();
          try {
            await _run(next);
          } catch (error) {
            await _markFailed(next, _describeError(error));
          }
        }
      } while (_dirty);
    } catch (error) {
      debugPrint('Download queue failed: $error');
    } finally {
      _processing = false;
      if (!_hasActiveWork) {
        unawaited(_notification.cancel());
      }
    }
  }

  Future<void> _run(DownloadQueueItem item) async {
    final started = _replace(
      item.id,
      item.copyWith(
        status: DownloadQueueStatus.downloading,
        attempts: item.attempts + 1,
        clearError: true,
      ),
    );
    if (started == null) return;
    await _persist();

    unawaited(_notification.show(
      isRu: _isRu ?? true,
      slugUrl: started.slugUrl,
      volume: started.volume,
      number: started.number,
      currentPage: 0,
      totalPages: 0,
      force: true,
    ));

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final progress = await _downloadChapter(started, appDir.path);
      if (progress == null) {
        await _markFailed(started, null);
        return;
      }
      switch (progress.state) {
        case DownloadState.completed:
          await _markCompleted(started);
        case DownloadState.failed:
          await _markFailed(started, progress.errorMessage);
        case DownloadState.queued:
        case DownloadState.downloading:
        case DownloadState.waitingForNetwork:
        case DownloadState.paused:
          // The stream ended without a terminal state: the global cancel flag
          // was raised, so the chapter has to be retried by the user.
          await _markFailed(started, null);
      }
    } catch (error) {
      await _markFailed(started, _describeError(error));
    }
  }

  /// Resolves to the last emitted progress, or `null` when the engine stopped
  /// without reporting a terminal state.
  Future<DownloadProgress?> _downloadChapter(
    DownloadQueueItem item,
    String appDir,
  ) {
    final completer = Completer<DownloadProgress?>();
    DownloadProgress? last;

    final subscription = rust_download.startChapterDownload(
      slugUrl: item.slugUrl,
      mangaId: item.mangaId,
      chapters: [
        ChapterDownloadRequest(
          volume: item.volume,
          number: item.number,
          branchId: item.branchId,
        ),
      ],
      appDir: appDir,
      concurrentImages: _read<int>(downloadConcurrencyImagesProvider, 10),
    ).listen(
      (progress) {
        last = progress;
        _applyProgress(progress);
        if (progress.state == DownloadState.completed ||
            progress.state == DownloadState.failed) {
          if (!completer.isCompleted) completer.complete(progress);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(last);
      },
    );

    return completer.future.whenComplete(subscription.cancel);
  }

  void _applyProgress(DownloadProgress progress) {
    final container = _container;
    if (container != null) {
      try {
        container.read(downloadProvider.notifier).addProgress(progress);
      } catch (error) {
        debugPrint('Unable to publish download progress: $error');
      }
    }

    if (progress.state == DownloadState.downloading) {
      unawaited(_notification.show(
        isRu: _isRu ?? true,
        slugUrl: progress.mangaSlug,
        volume: progress.chapterVolume,
        number: progress.chapterNumber,
        currentPage: progress.currentPage.toInt(),
        totalPages: progress.totalPages.toInt(),
      ));
    }
  }

  Future<void> _markCompleted(DownloadQueueItem item) async {
    _replace(
      item.id,
      item.copyWith(status: DownloadQueueStatus.completed, clearError: true),
    );
    await _persist();

    try {
      await _autoCleanup(justCompleted: item);
    } catch (error) {
      debugPrint('Download cleanup failed: $error');
    }

    _bumpCompletionTick();
  }

  Future<void> _markFailed(DownloadQueueItem item, String? error) async {
    _replace(
      item.id,
      item.copyWith(
        status: DownloadQueueStatus.failed,
        error: _cleanError(error),
        clearError: error == null || error.trim().isEmpty,
      ),
    );
    await _persist();
  }

  Future<void> _autoCleanup({required DownloadQueueItem justCompleted}) async {
    if (_read<bool>(autoDeleteReadChaptersProvider, false)) {
      await _deleteReadChapters(protect: justCompleted);
    }
    await _enforceStorageLimit(protect: justCompleted);
  }

  Future<DownloadStorageCleanup> _deleteReadChapters(
      {DownloadQueueItem? protect}) async {
    final groups = await rust_storage.getDownloadedMangaGroups();
    var deleted = 0;
    var freed = 0;

    for (final group in groups) {
      final readKeys = await _completedChapterKeys(group.mangaId);
      for (final chapter in group.chapters) {
        if (!readKeys.contains('${chapter.volume}|${chapter.number}')) continue;
        if (_isProtected(chapter, protect)) continue;

        final sizeBytes = await _chapterSize(chapter, group);
        try {
          await rust_storage.deleteDownloadedChapter(
            mangaId: chapter.mangaId,
            volume: chapter.volume,
            number: chapter.number,
          );
        } catch (error) {
          debugPrint('Unable to delete read chapter: $error');
          continue;
        }
        deleted += 1;
        freed += sizeBytes;
      }
    }

    return DownloadStorageCleanup(deletedChapters: deleted, freedBytes: freed);
  }

  Future<DownloadStorageCleanup> _enforceStorageLimit(
      {DownloadQueueItem? protect}) async {
    final limitMb = _read<int>(downloadsStorageLimitProvider, 0);
    if (limitMb <= 0) return DownloadStorageCleanup.none;

    final limitBytes = limitMb * 1024 * 1024;
    final groups = await rust_storage.getDownloadedMangaGroups();

    var total = 0;
    for (final group in groups) {
      total += group.totalSizeBytes.toInt();
    }
    // Size totals come straight from the database; per-chapter file stats are
    // only paid for when the limit is actually exceeded.
    if (total <= limitBytes) return DownloadStorageCleanup.none;

    final chapters = <_DownloadedChapter>[];
    for (final group in groups) {
      final readKeys = await _completedChapterKeys(group.mangaId);
      for (final chapter in group.chapters) {
        chapters.add(_DownloadedChapter(
          chapter: chapter,
          sizeBytes: await _chapterSize(chapter, group),
          isRead: readKeys.contains('${chapter.volume}|${chapter.number}'),
        ));
      }
    }

    // Oldest first: the least recently fetched chapters are the cheapest to lose.
    chapters.sort(
      (a, b) => a.chapter.downloadedAt.compareTo(b.chapter.downloadedAt),
    );

    var deleted = 0;
    var freed = 0;

    Future<void> deleteChapter(_DownloadedChapter entry) async {
      if (entry.deleted || _isProtected(entry.chapter, protect)) return;
      try {
        await rust_storage.deleteDownloadedChapter(
          mangaId: entry.chapter.mangaId,
          volume: entry.chapter.volume,
          number: entry.chapter.number,
        );
      } catch (error) {
        debugPrint('Unable to delete chapter for storage limit: $error');
        return;
      }
      entry.deleted = true;
      deleted += 1;
      freed += entry.sizeBytes;
      total -= entry.sizeBytes;
    }

    for (final entry in chapters.where((entry) => entry.isRead)) {
      if (total <= limitBytes) break;
      await deleteChapter(entry);
    }
    if (total > limitBytes) {
      for (final entry in chapters) {
        if (total <= limitBytes) break;
        await deleteChapter(entry);
      }
    }

    return DownloadStorageCleanup(deletedChapters: deleted, freedBytes: freed);
  }

  Future<int> _chapterSize(
    DownloadedChapterInfo chapter,
    DownloadedMangaGroup group,
  ) async {
    try {
      final file = File(chapter.downloadPath);
      if (await file.exists()) return await file.length();
    } catch (_) {
      // Falls back to a per-chapter average below.
    }
    final count = group.chapters.length;
    if (count == 0) return 0;
    return group.totalSizeBytes.toInt() ~/ count;
  }

  Future<Set<String>> _completedChapterKeys(int mangaId) async {
    try {
      final history = await rust_storage.getChapterHistory(mangaId: mangaId);
      return {
        for (final entry in history)
          if (entry.isCompleted) '${entry.volume}|${entry.number}',
      };
    } catch (error) {
      debugPrint('Unable to read chapter history: $error');
      return <String>{};
    }
  }

  bool _isProtected(DownloadedChapterInfo chapter, DownloadQueueItem? protect) {
    if (protect == null) return false;
    return chapter.mangaId == protect.mangaId &&
        chapter.volume == protect.volume &&
        chapter.number == protect.number;
  }

  Future<void> _ensureLocale() async {
    if (_isRu != null) return;
    try {
      final configured = await rust_storage.getSetting(key: 'locale');
      if (configured == 'ru') {
        _isRu = true;
        return;
      }
      if (configured == 'en') {
        _isRu = false;
        return;
      }
    } catch (_) {
      // Falls through to the system locale.
    }
    try {
      _isRu = Platform.localeName.toLowerCase().startsWith('ru');
    } catch (_) {
      _isRu = true;
    }
  }

  Future<bool> _allowedToDownload() async {
    final wifiOnly = _read<bool>(wifiOnlyDownloadsProvider, false);
    if (!wifiOnly) return true;
    await _refreshConnectivity();
    return _unmeteredConnection;
  }

  void _attachConnectivity() {
    if (_connectivitySubscription != null) return;
    try {
      _connectivitySubscription =
          Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
      unawaited(_refreshConnectivity());
    } catch (error) {
      debugPrint('Connectivity stream unavailable: $error');
    }
  }

  void _attachSettingsListener() {
    final container = _container;
    if (container == null || _wifiOnlySubscription != null) return;
    try {
      _wifiOnlySubscription = container.listen<bool>(
        wifiOnlyDownloadsProvider,
        (_, enabled) {
          if (!enabled) unawaited(_process());
        },
      );
    } catch (error) {
      debugPrint('Unable to watch download settings: $error');
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hadUnmetered = _unmeteredConnection;
    _unmeteredConnection = _isUnmetered(results);
    if (_unmeteredConnection && !hadUnmetered) {
      unawaited(_resumeWaitingItems());
    }
  }

  Future<void> _refreshConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hadUnmetered = _unmeteredConnection;
      _unmeteredConnection = _isUnmetered(results);
      if (_unmeteredConnection && !hadUnmetered) {
        await _resumeWaitingItems();
      }
    } catch (error) {
      debugPrint('Unable to read connectivity state: $error');
    }
  }

  /// Wired ethernet counts as unmetered on desktop, where no Wi-Fi radio exists.
  bool _isUnmetered(List<ConnectivityResult> results) =>
      results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet);

  Future<void> _resumeWaitingItems() async {
    if (waitingForWifiItems.isEmpty) return;
    _setItems([
      for (final item in items)
        item.status == DownloadQueueStatus.waitingForWifi
            ? item.copyWith(status: DownloadQueueStatus.queued, clearError: true)
            : item,
    ]);
    await _persist();
    unawaited(_process());
  }

  void _markQueuedAsWaiting() {
    if (pendingItems.isEmpty) return;
    _setItems([
      for (final item in items)
        item.status == DownloadQueueStatus.queued
            ? item.copyWith(status: DownloadQueueStatus.waitingForWifi)
            : item,
    ]);
  }

  bool get _hasActiveWork => items
      .any((item) => item.status == DownloadQueueStatus.queued ||
          item.status == DownloadQueueStatus.downloading);

  DownloadQueueItem? _nextQueued() {
    for (final item in items) {
      if (item.status == DownloadQueueStatus.queued) return item;
    }
    return null;
  }

  DownloadQueueItem? _itemById(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  DownloadQueueItem? _replace(String id, DownloadQueueItem updated) {
    var found = false;
    final next = <DownloadQueueItem>[];
    for (final item in items) {
      if (item.id == id) {
        next.add(updated);
        found = true;
      } else {
        next.add(item);
      }
    }
    if (!found) return null;
    _setItems(next);
    return updated;
  }

  void _setItems(List<DownloadQueueItem> next) {
    queue.value = List<DownloadQueueItem>.unmodifiable(next);
  }

  void _bumpCompletionTick() {
    final container = _container;
    if (container == null) return;
    try {
      container.read(downloadCompletionTickProvider.notifier).state += 1;
    } catch (error) {
      debugPrint('Unable to bump download completion tick: $error');
    }
  }

  void _resolveContainer(WidgetRef ref) {
    if (_container != null) return;
    // WidgetRef is implemented by the widget's element, which is also the
    // BuildContext that owns the provider container. Reading through the
    // container (not the ref) keeps the queue alive after the page is popped.
    if (ref is! ConsumerStatefulElement) return;
    try {
      _container = ProviderScope.containerOf(ref, listen: false);
    } catch (error) {
      debugPrint('Unable to locate provider container: $error');
    }
  }

  T _read<T>(ProviderListenable<T> provider, T fallback) {
    final container = _container;
    if (container == null) return fallback;
    try {
      return container.read(provider);
    } catch (error) {
      debugPrint('Unable to read provider: $error');
      return fallback;
    }
  }

  Future<bool> _isAlreadyDownloaded(
    int mangaId,
    String volume,
    String number,
  ) async {
    try {
      return await rust_storage.isChapterDownloaded(
        mangaId: mangaId,
        volume: volume,
        number: number,
      );
    } catch (error) {
      debugPrint('Unable to check downloaded state: $error');
      return false;
    }
  }

  Future<List<DownloadQueueItem>> _loadPersisted() async {
    try {
      final raw = await rust_storage.getSetting(key: _storageKey);
      if (raw == null || raw.trim().isEmpty) return const <DownloadQueueItem>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <DownloadQueueItem>[];

      final restored = <DownloadQueueItem>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          restored.add(
            DownloadQueueItem.fromJson(Map<String, dynamic>.from(entry)),
          );
        } catch (error) {
          debugPrint('Skipping unreadable queue entry: $error');
        }
      }
      return restored;
    } catch (error) {
      debugPrint('Unable to restore download queue: $error');
      return const <DownloadQueueItem>[];
    }
  }

  Future<void> _persist() async {
    try {
      final encoded = jsonEncode([for (final item in items) item.toJson()]);
      await rust_storage.setSetting(key: _storageKey, value: encoded);
    } catch (error) {
      debugPrint('Unable to persist download queue: $error');
    }
  }

  String? _cleanError(String? error) {
    if (error == null) return null;
    final trimmed = error.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > 240 ? '${trimmed.substring(0, 240)}...' : trimmed;
  }

  String _describeError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }
}

class _DownloadedChapter {
  _DownloadedChapter({
    required this.chapter,
    required this.sizeBytes,
    required this.isRead,
  });

  final DownloadedChapterInfo chapter;
  final int sizeBytes;
  final bool isRead;
  bool deleted = false;
}

/// Single ongoing notification that mirrors the chapter currently downloading.
class _DownloadProgressNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _notificationId = 9101;
  static const Duration _minInterval = Duration(milliseconds: 500);

  bool _initialized = false;
  bool _unavailable = false;
  DateTime? _lastShownAt;
  String? _lastSignature;

  bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> show({
    required bool isRu,
    required String slugUrl,
    required String volume,
    required String number,
    required int currentPage,
    required int totalPages,
    bool force = false,
  }) async {
    if (!_supported || _unavailable) return;

    final maxProgress = totalPages > 0 ? totalPages : 1;
    final progress = currentPage.clamp(0, maxProgress);
    final signature = '$slugUrl|$volume|$number|$progress|$maxProgress';
    if (!force && signature == _lastSignature) return;

    final now = DateTime.now();
    final lastShownAt = _lastShownAt;
    if (!force && lastShownAt != null && now.difference(lastShownAt) < _minInterval) {
      return;
    }

    _lastShownAt = now;
    _lastSignature = signature;
    final notificationStrings = NotificationStrings(isRu);

    try {
      if (!await _ensureInitialized()) return;

      final androidDetails = AndroidNotificationDetails(
        'downloads',
        notificationStrings.downloadChannelName,
        channelDescription: notificationStrings.downloadChannelDescription,
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: maxProgress,
        progress: progress,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        icon: '@drawable/ic_notification',
        color: AppTokens.accent,
      );

      final body = notificationStrings.downloadBody(volume, number, progress, maxProgress);

      await _plugin.show(
        _notificationId,
        notificationStrings.downloadTitle,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (error) {
      _unavailable = true;
      debugPrint('Download notification unavailable: $error');
    }
  }

  Future<void> cancel() async {
    _lastShownAt = null;
    _lastSignature = null;
    if (!_supported) return;
    try {
      await _plugin.cancel(_notificationId);
    } catch (error) {
      debugPrint('Unable to cancel download notification: $error');
    }
  }

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    if (_unavailable) return false;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      _initialized = true;
      return true;
    } catch (error) {
      _unavailable = true;
      debugPrint('Unable to initialize download notifications: $error');
      return false;
    }
  }
}