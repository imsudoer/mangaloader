import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/providers/download_provider.dart';
import 'package:mangaloader/src/rust/api/download_engine.dart' as rust_download;
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/cbz_export.dart' as rust_cbz;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/services/streak_notification_service.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

enum ReadMode { ltr, rtl, vertical }
enum ReadBgColor { black, darkGrey, white }
enum ReadBoxFit { contain, cover, fitWidth }
enum ReadColorFilter { none, invert, sepia }
enum ReadSharpenMode { off, subtle, high }

class ReaderPage extends ConsumerStatefulWidget {
  final String slugUrl;
  final String volume;
  final String number;
  final int? branchId;
  final String? localCbzPath;
  
  const ReaderPage({
    super.key, 
    required this.slugUrl, 
    required this.volume, 
    required this.number,
    this.branchId,
    this.localCbzPath,
  });

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final ValueNotifier<bool> _showControlsNotifier = ValueNotifier<bool>(false);
  ReadMode _readMode = ReadMode.vertical;
  ReadBgColor _bgColor = ReadBgColor.black;
  final ReadBoxFit _boxFit = ReadBoxFit.fitWidth;
  ReadColorFilter _filterMode = ReadColorFilter.none;
  ReadSharpenMode _sharpenMode = ReadSharpenMode.off;
  
  // Crop borders
  bool _cropBorders = false;
  double _cropPercent = 3.0; // 3% margin crop
  
  // Smart HUD
  final bool _showHud = true;
  final ValueNotifier<int> _pageIndexNotifier = ValueNotifier<int>(0);

  double _zoomLevel = 1.0;
  double _brightness = 1.0;
  bool _isFullscreen = false;
  bool _isAutoScrolling = false;
  double _autoScrollSpeed = 1.0;
  Timer? _autoScrollTimer;
  
  bool _isLoading = true;
  bool _isDownloaded = false;
  String? _errorMessage;
  int _totalPages = 0;
  String _cbzPath = "";
  
  // For online reading
  List<ChapterPage> _onlinePages = [];
  
  // Memory cache for CBZ page bytes
  final Map<int, Uint8List> _pageCache = {};
  List<GlobalKey> _pageKeys = [];
  
  int _currentPageIndex = 0;
  PageController? _pageController;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  bool _isJumping = false;
  
  Timer? _saveTimer;
  int _mangaId = 0;
  String _chapterTitle = "";
  
