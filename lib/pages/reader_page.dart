import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:battery_plus/battery_plus.dart';
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

class ReaderPage extends StatefulWidget {
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
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  bool _showControls = false;
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
  String _currentTime = "";
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.full;
  Timer? _clockTimer;
  StreamSubscription<BatteryState>? _batteryStateSub;

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
  
  // Cache for CBZ page bytes
  final Map<int, Uint8List> _pageCache = {};
  
  int _currentPageIndex = 0;
  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  // Page height cache for vertical mode
  final Map<int, double> _pageHeights = {};
  
  Timer? _saveTimer;
  int _mangaId = 0;
  String _chapterTitle = "";
  
  // Next chapter info for prefetching & seamless transition
  Chapter? _nextChapter;
  List<Chapter> _allChapters = [];
  bool _isNextChapterPrefetched = false;
  int _activePointers = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _scrollController.addListener(_onVerticalScroll);
    _chapterTitle = widget.localCbzPath != null
        ? widget.localCbzPath!.split(Platform.pathSeparator).last
        : 'Том ${widget.volume} Гл ${widget.number}';
    _updateWindowTitle();
    _initHud();
    _loadChapter();
  }

  double _getPageHeight(int index, double screenWidth) {
    if (_pageHeights.containsKey(index)) {
      return _pageHeights[index]!;
    }
    if (index < _onlinePages.length) {
      final p = _onlinePages[index];
      if (p.width != null && p.height != null && p.width! > 0 && p.height! > 0) {
        final calc = (screenWidth * _zoomLevel) * (p.height! / p.width!);
        _pageHeights[index] = calc;
        return calc;
      }
    }
    return (screenWidth * _zoomLevel) / 0.7;
  }

  void _onVerticalScroll() {
    if (_readMode != ReadMode.vertical || !_scrollController.hasClients || _totalPages <= 1) return;
    
    final offset = _scrollController.offset;
    final screenWidth = MediaQuery.of(context).size.width;
    final viewportHeight = MediaQuery.of(context).size.height;
    final currentReadingPoint = offset + (viewportHeight * 0.4);

    double accumulated = 0.0;
    int currentVisible = 0;
    
    for (int i = 0; i < _totalPages; i++) {
      final h = _getPageHeight(i, screenWidth);
      if (currentReadingPoint >= accumulated && currentReadingPoint < accumulated + h) {
        currentVisible = i;
        break;
      }
      accumulated += h;
      currentVisible = i;
    }
    
    if (currentVisible != _currentPageIndex) {
      _currentPageIndex = currentVisible;
      if (mounted) setState(() {});
      _scheduleSaveProgress();
    }

    // Smart Next Chapter Preload (trigger when near end of chapter)
    if (_nextChapter != null && !_isNextChapterPrefetched) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent > 0 && (offset >= maxExtent * 0.75 || maxExtent - offset < 2500)) {
        _isNextChapterPrefetched = true;
        _prefetchNextChapter(_nextChapter!);
      }
    }
  }

  void _initHud() {
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _updateTime());
    _initBattery();
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

  void _updateWindowTitle() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setTitle("Manga Loader - $_chapterTitle");
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onVerticalScroll);
    _clockTimer?.cancel();
    _batteryStateSub?.cancel();
    _stopAutoScroll();
    _saveTimer?.cancel();
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
    _pageController.dispose();
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

    setState(() => _isLoading = false);
    
    if (_totalPages > 0 && _currentPageIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToPageIndex(_currentPageIndex);
      });
    }
  }

  void _jumpToPageIndex(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _totalPages) return;
    setState(() => _currentPageIndex = targetIndex);
    
    if (_readMode != ReadMode.vertical && _pageController.hasClients) {
      _pageController.jumpToPage(targetIndex);
    } else if (_readMode == ReadMode.vertical && _scrollController.hasClients && _totalPages > 1) {
      final screenWidth = MediaQuery.of(context).size.width;
      double targetOffset = 0.0;
      for (int i = 0; i < targetIndex; i++) {
        targetOffset += _getPageHeight(i, screenWidth);
      }
      _scrollController.jumpTo(targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
    }
    _scheduleSaveProgress();
  }

  Future<void> _findNextChapter() async {
    if (widget.slugUrl.isEmpty) return;
    try {
      _allChapters = await rust_api.getChapters(slugUrl: widget.slugUrl);
      final currentIndex = _allChapters.indexWhere(
        (c) => c.volume == widget.volume && c.number == widget.number
      );
      if (currentIndex != -1 && currentIndex + 1 < _allChapters.length) {
        final next = _allChapters[currentIndex + 1];
        if (!next.isPaid) {
          _nextChapter = next;
          _prefetchNextChapter(next);
        }
      }
    } catch (_) {}
  }

  Future<void> _prefetchNextChapter(Chapter next) async {
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
      _pageCache.removeWhere((k, _) => (k - index).abs() > 8);
      return data;
    } catch (e) {
      debugPrint("Error reading CBZ page $index: $e");
      return null;
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPageIndex = index);
    if (!_isDownloaded) _preloadImages(index);
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

      // Auto-add to library as "reading" if not already in any list
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
        else if (_currentPageIndex > 0) { _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut); }
      }
    } else if (dx > width * 0.75) {
      if (_readMode != ReadMode.vertical) {
        if (isRtl && _currentPageIndex > 0) { _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut); }
        else if (!isRtl) { _nextPageAction(); }
      }
    } else {
      setState(() => _showControls = !_showControls);
    }
  }

  void _nextPageAction() {
    if (_currentPageIndex < _totalPages - 1) {
      if (_readMode != ReadMode.vertical && _pageController.hasClients) {
        _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
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
      _pageHeights.clear();
    });
  }

  void _zoomOut() {
    setState(() {
      _zoomLevel = (_zoomLevel - 0.25).clamp(0.5, 4.0);
      _pageHeights.clear();
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomLevel = 1.0;
      _pageHeights.clear();
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

  double _baseScale = 1.0;

  void _handleScaleStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      _baseScale = _zoomLevel;
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2 && details.scale != 1.0) {
      setState(() {
        _zoomLevel = (_baseScale * details.scale).clamp(0.5, 4.0);
        _pageHeights.clear();
      });
    }
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.scale != 1.0) {
      setState(() {
        _zoomLevel = (_zoomLevel * event.scale).clamp(0.5, 4.0);
        _pageHeights.clear();
      });
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    
    final isRtl = _readMode == ReadMode.rtl;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.pageDown || event.logicalKey == LogicalKeyboardKey.space) {
      if (isRtl && _currentPageIndex > 0) {
        if (_readMode != ReadMode.vertical && _pageController.hasClients) {
          _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
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
        if (_readMode != ReadMode.vertical && _pageController.hasClients) {
          _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
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

  Widget _buildImageContent(int index) {
    Widget content;
    if (_isDownloaded) {
      content = FutureBuilder<Uint8List?>(
        future: _getCbzPage(index),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const AspectRatio(aspectRatio: 0.7, child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasData && snap.data != null) {
            return Image.memory(
              snap.data!, 
              fit: _resolvedBoxFit, 
              gaplessPlayback: true,
            );
          }
          return const AspectRatio(
            aspectRatio: 0.7,
            child: Center(child: Icon(Icons.broken_image, color: Colors.white)),
          );
        },
      );
    } else if (index < _onlinePages.length) {
      final pageUrl = _resolveImageUrl(_onlinePages[index].url);
      final screenWidth = MediaQuery.of(context).size.width;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final memWidth = (screenWidth * _zoomLevel * dpr).toInt().clamp(300, 2560);
      
      content = CachedNetworkImage(
        imageUrl: pageUrl,
        httpHeaders: const {'Referer': 'https://mangalib.org/'},
        fit: _resolvedBoxFit,
        memCacheWidth: memWidth,
        placeholder: (ctx, url) => const AspectRatio(aspectRatio: 0.7, child: Center(child: CircularProgressIndicator())),
        errorWidget: (ctx, url, err) => InkWell(
          onTap: () => _reloadImage(pageUrl),
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

    // Border Crop wrapping
    if (_cropBorders) {
      final scaleFactor = 1.0 + (_cropPercent * 2 / 100.0);
      content = ClipRect(
        child: Transform.scale(
          scale: scaleFactor,
          child: content,
        ),
      );
    }

    return _applyColorFilter(content);
  }

  Widget _buildVerticalImage(int index) {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth * _zoomLevel;

    double? knownAspectRatio;
    if (index < _onlinePages.length) {
      final p = _onlinePages[index];
      if (p.width != null && p.height != null && p.width! > 0 && p.height! > 0) {
        knownAspectRatio = p.width! / p.height!;
      }
    }

    final placeholderHeight = (knownAspectRatio != null && knownAspectRatio > 0)
        ? itemWidth / knownAspectRatio
        : itemWidth * 1.4;

    Widget content;
    if (_isDownloaded) {
      content = FutureBuilder<Uint8List?>(
        future: _getCbzPage(index),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Container(
              height: placeholderHeight,
              color: const Color(0xFF181818),
              child: const Center(
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            );
          }
          if (snap.hasData && snap.data != null) {
            return Image.memory(
              snap.data!, 
              fit: BoxFit.fitWidth, 
              alignment: Alignment.topCenter,
              gaplessPlayback: true,
            );
          }
          return Container(
            height: placeholderHeight,
            color: const Color(0xFF181818),
            child: const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
          );
        },
      );
    } else if (index < _onlinePages.length) {
      final pageUrl = _resolveImageUrl(_onlinePages[index].url);
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final memWidth = (itemWidth * dpr).toInt().clamp(300, 2560);

      content = CachedNetworkImage(
        imageUrl: pageUrl,
        httpHeaders: const {'Referer': 'https://mangalib.org/'},
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        memCacheWidth: memWidth,
        placeholder: (ctx, url) => Container(
          height: placeholderHeight,
          color: const Color(0xFF181818),
          child: const Center(
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
        errorWidget: (ctx, url, err) => InkWell(
          onTap: () => _reloadImage(pageUrl),
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

    if (_cropBorders) {
      final scaleFactor = 1.0 + (_cropPercent * 2 / 100.0);
      content = ClipRect(
        child: Transform.scale(scale: scaleFactor, child: content),
      );
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 1),
      child: Center(
        child: SizedBox(
          width: itemWidth,
          child: _applyColorFilter(content),
        ),
      ),
    );
  }

  Widget _buildHorizontalImage(int index) {
    final imageContent = _buildImageContent(index);
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onDoubleTap: () {
        setState(() {
          _zoomLevel = _zoomLevel == 1.0 ? 2.0 : 1.0;
          _pageHeights.clear();
        });
      },
      child: Center(
        child: SizedBox(
          width: screenWidth * _zoomLevel,
          height: MediaQuery.of(context).size.height * _zoomLevel,
          child: FittedBox(
            fit: _resolvedBoxFit,
            child: imageContent,
          ),
        ),
      ),
    );
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
        body: Listener(
          onPointerDown: (_) => setState(() => _activePointers++),
          onPointerUp: (_) => setState(() => _activePointers = (_activePointers - 1).clamp(0, 10)),
          onPointerCancel: (_) => setState(() => _activePointers = (_activePointers - 1).clamp(0, 10)),
          onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
          child: GestureDetector(
            onTapUp: _handleTap,
            onDoubleTap: () {
              setState(() {
                _zoomLevel = _zoomLevel == 1.0 ? 2.0 : 1.0;
                _pageHeights.clear();
              });
            },
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            child: Stack(
              children: [
                if (_totalPages == 0)
                  Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.menu_book_rounded, color: Colors.grey, size: 48),
                      const SizedBox(height: 16),
                      Text(isRu ? 'Страницы не найдены.' : 'No pages found.', style: TextStyle(color: _bgColor == ReadBgColor.white ? Colors.black : Colors.white)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => context.pop(), 
                        icon: const Icon(Icons.arrow_back),
                        label: Text(isRu ? 'Назад' : 'Go Back'),
                      ),
                    ],
                  ))
                else if (_readMode == ReadMode.vertical)
                  Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: _activePointers >= 2 
                        ? const NeverScrollableScrollPhysics() 
                        : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      itemCount: _totalPages + 1,
                      itemBuilder: (context, index) {
                        if (index == _totalPages) {
                          return _buildNextChapterSwipeCard(isRu);
                        }
                        return _buildVerticalImage(index);
                      },
                    ),
                  )
                else
                  PageView.builder(
                    controller: _pageController,
                    itemCount: _totalPages,
                    reverse: _readMode == ReadMode.rtl,
                    onPageChanged: _onPageChanged,
                    physics: _activePointers >= 2 
                      ? const NeverScrollableScrollPhysics() 
                      : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    itemBuilder: (context, index) => _buildHorizontalImage(index),
                  ),
                  
                // Top controls bar
                if (_showControls)
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: AppBar(
                      backgroundColor: Colors.black.withValues(alpha: 0.85),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      leading: const BackButton(),
                      title: Text(_chapterTitle, style: const TextStyle(fontSize: 16)),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.grid_view_rounded),
                          tooltip: 'Сетка страниц',
                          onPressed: _showPageJumperDialog,
                        ),
                        if (_readMode == ReadMode.vertical)
                          IconButton(
                            icon: Icon(_isAutoScrolling ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: _isAutoScrolling ? Colors.orange : Colors.white),
                            tooltip: _isAutoScrolling ? 'Остановить автопрокрутку (A)' : 'Автопрокрутка (A)',
                            onPressed: _toggleAutoScroll,
                          ),
                        IconButton(
                          icon: Icon(_isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                          tooltip: 'Полноэкранный режим (F11)',
                          onPressed: _toggleFullscreen,
                        ),
                        if (_nextChapter != null)
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded),
                            tooltip: 'Следующая глава (Том ${_nextChapter!.volume} Гл ${_nextChapter!.number})',
                            onPressed: () {
                              final branchQ = _nextChapter!.branchId != null ? "?branchId=${_nextChapter!.branchId}" : "";
                              context.pushReplacement('/read/${widget.slugUrl}/${_nextChapter!.volume}/${_nextChapter!.number}$branchQ');
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: Localizations.localeOf(context).languageCode == 'ru' ? 'Сбросить кэш и перезагрузить главу' : 'Reload chapter',
                          onPressed: _reloadCurrentChapter,
                        ),
                        IconButton(icon: const Icon(Icons.tune_rounded), tooltip: 'Настройки', onPressed: _showSettingsSheet),
                      ],
                    ),
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

                // Floating Zoom Toolbar
                if (_showControls)
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
                            tooltip: 'Приблизить (+)',
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
                            tooltip: 'Отдалить (-)',
                            onPressed: _zoomOut,
                          ),
                        ],
                      ),
                    ),
                  ),

                // Smart HUD (Bottom right corner)
                if (_showHud && _totalPages > 0 && !_showControls)
                  Positioned(
                    bottom: 12,
                    right: 14,
                    child: IgnorePointer(
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
                              '${_currentPageIndex + 1}/$_totalPages (${((_currentPageIndex + 1) / _totalPages * 100).toInt()}%)',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Bottom progress and page controls
                if (_showControls && _totalPages > 0)
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.85),
                      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, left: 16, right: 16, top: 12),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_totalPages > 1)
                              Slider(
                                value: _currentPageIndex.toDouble().clamp(0.0, (_totalPages - 1).toDouble()),
                                min: 0,
                                max: (_totalPages - 1).toDouble(),
                                activeColor: const Color(0xFF8A897C),
                                inactiveColor: const Color(0xFF353535),
                                onChanged: (val) {
                                  _jumpToPageIndex(val.toInt());
                                },
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton.icon(
                                  onPressed: _showPageJumperDialog,
                                  icon: const Icon(Icons.menu_book_rounded, size: 16, color: Colors.white70),
                                  label: Text('${_currentPageIndex + 1} / $_totalPages стр.', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                                Row(
                                  children: [
                                    if (_nextChapter != null) ...[
                                      Text('След: Гл ${_nextChapter!.number}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                      const SizedBox(width: 8),
                                    ],
                                    Icon(_isDownloaded ? Icons.offline_pin_rounded : Icons.cloud_rounded, color: _isDownloaded ? Colors.green : Colors.grey, size: 20),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
              ],
            ),
          ),
        ),
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
                        setState(() => _readMode = val.first);
                        setModalState(() {});
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
    if (_nextChapter == null) {
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
          Text(
            isRu 
              ? 'Следующая: Том ${_nextChapter!.volume} Глава ${_nextChapter!.number}' 
              : 'Next: Volume ${_nextChapter!.volume} Chapter ${_nextChapter!.number}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          if (_nextChapter!.name != null && _nextChapter!.name!.isNotEmpty) ...[
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
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final branchQ = _nextChapter!.branchId != null ? "?branchId=${_nextChapter!.branchId}" : "";
              context.pushReplacement('/read/${widget.slugUrl}/${_nextChapter!.volume}/${_nextChapter!.number}$branchQ');
            },
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: Text(
              isRu ? 'Читать следующую главу' : 'Read Next Chapter',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