  // Chapter info for navigation & seamless transition
  Chapter? _prevChapter;
  Chapter? _nextChapter;
  String? _prevLocalCbzPath;
  String? _nextLocalCbzPath;
  List<Chapter> _allChapters = [];
  bool _isNextChapterPrefetched = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onVerticalScroll);
    _chapterTitle = widget.localCbzPath != null
        ? widget.localCbzPath!.split(Platform.pathSeparator).last
        : 'Том ${widget.volume} Гл ${widget.number}';
    _updateWindowTitle();
    _loadChapter();
  }

  int _findVisiblePageIndex() {
    if (_totalPages <= 1) return 0;
    final screenH = MediaQuery.of(context).size.height;
    final targetY = screenH * 0.35;

    for (int i = 0; i < _totalPages && i < _pageKeys.length; i++) {
      final ctx = _pageKeys[i].currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final pos = box.localToGlobal(Offset.zero);
          if (pos.dy + box.size.height > targetY) {
            return i;
          }
        }
      }
    }
    return _currentPageIndex;
  }

  void _onVerticalScroll() {
    if (_readMode != ReadMode.vertical || !_scrollController.hasClients || _totalPages <= 1) return;
    if (_isJumping) return;
    
    final currentVisible = _findVisiblePageIndex();
    
    if (currentVisible != _currentPageIndex) {
      _currentPageIndex = currentVisible;
      _pageIndexNotifier.value = currentVisible;
      _scheduleSaveProgress();
    }

    // Smart Next Chapter Preload (trigger when near end of chapter)
    if (_nextChapter != null && !_isNextChapterPrefetched) {
      final offset = _scrollController.offset;
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent > 0 && (offset >= maxExtent * 0.75 || maxExtent - offset < 2500)) {
        _isNextChapterPrefetched = true;
        _prefetchNextChapter(_nextChapter!);
      }
    }
  }

  void _updateWindowTitle() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setTitle("Manga Loader - $_chapterTitle");
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onVerticalScroll);
    _stopAutoScroll();
    _saveTimer?.cancel();
    _showControlsNotifier.dispose();
    _pageIndexNotifier.dispose();
    if (_mangaId > 0) {
      rust_storage.saveReadingProgress(
        progress: ReadingPosition(
          mangaId: _mangaId,
          chapterVolume: widget.volume,
          chapterNumber: widget.number,
          pageIndex: _currentPageIndex,
          scrollPosition: 0.0,
          lastReadAt: DateTime.now().toIso8601String(),
        ),
      );
    }
    _pageController?.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setTitle("Manga Loader");
      if (_isFullscreen) {
        windowManager.setFullScreen(false);
      }
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _loadChapter() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    
    try {
      if (widget.localCbzPath != null && widget.localCbzPath!.isNotEmpty) {
        _cbzPath = widget.localCbzPath!;
        _isDownloaded = true;
        _totalPages = await rust_cbz.getCbzPageCount(cbzPath: _cbzPath);
        if (_totalPages == 0) {
          throw Exception("Не удалось прочитать страницы из локального CBZ файла");
        }
      } else {
        if (widget.slugUrl.isNotEmpty) {
          var cached = await rust_storage.getCachedManga(slugUrl: widget.slugUrl);
          if (cached == null) {
            try {
              final remote = await rust_api.getMangaDetails(slugUrl: widget.slugUrl);
              _mangaId = remote.id;
            } catch (_) {}
          } else {
            _mangaId = cached.id;
          }

          if (_mangaId > 0) {
            // Auto-enroll into library as reading if not already in any category
            try {
              final existingType = await rust_storage.getMangaListType(mangaId: _mangaId);
              if (existingType == null || existingType.isEmpty) {
                await rust_storage.addToList(mangaId: _mangaId, listType: 'reading');
              }
            } catch (e) {
              debugPrint("Auto add to library error: $e");
            }

            _isDownloaded = await rust_storage.isChapterDownloaded(
              mangaId: _mangaId, volume: widget.volume, number: widget.number
            );
            
            final progress = await rust_storage.getReadingProgress(mangaId: _mangaId);
            if (progress != null && progress.chapterVolume == widget.volume && progress.chapterNumber == widget.number) {
              _currentPageIndex = progress.pageIndex.toInt();
            }
          }
        }

        final appDir = await getApplicationDocumentsDirectory();
        _cbzPath = '${appDir.path}/manga/${widget.slugUrl}/v${widget.volume}_c${widget.number}.cbz';

        if (File(_cbzPath).existsSync()) {
          try {
            _totalPages = await rust_cbz.getCbzPageCount(cbzPath: _cbzPath);
            if (_totalPages > 0) {
              _isDownloaded = true;
            } else {
              _isDownloaded = false;
            }
          } catch (_) {
            _isDownloaded = false;
          }
        } else {
          _isDownloaded = false;
        }
        
        if (!_isDownloaded) {
          _onlinePages = await rust_api.getChapterPages(
            slugUrl: widget.slugUrl, 
            volume: widget.volume, 
            number: widget.number,
            branchId: widget.branchId,
          );
          _totalPages = _onlinePages.length;
          if (_totalPages > 0) {
            _preloadImages(_currentPageIndex);
          }
        }
        
        _findNextChapter();
      }
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint("Error loading chapter: $e");
    }

    if (_currentPageIndex >= _totalPages) {
      _currentPageIndex = 0;
    }

    _pageKeys = List.generate(_totalPages, (i) => GlobalKey(debugLabel: 'page_$i'));

    // Create PageController with correct initial page for horizontal modes
    _pageController?.dispose();
    _pageController = PageController(initialPage: _currentPageIndex);
    _pageIndexNotifier.value = _currentPageIndex;

    setState(() => _isLoading = false);
    
    // For vertical mode, scroll to saved position after first frame
    if (_totalPages > 0 && _currentPageIndex > 0 && _readMode == ReadMode.vertical) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToPageIndex(_currentPageIndex);
      });
    }
  }

  void _jumpToPageIndex(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _totalPages) return;
    _currentPageIndex = targetIndex;
    _pageIndexNotifier.value = targetIndex;
    
    if (_readMode != ReadMode.vertical) {
      if (_pageController != null && _pageController!.hasClients) {
        _pageController!.jumpToPage(targetIndex);
      }
    } else {
      _isJumping = true;
      if (targetIndex < _pageKeys.length) {
        final ctx = _pageKeys[targetIndex].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx, 
            alignment: 0.0, 
            duration: Duration.zero,
          );
        } else if (_scrollController.hasClients) {
          final maxExtent = _scrollController.position.maxScrollExtent;
          if (maxExtent > 0) {
            final ratio = targetIndex / (_totalPages > 1 ? (_totalPages - 1) : 1);
            _scrollController.jumpTo((maxExtent * ratio).clamp(0.0, maxExtent));
          }
        }
      }
      
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _isJumping = false;
      });
    }
    _scheduleSaveProgress();
  }

  Future<void> _findNextChapter() async {
    try {
      if (widget.slugUrl.isNotEmpty) {
        List<Chapter> chapters = [];
        try {
          chapters = await rust_api.getChapters(slugUrl: widget.slugUrl);
        } catch (_) {
          if (_mangaId > 0) {
            chapters = await rust_storage.getCachedChapters(mangaId: _mangaId);
          }
        }
        if (chapters.isEmpty && _mangaId > 0) {
          chapters = await rust_storage.getCachedChapters(mangaId: _mangaId);
        }

        final sorted = List<Chapter>.from(chapters);
        sorted.sort((a, b) {
          final va = double.tryParse(a.volume) ?? 0.0;
          final vb = double.tryParse(b.volume) ?? 0.0;
          if (va != vb) return va.compareTo(vb);
          final na = double.tryParse(a.number) ?? 0.0;
          final nb = double.tryParse(b.number) ?? 0.0;
          return na.compareTo(nb);
        });

        _allChapters = sorted;

        final currentVol = double.tryParse(widget.volume) ?? 0.0;
        final currentNum = double.tryParse(widget.number) ?? 0.0;

        final currentIndex = _allChapters.indexWhere((c) {
          final v = double.tryParse(c.volume) ?? 0.0;
          final n = double.tryParse(c.number) ?? 0.0;
          return (v == currentVol || c.volume == widget.volume) &&
                 (n == currentNum || c.number == widget.number);
        });

        if (currentIndex != -1) {
          if (currentIndex > 0) {
            _prevChapter = _allChapters[currentIndex - 1];
          } else {
            _prevChapter = null;
          }

          if (currentIndex + 1 < _allChapters.length) {
            final next = _allChapters[currentIndex + 1];
            _nextChapter = next;
            _prefetchNextChapter(next);
          } else {
            _nextChapter = null;
          }
        } else if (_allChapters.isNotEmpty) {
          final prevList = _allChapters.where((c) {
            final v = double.tryParse(c.volume) ?? 0.0;
            final n = double.tryParse(c.number) ?? 0.0;
            return (v < currentVol) || (v == currentVol && n < currentNum);
          }).toList();
          if (prevList.isNotEmpty) {
            _prevChapter = prevList.last;
          } else {
            _prevChapter = null;
          }

          final nextList = _allChapters.where((c) {
            final v = double.tryParse(c.volume) ?? 0.0;
            final n = double.tryParse(c.number) ?? 0.0;
            return (v > currentVol) || (v == currentVol && n > currentNum);
          }).toList();
          if (nextList.isNotEmpty) {
            _nextChapter = nextList.first;
            _prefetchNextChapter(_nextChapter!);
          } else {
            _nextChapter = null;
          }
        }
      } else if (widget.localCbzPath != null && widget.localCbzPath!.isNotEmpty) {
        final file = File(widget.localCbzPath!);
        final dir = file.parent;
        if (dir.existsSync()) {
          final files = dir.listSync().whereType<File>().where((f) {
            final ext = f.path.split('.').last.toLowerCase();
            return ext == 'cbz' || ext == 'zip';
          }).toList();

          files.sort((a, b) => a.path.compareTo(b.path));
          final idx = files.indexWhere((f) => f.path == file.path);
          if (idx != -1) {
            if (idx > 0) {
              _prevLocalCbzPath = files[idx - 1].path;
            }
            if (idx + 1 < files.length) {
              _nextLocalCbzPath = files[idx + 1].path;
            }
          }
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  bool _smartDownloadTriggered = false;

  Future<void> _checkSmartAutoDownload() async {
    if (_smartDownloadTriggered || widget.slugUrl.isEmpty || _mangaId == 0) return;
    final autoCount = ref.read(smartAutoDownloadCountProvider);
    if (autoCount <= 0) return;

    _smartDownloadTriggered = true;
    try {
      final currentIndex = _allChapters.indexWhere(
        (c) => c.volume == widget.volume && c.number == widget.number,
      );
      if (currentIndex == -1) return;

      final requests = <ChapterDownloadRequest>[];
      for (int i = currentIndex + 1; i < _allChapters.length && requests.length < autoCount; i++) {
        final ch = _allChapters[i];
        if (ch.isPaid) continue;
        final isDownloaded = await rust_storage.isChapterDownloaded(
          mangaId: _mangaId,
          volume: ch.volume,
          number: ch.number,
        );
        if (!isDownloaded) {
          requests.add(ChapterDownloadRequest(
            volume: ch.volume,
            number: ch.number,
            branchId: ch.branchId,
          ));
        }
      }

      if (requests.isNotEmpty) {
        final appDir = await getApplicationDocumentsDirectory();
        final stream = rust_download.startChapterDownload(
          slugUrl: widget.slugUrl,
          mangaId: _mangaId,
          chapters: requests,
          appDir: appDir.path,
          concurrentImages: ref.read(downloadConcurrencyImagesProvider),
        );
        stream.listen((p) {
          ref.read(downloadProvider.notifier).addProgress(p);
        });
      }
    } catch (_) {}
  }

  Future<void> _prefetchNextChapter(Chapter next) async {
    _checkSmartAutoDownload();
    try {
      if (widget.slugUrl.isNotEmpty) {
        final isDownloaded = await rust_storage.isChapterDownloaded(
          mangaId: _mangaId, volume: next.volume, number: next.number
        );
        if (!isDownloaded) {
          final pages = await rust_api.getChapterPages(
            slugUrl: widget.slugUrl, 
            volume: next.volume, 
            number: next.number,
            branchId: next.branchId,
          );
          if (pages.isNotEmpty) {
            for (int i = 0; i < 3 && i < pages.length; i++) {
              final url = _resolveImageUrl(pages[i].url);
              if (mounted) {
                precacheImage(
                  CachedNetworkImageProvider(url, headers: const {'Referer': 'https://mangalib.org/'}), 
                  context
                );
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Color get _resolvedBgColor {
    switch (_bgColor) {
      case ReadBgColor.black: return Colors.black;
      case ReadBgColor.darkGrey: return const Color(0xFF181818);
      case ReadBgColor.white: return Colors.white;
    }
  }

  BoxFit get _resolvedBoxFit {
    switch (_boxFit) {
      case ReadBoxFit.contain: return BoxFit.contain;
      case ReadBoxFit.cover: return BoxFit.cover;
      case ReadBoxFit.fitWidth: return BoxFit.fitWidth;
    }
  }

  String _resolveImageUrl(String rawUrl) {
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    if (rawUrl.startsWith('//manga')) {
      return 'https://img3.cdnlibs.org${rawUrl.substring(1)}';
    }
    if (rawUrl.startsWith('//')) {
      return 'https:$rawUrl';
    }
    if (rawUrl.startsWith('/')) {
      return 'https://img3.cdnlibs.org$rawUrl';
    }
    return 'https://img3.cdnlibs.org/$rawUrl';
  }

  void _preloadImages(int startIndex) {
    if (_isDownloaded || _onlinePages.isEmpty) return;
    for (int i = startIndex; i < startIndex + 5 && i < _onlinePages.length; i++) {
      final url = _resolveImageUrl(_onlinePages[i].url);
      precacheImage(
        CachedNetworkImageProvider(url, headers: const {'Referer': 'https://mangalib.org/'}), 
        context
      );
    }
  }

  Future<Uint8List?> _getCbzPage(int index) async {
    if (_pageCache.containsKey(index)) return _pageCache[index];
    try {
      final bytes = await rust_cbz.readCbzPage(cbzPath: _cbzPath, pageIndex: index);
      final data = Uint8List.fromList(bytes);
      _pageCache[index] = data;
      _pageCache.removeWhere((k, _) => (k - index).abs() > 10);
      return data;
    } catch (e) {
      debugPrint("Error reading CBZ page $index: $e");
      return null;
    }
  }

  void _onPageChanged(int index) {
    _currentPageIndex = index.clamp(0, _totalPages > 0 ? _totalPages - 1 : 0);
    _pageIndexNotifier.value = _currentPageIndex;
    if (!_isDownloaded && index < _totalPages) _preloadImages(index);
    _scheduleSaveProgress();

    if (_nextChapter != null && !_isNextChapterPrefetched && index >= _totalPages - 3) {
      _isNextChapterPrefetched = true;
      _prefetchNextChapter(_nextChapter!);
    }
  }

  void _scheduleSaveProgress() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () async {
      if (_mangaId == 0 && widget.slugUrl.isNotEmpty) {
        final cached = await rust_storage.getCachedManga(slugUrl: widget.slugUrl);
        if (cached != null) {
          _mangaId = cached.id;
        } else {
          try {
            final remote = await rust_api.getMangaDetails(slugUrl: widget.slugUrl);
            _mangaId = remote.id;
            await rust_storage.saveManga(manga: remote);
          } catch (_) {}
        }
      }
      if (_mangaId == 0) return;

      try {
        final existingType = await rust_storage.getMangaListType(mangaId: _mangaId);
        if (existingType == null || existingType.isEmpty) {
          await rust_storage.addToList(mangaId: _mangaId, listType: "reading");
        }
      } catch (_) {}

      await rust_storage.saveReadingProgress(
        progress: ReadingPosition(
          mangaId: _mangaId,
          chapterVolume: widget.volume,
          chapterNumber: widget.number,
          pageIndex: _currentPageIndex,
          scrollPosition: 0.0,
          lastReadAt: DateTime.now().toIso8601String(),
        )
      );
      final isCompleted = _currentPageIndex >= _totalPages - 1;
      await rust_storage.markChapterRead(
        mangaId: _mangaId, 
        volume: widget.volume, 
        number: widget.number, 
        pageIndex: _currentPageIndex, 
        totalPages: _totalPages, 
        isCompleted: isCompleted,
      );
      if (isCompleted) {
        StreakNotificationService.scheduleDailyStreakReminder();
        if (ref.read(autoDeleteReadChaptersProvider) && _isDownloaded) {
          try {
            await rust_storage.deleteDownloadedChapter(
              mangaId: _mangaId,
              volume: widget.volume,
              number: widget.number,
            );
            _isDownloaded = false;
          } catch (e) {
            debugPrint("Auto-delete read chapter error: $e");
          }
        }
      }
    });
  }

  void _handleTap(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;
    final isRtl = _readMode == ReadMode.rtl;

    if (dx < width * 0.25) {
      if (_readMode != ReadMode.vertical) {
        if (isRtl) { _nextPageAction(); } 
        else if (_currentPageIndex > 0) { _pageController?.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut); }
      }
    } else if (dx > width * 0.75) {
      if (_readMode != ReadMode.vertical) {
        if (isRtl && _currentPageIndex > 0) { _pageController?.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut); }
        else if (!isRtl) { _nextPageAction(); }
      }
    } else {
      _showControlsNotifier.value = !_showControlsNotifier.value;
    }
  }

  void _nextPageAction() {
    if (_currentPageIndex < _totalPages - 1) {
      if (_readMode != ReadMode.vertical && _pageController != null && _pageController!.hasClients) {
        _pageController!.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _jumpToPageIndex(_currentPageIndex + 1);
      }
    } else {
      _showEndOfChapter();
    }
  }

  void _showEndOfChapter() {
    _stopAutoScroll();
    if (_nextChapter != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Перейти к следующей главе: Том ${_nextChapter!.volume} Гл ${_nextChapter!.number}?'),
          action: SnackBarAction(
            label: 'Читать',
            onPressed: () {
              final branchQ = _nextChapter!.branchId != null ? "?branchId=${_nextChapter!.branchId}" : "";
              context.pushReplacement('/read/${widget.slugUrl}/${_nextChapter!.volume}/${_nextChapter!.number}$branchQ');
            },
          ),
          duration: const Duration(seconds: 4),
        )
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы дочитали главу.')));
    }
  }

  void _zoomIn() {
    setState(() {
      _zoomLevel = (_zoomLevel + 0.25).clamp(0.5, 4.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoomLevel = (_zoomLevel - 0.25).clamp(0.5, 4.0);
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomLevel = 1.0;
    });
  }

  void _toggleFullscreen() async {
    setState(() => _isFullscreen = !_isFullscreen);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.setFullScreen(_isFullscreen);
    } else {
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  void _toggleAutoScroll() {
    setState(() {
      _isAutoScrolling = !_isAutoScrolling;
      if (_isAutoScrolling) {
        _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
          if (_scrollController.hasClients) {
            final nextOffset = _scrollController.offset + _autoScrollSpeed;
            if (nextOffset >= _scrollController.position.maxScrollExtent) {
              _stopAutoScroll();
              _showEndOfChapter();
            } else {
              _scrollController.jumpTo(nextOffset);
            }
          }
        });
      } else {
        _stopAutoScroll();
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (_isAutoScrolling) {
      setState(() => _isAutoScrolling = false);
    }
  }

  Future<void> _reloadImage(String pageUrl) async {
    try {
      await DefaultCacheManager().removeFile(pageUrl);
      PaintingBinding.instance.imageCache.evict(
        CachedNetworkImageProvider(pageUrl, headers: const {'Referer': 'https://mangalib.org/'}),
      );
    } catch (_) {}
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _reloadCurrentChapter() async {
    _pageCache.clear();
    for (final p in _onlinePages) {
      final url = _resolveImageUrl(p.url);
      try {
        await DefaultCacheManager().removeFile(url);
        PaintingBinding.instance.imageCache.evict(
          CachedNetworkImageProvider(url, headers: const {'Referer': 'https://mangalib.org/'}),
        );
      } catch (_) {}
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Кэш изображений главы сброшен, перезагрузка...')),
      );
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    
    final isRtl = _readMode == ReadMode.rtl;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.pageDown || event.logicalKey == LogicalKeyboardKey.space) {
      if (isRtl && _currentPageIndex > 0) {
        if (_readMode != ReadMode.vertical && _pageController != null && _pageController!.hasClients) {
          _pageController!.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        } else {
          _jumpToPageIndex(_currentPageIndex - 1);
        }
      } else {
        _nextPageAction();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.pageUp) {
      if (isRtl) {
        _nextPageAction();
      } else if (_currentPageIndex > 0) {
        if (_readMode != ReadMode.vertical && _pageController != null && _pageController!.hasClients) {
          _pageController!.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        } else {
          _jumpToPageIndex(_currentPageIndex - 1);
        }
      }
    } else if (event.logicalKey == LogicalKeyboardKey.equal || event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      _zoomIn();
    } else if (event.logicalKey == LogicalKeyboardKey.minus || event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _zoomOut();
    } else if (event.logicalKey == LogicalKeyboardKey.digit0 || event.logicalKey == LogicalKeyboardKey.numpad0) {
      _resetZoom();
    } else if (event.logicalKey == LogicalKeyboardKey.f11 || event.logicalKey == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (event.logicalKey == LogicalKeyboardKey.keyA) {
      if (_readMode == ReadMode.vertical) _toggleAutoScroll();
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      _jumpToPageIndex(0);
    } else if (event.logicalKey == LogicalKeyboardKey.end && _totalPages > 0) {
      _jumpToPageIndex(_totalPages - 1);
    }
  }

  Widget _applyColorFilter(Widget child) {
    Widget result = child;

    // Sharpening / Contrast Enhancement
    if (_sharpenMode == ReadSharpenMode.subtle) {
      result = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1.15, 0, 0, 0, -15,
          0, 1.15, 0, 0, -15,
          0, 0, 1.15, 0, -15,
          0, 0, 0, 1, 0,
        ]),
        child: result,
      );
    } else if (_sharpenMode == ReadSharpenMode.high) {
      result = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1.35, 0, 0, 0, -35,
          0, 1.35, 0, 0, -35,
          0, 0, 1.35, 0, -35,
          0, 0, 0, 1, 0,
        ]),
        child: result,
      );
    }

    // Color palette mode
    if (_filterMode == ReadColorFilter.invert) {
      result = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]),
        child: result,
      );
    } else if (_filterMode == ReadColorFilter.sepia) {
      result = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: result,
      );
    }

    if (_brightness < 1.0) {
      result = Stack(
        fit: StackFit.passthrough,
        children: [
          result,
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 1.0 - _brightness),
            ),
          ),
        ],
      );
    }

    return result;
  }

  void _showPageJumperDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: const Text('Перейти на страницу', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: _totalPages,
              itemBuilder: (ctx2, i) {
                final isCurrent = i == _currentPageIndex;
                return InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _jumpToPageIndex(i);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCurrent ? const Color(0xFF8A897C) : const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: isCurrent ? Colors.white : const Color(0xFFD2D7DF),
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть', style: TextStyle(color: Color(0xFFD2D7DF))),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    if (_isLoading) {
      return Scaffold(
        backgroundColor: _resolvedBgColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          title: Text(
            _chapterTitle.isNotEmpty ? _chapterTitle : (isRu ? 'Загрузка главы...' : 'Loading chapter...'),
            style: const TextStyle(fontSize: 15, color: Colors.white),
          ),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3E3E3E)),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 18, 
                  height: 18, 
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF8A897C)),
                ),
                const SizedBox(width: 12),
                Text(
                  isRu ? 'Загрузка страниц...' : 'Loading pages...',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      final isLocked = _errorMessage!.contains('заблокирована') || _errorMessage!.contains('доступ');
      return Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
          title: Text(_chapterTitle),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Card(
                color: const Color(0xFF2C2C2C),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF3E3E3E)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLocked ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
                        color: isLocked ? Colors.amberAccent : Colors.redAccent,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isLocked ? 'Глава заблокирована' : 'Ошибка загрузки',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFFD2D7DF), fontSize: 13, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8A897C),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Вернуться к манге'),
                      ),
                      if (widget.slugUrl.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD2D7DF),
                            minimumSize: const Size.fromHeight(42),
                          ),
                          onPressed: () async {
                            final uri = Uri.parse('https://mangalib.org/ru/manga/${widget.slugUrl}/read/v${widget.volume}/c${widget.number}');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                          label: const Text('Открыть на MangaLib'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: _resolvedBgColor,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: _handleTap,
          child: Stack(
            children: [
              _buildReaderContent(isRu),

              if (_showHud && _totalPages > 0)
            Positioned(
              bottom: 12,
              right: 14,
              child: ValueListenableBuilder<bool>(
                valueListenable: _showControlsNotifier,
                builder: (context, showControls, _) {
                  if (showControls) return const SizedBox.shrink();
                  return _ReaderHud(
                    pageIndexNotifier: _pageIndexNotifier,
                    totalPages: _totalPages,
                  );
                },
              ),
            ),

          ValueListenableBuilder<bool>(
            valueListenable: _showControlsNotifier,
            builder: (context, showControls, _) {
              if (!showControls) return const SizedBox.shrink();
              final hasPrev = _prevChapter != null || _prevLocalCbzPath != null;
              final hasNext = _nextChapter != null || _nextLocalCbzPath != null;

              return Stack(
                children: [
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: AppBar(
                      backgroundColor: Colors.black.withValues(alpha: 0.85),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      leading: const BackButton(),
                      title: InkWell(
                        onTap: _allChapters.isNotEmpty ? _showChapterListDialog : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Text(_chapterTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                              if (_allChapters.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down_rounded, size: 20, color: Color(0xFF8A897C)),
                              ],
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        if (hasPrev)
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded),
                            tooltip: isRu ? 'Предыдущая глава' : 'Previous Chapter',
                            onPressed: _navigateToPrevChapter,
                          ),
                        if (hasNext)
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded),
                            tooltip: isRu ? 'Следующая глава' : 'Next Chapter',
                            onPressed: _navigateToNextChapter,
                          ),
                        if (_allChapters.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.format_list_bulleted_rounded),
                            tooltip: isRu ? 'Список глав' : 'Chapter list',
                            onPressed: _showChapterListDialog,
                          ),
                        IconButton(
                          icon: const Icon(Icons.grid_view_rounded),
                          tooltip: isRu ? 'Сетка страниц' : 'Page Grid',
                          onPressed: _showPageJumperDialog,
                        ),
                        if (_readMode == ReadMode.vertical)
                          IconButton(
                            icon: Icon(_isAutoScrolling ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: _isAutoScrolling ? Colors.orange : Colors.white),
                            tooltip: _isAutoScrolling ? (isRu ? 'Остановить автопрокрутку (A)' : 'Stop autoscroll (A)') : (isRu ? 'Автопрокрутка (A)' : 'Autoscroll (A)'),
                            onPressed: _toggleAutoScroll,
                          ),
                        IconButton(
                          icon: Icon(_isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                          tooltip: isRu ? 'Полноэкранный режим (F11)' : 'Fullscreen (F11)',
                          onPressed: _toggleFullscreen,
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: isRu ? 'Сбросить кэш и перезагрузить главу' : 'Reload chapter',
                          onPressed: _reloadCurrentChapter,
                        ),
                        IconButton(icon: const Icon(Icons.tune_rounded), tooltip: isRu ? 'Настройки' : 'Settings', onPressed: _showSettingsSheet),
                      ],
                    ),
                  ),

                  // Floating Zoom Toolbar
                  Positioned(
                    right: 16,
                    bottom: 100,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.zoom_in_rounded, color: Colors.white),
                            tooltip: isRu ? 'Приблизить (+)' : 'Zoom In (+)',
                            onPressed: _zoomIn,
                          ),
                          TextButton(
                            onPressed: _resetZoom,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              '${(_zoomLevel * 100).toInt()}%',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.zoom_out_rounded, color: Colors.white),
                            tooltip: isRu ? 'Отдалить (-)' : 'Zoom Out (-)',
                            onPressed: _zoomOut,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom progress and page controls
                  if (_totalPages > 0)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.85),
                        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, left: 16, right: 16, top: 12),
                        child: SafeArea(
                          top: false,
                          child: ValueListenableBuilder<int>(
                            valueListenable: _pageIndexNotifier,
                            builder: (context, pageIndex, _) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_totalPages > 1)
                                    Slider(
                                      value: pageIndex.toDouble().clamp(0.0, (_totalPages - 1).toDouble()),
                                      min: 0,
                                      max: (_totalPages - 1).toDouble(),
                                      activeColor: const Color(0xFF8A897C),
                                      inactiveColor: const Color(0xFF353535),
                                      onChanged: (val) {
                                        final target = val.round();
                                        if (target != _currentPageIndex) {
                                          _jumpToPageIndex(target);
                                        }
                                      },
                                    ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          TextButton.icon(
                                            onPressed: _showPageJumperDialog,
                                            icon: const Icon(Icons.menu_book_rounded, size: 16, color: Colors.white70),
                                            label: Text('${pageIndex + 1} / $_totalPages стр.', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          ),
                                          if (_allChapters.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.format_list_bulleted_rounded, size: 18, color: Color(0xFF8A897C)),
                                              tooltip: isRu ? 'Выбрать главу' : 'Select chapter',
                                              onPressed: _showChapterListDialog,
                                            ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          if (hasPrev)
                                            IconButton(
                                              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white70),
                                              tooltip: isRu ? 'Предыдущая глава' : 'Previous chapter',
                                              onPressed: _navigateToPrevChapter,
                                            ),
                                          if (hasNext) ...[
                                            FilledButton.tonalIcon(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: const Color(0xFF8A897C).withValues(alpha: 0.3),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                              onPressed: _navigateToNextChapter,
                                              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white),
                                              label: Text(
                                                _nextChapter != null ? 'Гл. ${_nextChapter!.number}' : (isRu ? 'След. глава' : 'Next Ch.'),
                                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          Icon(_isDownloaded ? Icons.offline_pin_rounded : Icons.cloud_rounded, color: _isDownloaded ? Colors.green : Colors.grey, size: 20),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

              // Floating Auto-Scroll Speed Controller
              if (_isAutoScrolling)
                Positioned(
                  top: 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2C).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF8A897C)),
                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_circle_fill_rounded, size: 16, color: Color(0xFF8A897C)),
                          const SizedBox(width: 6),
                          const Text('Автоскролл', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.remove_rounded, size: 16, color: Color(0xFFD2D7DF)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () {
                              setState(() {
                                _autoScrollSpeed = (_autoScrollSpeed - 0.5).clamp(0.5, 5.0);
                              });
                            },
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF353535),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_autoScrollSpeed}x',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFFD2D7DF)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () {
                              setState(() {
                                _autoScrollSpeed = (_autoScrollSpeed + 0.5).clamp(0.5, 5.0);
                              });
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: _toggleAutoScroll,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderContent(bool isRu) {
    if (_totalPages == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded, color: Colors.grey, size: 48),
            const SizedBox(height: 16),
            Text(
              isRu ? 'Страницы не найдены.' : 'No pages found.',
              style: TextStyle(color: _bgColor == ReadBgColor.white ? Colors.black : Colors.white),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: Text(isRu ? 'Назад' : 'Go Back'),
            ),
          ],
        ),
      );
    } else if (_readMode == ReadMode.vertical) {
      return Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          child: Column(
            children: [
              for (int i = 0; i < _totalPages; i++)
                _VerticalReaderPageItem(
                  key: i < _pageKeys.length ? _pageKeys[i] : ValueKey('page_$i'),
                  index: i,
                  totalPages: _totalPages,
                  isDownloaded: _isDownloaded,
                  cbzPath: _cbzPath,
                  onlinePages: _onlinePages,
                  resolveImageUrl: _resolveImageUrl,
                  getCbzPage: _getCbzPage,
                  reloadImage: _reloadImage,
                  zoomLevel: _zoomLevel,
                  cropBorders: _cropBorders,
                  cropPercent: _cropPercent,
                  applyColorFilter: _applyColorFilter,
                ),
              _buildNextChapterSwipeCard(isRu),
            ],
          ),
        ),
      );
    } else {
      return PageView.builder(
        controller: _pageController!,
        itemCount: _totalPages + 1,
        reverse: _readMode == ReadMode.rtl,
        onPageChanged: _onPageChanged,
        physics: const ClampingScrollPhysics(),
        itemBuilder: (context, index) {
          if (index == _totalPages) {
            return Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildNextChapterSwipeCard(isRu),
                ),
              ),
            );
          }
          return _HorizontalReaderPageItem(
            key: ValueKey('h_page_$index'),
            index: index,
            isDownloaded: _isDownloaded,
            onlinePages: _onlinePages,
            resolveImageUrl: _resolveImageUrl,
            getCbzPage: _getCbzPage,
            reloadImage: _reloadImage,
            zoomLevel: _zoomLevel,
            cropBorders: _cropBorders,
            cropPercent: _cropPercent,
            boxFit: _resolvedBoxFit,
            applyColorFilter: _applyColorFilter,
          );
        },
      );
    }
  }

  void _navigateToPrevChapter() {
    if (_prevChapter != null) {
      final branchQ = _prevChapter!.branchId != null ? "?branchId=${_prevChapter!.branchId}" : "";
      context.pushReplacement('/read/${widget.slugUrl}/${_prevChapter!.volume}/${_prevChapter!.number}$branchQ');
    } else if (_prevLocalCbzPath != null) {
      context.pushReplacement('/read-local?path=${Uri.encodeComponent(_prevLocalCbzPath!)}');
    }
  }

  void _navigateToNextChapter() {
    if (_nextChapter != null) {
      final branchQ = _nextChapter!.branchId != null ? "?branchId=${_nextChapter!.branchId}" : "";
      context.pushReplacement('/read/${widget.slugUrl}/${_nextChapter!.volume}/${_nextChapter!.number}$branchQ');
    } else if (_nextLocalCbzPath != null) {
      context.pushReplacement('/read-local?path=${Uri.encodeComponent(_nextLocalCbzPath!)}');
    }
  }

  void _showChapterListDialog() {
    if (_allChapters.isEmpty) return;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    String filterQuery = '';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filtered = _allChapters.where((c) {
            if (filterQuery.isEmpty) return true;
            final q = filterQuery.toLowerCase();
            return c.number.contains(q) || c.volume.contains(q) || (c.name ?? '').toLowerCase().contains(q);
          }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (ctx, scrollController) => Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.format_list_bulleted_rounded, color: Color(0xFF8A897C), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        isRu ? 'Список глав (${_allChapters.length})' : 'Chapters (${_allChapters.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: isRu ? 'Поиск главы...' : 'Search chapter...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF2C2C2C),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) => setModalState(() => filterQuery = val.trim()),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final c = filtered[i];
                      final isCurrent = c.volume == widget.volume && c.number == widget.number;

                      return ListTile(
                        selected: isCurrent,
                        selectedTileColor: const Color(0xFF8A897C).withValues(alpha: 0.20),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isCurrent ? const Color(0xFF8A897C) : const Color(0xFF2C2C2C),
                          child: Text(
                            c.number,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isCurrent ? Colors.white : const Color(0xFFD2D7DF),
                            ),
                          ),
                        ),
                        title: Text(
                          isRu ? 'Том ${c.volume} Глава ${c.number}' : 'Volume ${c.volume} Chapter ${c.number}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent ? Colors.white : const Color(0xFFD2D7DF),
                          ),
                        ),
                        subtitle: c.name != null && c.name!.isNotEmpty
                            ? Text(c.name!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54))
                            : null,
                        trailing: c.isPaid
                            ? const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.amber)
                            : isCurrent
                                ? const Icon(Icons.bookmark_rounded, size: 18, color: Color(0xFF8A897C))
                                : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          if (!isCurrent) {
                            final branchQ = c.branchId != null ? "?branchId=${c.branchId}" : "";
                            context.pushReplacement('/read/${widget.slugUrl}/${c.volume}/${c.number}$branchQ');
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettingsSheet() {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isRu ? 'Настройки читалки' : 'Reader Settings', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    
                    Text(isRu ? 'Режим чтения' : 'Reading Mode', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SegmentedButton<ReadMode>(
                      segments: [
                        ButtonSegment(value: ReadMode.vertical, label: Text(isRu ? 'Лента' : 'Webtoon')),
                        ButtonSegment(value: ReadMode.ltr, label: Text(isRu ? 'Слева' : 'LTR')),
                        ButtonSegment(value: ReadMode.rtl, label: Text(isRu ? 'Справа (Манга)' : 'RTL (Manga)')),
                      ],
                      selected: {_readMode},
                      onSelectionChanged: (val) {
                        final newMode = val.first;
                        if (newMode != ReadMode.vertical && _readMode == ReadMode.vertical) {
                          _pageController?.dispose();
                          _pageController = PageController(initialPage: _currentPageIndex);
                        }
                        setState(() => _readMode = newMode);
                        setModalState(() {});
                        if (newMode == ReadMode.vertical && _currentPageIndex > 0) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _jumpToPageIndex(_currentPageIndex);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    Text(isRu ? 'Цвет фона' : 'Background Color', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SegmentedButton<ReadBgColor>(
                      segments: [
                        ButtonSegment(value: ReadBgColor.black, label: Text(isRu ? 'Черный' : 'Black')),
                        ButtonSegment(value: ReadBgColor.darkGrey, label: Text(isRu ? 'Серый' : 'Grey')),
                        ButtonSegment(value: ReadBgColor.white, label: Text(isRu ? 'Белый' : 'White')),
                      ],
                      selected: {_bgColor},
                      onSelectionChanged: (val) {
                        setState(() => _bgColor = val.first);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 16),

                    // Filter mode
                    Text(isRu ? 'Цветовой фильтр' : 'Color Filter', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SegmentedButton<ReadColorFilter>(
                      segments: [
                        ButtonSegment(value: ReadColorFilter.none, label: Text(isRu ? 'Обычный' : 'Normal')),
                        ButtonSegment(value: ReadColorFilter.invert, label: Text(isRu ? 'Инверсия' : 'Invert')),
                        ButtonSegment(value: ReadColorFilter.sepia, label: Text(isRu ? 'Сепия' : 'Sepia')),
                      ],
                      selected: {_filterMode},
                      onSelectionChanged: (val) {
                        setState(() => _filterMode = val.first);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 16),

                    // Sharpening Mode
                    Text(isRu ? 'Фильтр резкости' : 'Sharpening Filter', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SegmentedButton<ReadSharpenMode>(
                      segments: [
                        ButtonSegment(value: ReadSharpenMode.off, label: Text(isRu ? 'Выкл' : 'Off')),
                        ButtonSegment(value: ReadSharpenMode.subtle, label: Text(isRu ? 'Мягкий' : 'Subtle')),
                        ButtonSegment(value: ReadSharpenMode.high, label: Text(isRu ? 'Четкий' : 'High')),
                      ],
                      selected: {_sharpenMode},
                      onSelectionChanged: (val) {
                        setState(() => _sharpenMode = val.first);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 16),

                    // Auto crop borders switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(isRu ? 'Обрезка белых полей' : 'Crop White Borders', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        isRu ? 'Автоматически увеличивает страницу для удаления пустых полей' : 'Automatically crops empty borders',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      value: _cropBorders,
                      onChanged: (val) {
                        setState(() => _cropBorders = val);
                        setModalState(() {});
                      },
                    ),
                    if (_cropBorders) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isRu ? 'Степень обрезки' : 'Crop margin', style: const TextStyle(color: Colors.white70)),
                          Text('${_cropPercent.toInt()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Slider(
                        value: _cropPercent,
                        min: 1.0,
                        max: 10.0,
                        divisions: 9,
                        onChanged: (val) {
                          setState(() => _cropPercent = val);
                          setModalState(() {});
                        },
                      ),
                    ],

                    // Brightness slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(isRu ? 'Яркость страниц' : 'Page Brightness', style: const TextStyle(color: Colors.white70)),
                        Text('${(_brightness * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: _brightness,
                      min: 0.2,
                      max: 1.0,
                      divisions: 16,
                      onChanged: (val) {
                        setState(() => _brightness = val);
                        setModalState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNextChapterSwipeCard(bool isRu) {
    if (_nextChapter == null && _nextLocalCbzPath == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF383838)),
        ),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 40, color: Color(0xFF8A897C)),
            const SizedBox(height: 12),
            Text(
              isRu ? 'Вы прочитали последнюю главу!' : 'You reached the latest chapter!',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isRu ? 'Ожидайте выхода новых глав от переводчиков' : 'Stay tuned for upcoming releases',
              style: const TextStyle(fontSize: 12, color: Color(0xFFBDBBB0)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_prevChapter != null || _prevLocalCbzPath != null) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF484848)),
                  minimumSize: const Size.fromHeight(42),
                ),
                onPressed: _navigateToPrevChapter,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(
                  _prevChapter != null 
                    ? (isRu ? 'Предыдущая: Том ${_prevChapter!.volume} Гл. ${_prevChapter!.number}' : 'Previous Chapter')
                    : (isRu ? 'Предыдущая глава' : 'Previous Chapter'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_allChapters.isNotEmpty) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD2D7DF),
                  side: const BorderSide(color: Color(0xFF8A897C)),
                  minimumSize: const Size.fromHeight(42),
                ),
                onPressed: _showChapterListDialog,
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
                label: Text(isRu ? 'Список всех глав' : 'All Chapters'),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8A897C),
                side: const BorderSide(color: Color(0xFF8A897C)),
                minimumSize: const Size.fromHeight(42),
              ),
              onPressed: () async {
                await _findNextChapter();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_nextChapter != null
                          ? (isRu ? 'Найдена следующая глава: Том ${_nextChapter!.volume} Гл ${_nextChapter!.number}' : 'Next chapter found!')
                          : (isRu ? 'Новых глав пока нет' : 'No new chapters yet')),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(isRu ? 'Проверить новые главы' : 'Check for new chapters'),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8A897C).withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_stories_rounded, color: Color(0xFF8A897C), size: 20),
              const SizedBox(width: 8),
              Text(
                isRu ? 'Глава завершена' : 'Chapter Complete',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_nextChapter != null)
            Text(
              isRu 
                ? 'Следующая: Том ${_nextChapter!.volume} Глава ${_nextChapter!.number}' 
                : 'Next: Volume ${_nextChapter!.volume} Chapter ${_nextChapter!.number}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              textAlign: TextAlign.center,
            )
          else if (_nextLocalCbzPath != null)
            Text(
              isRu ? 'Следующая глава' : 'Next Chapter',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          if (_nextChapter?.name != null && _nextChapter!.name!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _nextChapter!.name!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFBDBBB0)),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8A897C),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _navigateToNextChapter,
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: Text(
              isRu ? 'Читать следующую главу' : 'Read Next Chapter',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          if (_allChapters.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Color(0xFF484848)),
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _showChapterListDialog,
              icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
              label: Text(isRu ? 'Список глав' : 'Chapter List'),
            ),
          ],
          if (_prevChapter != null || _prevLocalCbzPath != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white60,
                minimumSize: const Size.fromHeight(38),
              ),
              onPressed: _navigateToPrevChapter,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text(
                _prevChapter != null
                  ? (isRu ? 'Предыдущая: Том ${_prevChapter!.volume} Гл. ${_prevChapter!.number}' : 'Previous Chapter')
                  : (isRu ? 'Предыдущая глава' : 'Previous Chapter'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dedicated vertical page item with AutomaticKeepAliveClientMixin to prevent rebuilding/flashing on scroll
class _VerticalReaderPageItem extends StatefulWidget {
  final int index;
  final int totalPages;
  final bool isDownloaded;
  final String cbzPath;
  final List<ChapterPage> onlinePages;
  final String Function(String) resolveImageUrl;
  final Future<Uint8List?> Function(int) getCbzPage;
  final Future<void> Function(String) reloadImage;
  final double zoomLevel;
  final bool cropBorders;
  final double cropPercent;
  final Widget Function(Widget) applyColorFilter;

  const _VerticalReaderPageItem({
    super.key,
    required this.index,
    required this.totalPages,
    required this.isDownloaded,
    required this.cbzPath,
    required this.onlinePages,
    required this.resolveImageUrl,
    required this.getCbzPage,
    required this.reloadImage,
    required this.zoomLevel,
    required this.cropBorders,
    required this.cropPercent,
    required this.applyColorFilter,
  });

  @override
  State<_VerticalReaderPageItem> createState() => _VerticalReaderPageItemState();
}

class _VerticalReaderPageItemState extends State<_VerticalReaderPageItem> with AutomaticKeepAliveClientMixin {
  Uint8List? _cbzBytes;
  bool _isLoadingCbz = false;
  bool _cbzError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.isDownloaded) {
      _loadCbzBytes();
    }
  }

  void _loadCbzBytes() async {
    if (_isLoadingCbz) return;
    _isLoadingCbz = true;
    try {
      final bytes = await widget.getCbzPage(widget.index);
      if (mounted) {
        setState(() {
          _cbzBytes = bytes;
          _cbzError = bytes == null;
          _isLoadingCbz = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cbzError = true;
          _isLoadingCbz = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth * widget.zoomLevel;

    double? knownAspectRatio;
    if (widget.index < widget.onlinePages.length) {
      final p = widget.onlinePages[widget.index];
      if (p.width != null && p.height != null && p.width! > 0 && p.height! > 0) {
        knownAspectRatio = p.width! / p.height!;
      }
    }

    final placeholderHeight = (knownAspectRatio != null && knownAspectRatio > 0)
        ? itemWidth / knownAspectRatio
        : itemWidth * 1.4;

    Widget content;
    if (widget.isDownloaded) {
      if (_cbzBytes != null) {
        content = Image.memory(
          _cbzBytes!,
          fit: BoxFit.fitWidth,
          filterQuality: FilterQuality.high,
          alignment: Alignment.topCenter,
          gaplessPlayback: true,
        );
      } else if (_cbzError) {
        content = Container(
          height: placeholderHeight,
          color: const Color(0xFF181818),
          child: const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
        );
      } else {
        content = Container(
          height: placeholderHeight,
          color: const Color(0xFF181818),
          child: const Center(
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      }
    } else if (widget.index < widget.onlinePages.length) {
      final pageUrl = widget.resolveImageUrl(widget.onlinePages[widget.index].url);

      content = CachedNetworkImage(
        imageUrl: pageUrl,
        httpHeaders: const {'Referer': 'https://mangalib.org/'},
        fit: BoxFit.fitWidth,
        filterQuality: FilterQuality.high,
        alignment: Alignment.topCenter,
        placeholder: (ctx, url) => Container(
          height: placeholderHeight,
          color: const Color(0xFF181818),
          child: const Center(
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
        errorWidget: (ctx, url, err) => InkWell(
          onTap: () => widget.reloadImage(pageUrl),
          child: Container(
            height: placeholderHeight,
            color: const Color(0xFF181818),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded, color: Colors.white70, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    Localizations.localeOf(context).languageCode == 'ru' ? 'Нажмите для повтора' : 'Tap to retry',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      content = Container(
        height: placeholderHeight,
        color: const Color(0xFF181818),
        child: const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
      );
    }

    if (widget.cropBorders) {
      final scaleFactor = 1.0 + (widget.cropPercent * 2 / 100.0);
      content = ClipRect(
        child: Transform.scale(scale: scaleFactor, child: content),
      );
    }

    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.5,
      panEnabled: true,
      scaleEnabled: true,
      clipBehavior: Clip.none,
      child: Container(
        padding: const EdgeInsets.only(bottom: 1),
        width: itemWidth,
        child: Center(
          child: SizedBox(
            width: itemWidth,
            child: widget.applyColorFilter(content),
          ),
        ),
      ),
    );
  }
}

/// Dedicated horizontal page item with AutomaticKeepAliveClientMixin and InteractiveViewer
class _HorizontalReaderPageItem extends StatefulWidget {
  final int index;
  final bool isDownloaded;
  final List<ChapterPage> onlinePages;
  final String Function(String) resolveImageUrl;
  final Future<Uint8List?> Function(int) getCbzPage;
  final Future<void> Function(String) reloadImage;
  final double zoomLevel;
  final bool cropBorders;
  final double cropPercent;
  final BoxFit boxFit;
  final Widget Function(Widget) applyColorFilter;

  const _HorizontalReaderPageItem({
    super.key,
    required this.index,
    required this.isDownloaded,
    required this.onlinePages,
    required this.resolveImageUrl,
    required this.getCbzPage,
    required this.reloadImage,
    required this.zoomLevel,
    required this.cropBorders,
    required this.cropPercent,
    required this.boxFit,
    required this.applyColorFilter,
  });

  @override
  State<_HorizontalReaderPageItem> createState() => _HorizontalReaderPageItemState();
}

class _HorizontalReaderPageItemState extends State<_HorizontalReaderPageItem> with AutomaticKeepAliveClientMixin {
  Uint8List? _cbzBytes;
  bool _isLoadingCbz = false;
  bool _cbzError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.isDownloaded) {
      _loadCbzBytes();
    }
  }

  void _loadCbzBytes() async {
    if (_isLoadingCbz) return;
    _isLoadingCbz = true;
    try {
      final bytes = await widget.getCbzPage(widget.index);
      if (mounted) {
        setState(() {
          _cbzBytes = bytes;
          _cbzError = bytes == null;
          _isLoadingCbz = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cbzError = true;
          _isLoadingCbz = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    Widget content;
    if (widget.isDownloaded) {
      if (_cbzBytes != null) {
        content = Image.memory(
          _cbzBytes!,
          fit: widget.boxFit,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        );
      } else if (_cbzError) {
        content = const AspectRatio(
          aspectRatio: 0.7,
          child: Center(child: Icon(Icons.broken_image, color: Colors.white)),
        );
      } else {
        content = const AspectRatio(
          aspectRatio: 0.7,
          child: Center(child: CircularProgressIndicator()),
        );
      }
    } else if (widget.index < widget.onlinePages.length) {
      final pageUrl = widget.resolveImageUrl(widget.onlinePages[widget.index].url);
      
      content = CachedNetworkImage(
        imageUrl: pageUrl,
        httpHeaders: const {'Referer': 'https://mangalib.org/'},
        fit: widget.boxFit,
        filterQuality: FilterQuality.high,
        placeholder: (ctx, url) => const AspectRatio(aspectRatio: 0.7, child: Center(child: CircularProgressIndicator())),
        errorWidget: (ctx, url, err) => InkWell(
          onTap: () => widget.reloadImage(pageUrl),
          child: AspectRatio(
            aspectRatio: 0.7,
            child: Container(
              color: const Color(0xFF181818),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded, color: Colors.white70, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      Localizations.localeOf(context).languageCode == 'ru' ? 'Нажмите для повтора' : 'Tap to retry',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      content = const AspectRatio(
        aspectRatio: 0.7,
        child: Center(child: Icon(Icons.broken_image, color: Colors.white)),
      );
    }

    if (widget.cropBorders) {
      final scaleFactor = 1.0 + (widget.cropPercent * 2 / 100.0);
      content = ClipRect(
        child: Transform.scale(scale: scaleFactor, child: content),
      );
    }

    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.0,
      clipBehavior: Clip.none,
      child: Center(
        child: widget.applyColorFilter(content),
      ),
    );
  }
}

class _ReaderHud extends StatefulWidget {
  final ValueNotifier<int> pageIndexNotifier;
  final int totalPages;

  const _ReaderHud({
    required this.pageIndexNotifier,
    required this.totalPages,
  });

  @override
  State<_ReaderHud> createState() => _ReaderHudState();
}

class _ReaderHudState extends State<_ReaderHud> {
  String _currentTime = "";
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.full;
  Timer? _clockTimer;
  StreamSubscription<BatteryState>? _batteryStateSub;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _updateTime());
    _initBattery();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _batteryStateSub?.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    if (mounted) setState(() => _currentTime = '$h:$m');
  }

  void _initBattery() async {
    try {
      final battery = Battery();
      final lvl = await battery.batteryLevel;
      if (mounted) setState(() => _batteryLevel = lvl);
      _batteryStateSub = battery.onBatteryStateChanged.listen((state) {
        if (mounted) setState(() => _batteryState = state);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.pageIndexNotifier,
      builder: (context, pageIndex, _) {
        final pct = widget.totalPages > 0 ? (((pageIndex + 1) / widget.totalPages) * 100).toInt() : 0;
        return IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_currentTime.isNotEmpty) ...[
                  Text(_currentTime, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                ],
                Icon(
                  _batteryState == BatteryState.charging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                  color: Colors.white70,
                  size: 13,
                ),
                const SizedBox(width: 2),
                Text('$_batteryLevel%', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(width: 8),
                Container(width: 1, height: 10, color: Colors.white24),
                const SizedBox(width: 8),
                Text(
                  '${pageIndex + 1}/${widget.totalPages} ($pct%)',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
