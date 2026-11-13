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
import 'package:mangaloader/l10n/strings/reader_strings.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/providers/download_provider.dart';
import 'package:mangaloader/src/rust/api/download_engine.dart' as rust_download;
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/cbz_export.dart' as rust_cbz;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/services/streak_notification_service.dart';
import 'package:mangaloader/services/content_filter.dart';
import 'package:mangaloader/services/reader_bookmarks.dart';
import 'package:mangaloader/widgets/manga_comments_modal.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mangaloader/theme/app_tokens.dart';
import 'package:mangaloader/theme/app_theme.dart';

enum ReadMode { ltr, rtl, vertical }
enum ReadBgColor { black, darkGrey, white }
enum ReadBoxFit { contain, cover, fitWidth }
enum ReadColorFilter { none, invert, sepia }
enum ReadSharpenMode { off, subtle, high }
enum DualPageMode { auto, single, dual }
enum TapZoneLayout { standard, inverted, horizontal, edgesOnly }

enum _ReaderMenuAction {
  previousChapter,
  nextChapter,
  chapterList,
  pageGrid,
  bookmarks,
  autoScroll,
  comments,
  reload,
  fullscreen,
}

enum _ReaderPreset { webtoon, mangaRtl, comicLtr }

const double _chapterTileExtent = 72;

class ReaderPage extends ConsumerStatefulWidget {
  final String slugUrl;
  final String volume;
  final String number;
  final int? branchId;
  final String? localCbzPath;

  /// Page the chapter should open on, used when a bookmark points into another
  /// chapter. Overrides the saved reading progress for that chapter.
  final int? initialPageIndex;
  
  const ReaderPage({
    super.key, 
    required this.slugUrl, 
    required this.volume, 
    required this.number,
    this.branchId,
    this.localCbzPath,
    this.initialPageIndex,
  });

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  static const ReaderPrefs _defaultReaderPrefs = ReaderPrefs(
    mode: 'vertical',
    background: 'black',
    boxFit: 'contain',
    dualPage: 'auto',
    tapZones: 'standard',
    colorFilter: 'none',
    sharpen: 'off',
    cropBorders: false,
    cropPercent: 3.0,
    brightness: 1.0,
    autoScrollSpeed: 1.5,
    preloadRadius: 3,
    autoNextChapter: false,
  );

  final ValueNotifier<bool> _showControlsNotifier = ValueNotifier<bool>(false);
  ReadMode _readMode = ReadMode.vertical;
  ReadBgColor _bgColor = ReadBgColor.black;
  ReadBoxFit _boxFit = ReadBoxFit.contain;
  ReadColorFilter _filterMode = ReadColorFilter.none;
  ReadSharpenMode _sharpenMode = ReadSharpenMode.off;
  DualPageMode _dualPageMode = DualPageMode.auto;
  TapZoneLayout _tapZoneLayout = TapZoneLayout.standard;
  
  // Reading Time & Break Tracking
  DateTime _sessionStartTime = DateTime.now();
  int _continuousReadingMinutes = 0;
  Timer? _sessionTimer;
  
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
  int _preloadRadius = 4;
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
  Timer? _sliderDebounceTimer;
  double _titleDragDx = 0;

  bool _autoNextChapter = false;
  bool _isNextChapterPreparing = false;
  bool _isNextChapterReady = false;
  bool _showNextChapterBanner = false;
  bool _hasAutoAdvanced = false;
  int _nextChapterJob = 0;
  bool _prefetchNeighbours = true;
  int _neighbourJob = 0;

  // Measured page heights drive offset estimation so that jumping in the webtoon
  // list stays accurate without keeping every page mounted.
  final Map<int, double> _pageHeights = {};
  bool? _appliedDualLayout;
  
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
  List<ReaderBookmark> _bookmarks = const [];

  @override
  void initState() {
    super.initState();
    _restorePreferences();
    _sessionStartTime = DateTime.now();
    _sessionTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _continuousReadingMinutes++;
      final now = DateTime.now();
      final elapsed = now.difference(_sessionStartTime).inSeconds;
      if (elapsed >= 30 && _mangaId > 0) {
        rust_storage.recordReadingSession(mangaId: _mangaId, seconds: elapsed);
        _sessionStartTime = now;
      }
      if (_continuousReadingMinutes == 120 && mounted) {
        final s = ReaderStrings.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTokens.surfaceRaised,
            content: Row(
              children: [
                const Icon(Icons.timer_outlined, color: Colors.orangeAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.breakReminder,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: s.snooze,
              textColor: AppTokens.accent,
              onPressed: () {
                _continuousReadingMinutes = 90;
              },
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    });

    _scrollController.addListener(_onVerticalScroll);
    _chapterTitle = widget.localCbzPath != null
        ? widget.localCbzPath!
            .split(Platform.pathSeparator)
            .last
            .replaceAll(RegExp(r'\.(cbz|zip)$', caseSensitive: false), '')
            .replaceAll('_', ' ')
        : ReaderStrings(ref.read(localeProvider)?.languageCode != 'en')
            .chapterTitle(widget.volume, widget.number);
    _updateWindowTitle();
    _loadChapter();
  }

  void _restorePreferences() {
    final override = ref.read(titleReaderPrefsProvider)[widget.slugUrl];
    _applyReaderPrefs(override ?? ref.read(readerPrefsProvider));
  }

  void _resyncPreferencesWhileLoading() {
    if (!mounted || !_isLoading) return;
    _restorePreferences();
    setState(() {});
  }

  void _applyReaderPrefs(ReaderPrefs prefs) {
    _readMode = switch (prefs.mode) {
      'ltr' => ReadMode.ltr,
      'rtl' => ReadMode.rtl,
      _ => ReadMode.vertical,
    };
    _bgColor = switch (prefs.background) {
      'darkGrey' => ReadBgColor.darkGrey,
      'white' => ReadBgColor.white,
      _ => ReadBgColor.black,
    };
    _boxFit = switch (prefs.boxFit) {
      'cover' => ReadBoxFit.cover,
      'fitWidth' => ReadBoxFit.fitWidth,
      _ => ReadBoxFit.contain,
    };
    _dualPageMode = switch (prefs.dualPage) {
      'single' => DualPageMode.single,
      'dual' => DualPageMode.dual,
      _ => DualPageMode.auto,
    };
    _tapZoneLayout = switch (prefs.tapZones) {
      'inverted' => TapZoneLayout.inverted,
      'horizontal' => TapZoneLayout.horizontal,
      'edgesOnly' => TapZoneLayout.edgesOnly,
      _ => TapZoneLayout.standard,
    };
    _filterMode = switch (prefs.colorFilter) {
      'invert' => ReadColorFilter.invert,
      'sepia' => ReadColorFilter.sepia,
      _ => ReadColorFilter.none,
    };
    _sharpenMode = switch (prefs.sharpen) {
      'subtle' => ReadSharpenMode.subtle,
      'high' => ReadSharpenMode.high,
      _ => ReadSharpenMode.off,
    };
    _cropBorders = prefs.cropBorders;
    _cropPercent = prefs.cropPercent.clamp(1.0, 10.0);
    _brightness = prefs.brightness.clamp(0.2, 1.0);
    _autoScrollSpeed = prefs.autoScrollSpeed.clamp(0.5, 5.0);
    _preloadRadius = prefs.preloadRadius.clamp(1, 12);
    _autoNextChapter = prefs.autoNextChapter;
    _prefetchNeighbours = prefs.prefetchNeighbours;
  }

  /// Snapshot of the live reader state in the persisted [ReaderPrefs] format.
  ReaderPrefs get _currentPrefs => ReaderPrefs(
        mode: _readMode.name,
        background: _bgColor.name,
        boxFit: _boxFit.name,
        dualPage: _dualPageMode.name,
        tapZones: _tapZoneLayout.name,
        colorFilter: _filterMode.name,
        sharpen: _sharpenMode.name,
        cropBorders: _cropBorders,
        cropPercent: _cropPercent,
        brightness: _brightness,
        autoScrollSpeed: _autoScrollSpeed,
        preloadRadius: _preloadRadius,
        autoNextChapter: _autoNextChapter,
        prefetchNeighbours: _prefetchNeighbours,
      );

  /// Titles get their own override so manga (RTL) and webtoon entries can keep
  /// different profiles; locally opened CBZ files have no slug and only have the
  /// global profile to write to.
  void _persistPreferences() {
    final prefs = _currentPrefs;
    if (widget.slugUrl.isEmpty) {
      ref.read(readerPrefsProvider.notifier).update(prefs);
    } else {
      ref.read(titleReaderPrefsProvider.notifier).setForTitle(widget.slugUrl, prefs);
    }
  }

  bool get _hasTitleOverride =>
      widget.slugUrl.isNotEmpty &&
      ref.read(titleReaderPrefsProvider).containsKey(widget.slugUrl);

  /// Rebuilds the whole layout state from [prefs] while staying on the page the
  /// reader is currently showing, including across a vertical/paged switch.
  void _applyReaderPrefsKeepingPage(ReaderPrefs prefs) {
    final wasVertical = _readMode == ReadMode.vertical;
    setState(() {
      _applyReaderPrefs(prefs);
      final modeChanged = wasVertical != (_readMode == ReadMode.vertical);
      if (modeChanged) {
        _pageController?.dispose();
        _pageController = null;
        _appliedDualLayout = null;
      }
      if (modeChanged || !_autoNextChapter) _resetNextChapterTransition();
      if (!_prefetchNeighbours) _neighbourJob++;
    });

    final isVertical = _readMode == ReadMode.vertical;
    if (!isVertical) _stopAutoScroll();
    if (isVertical && !wasVertical) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToPageIndex(_currentPageIndex);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateNextChapterBanner();
    });
  }

  void _updatePrefs(ReaderPrefs next) {
    _applyReaderPrefsKeepingPage(next);
    _persistPreferences();
  }

  void _resetReaderSettings() {
    _applyReaderPrefsKeepingPage(_defaultReaderPrefs);
    _persistPreferences();
  }

  void _clearTitleOverride() {
    if (!_hasTitleOverride) return;
    final global = ref.read(readerPrefsProvider);
    ref.read(titleReaderPrefsProvider.notifier).clearForTitle(widget.slugUrl);
    _applyReaderPrefsKeepingPage(global);
  }

  ReaderPrefs _prefsForPreset(_ReaderPreset preset) => switch (preset) {
        _ReaderPreset.webtoon => _currentPrefs.copyWith(
            mode: ReadMode.vertical.name,
            boxFit: ReadBoxFit.fitWidth.name,
            tapZones: TapZoneLayout.standard.name,
            autoScrollSpeed: 1.5,
          ),
        _ReaderPreset.mangaRtl => _currentPrefs.copyWith(
            mode: ReadMode.rtl.name,
            boxFit: ReadBoxFit.contain.name,
            dualPage: DualPageMode.auto.name,
            tapZones: TapZoneLayout.standard.name,
          ),
        _ReaderPreset.comicLtr => _currentPrefs.copyWith(
            mode: ReadMode.ltr.name,
            boxFit: ReadBoxFit.contain.name,
            dualPage: DualPageMode.single.name,
          ),
      };

  void _applyPreset(_ReaderPreset preset) => _updatePrefs(_prefsForPreset(preset));

  void _resetNextChapterTransition() {
    _nextChapterJob++;
    _isNextChapterPreparing = false;
    _isNextChapterReady = false;
    _showNextChapterBanner = false;
  }

  bool _isNearChapterEnd() {
    if (_totalPages <= 0) return false;
    if (_currentPageIndex >= _totalPages - 2) return true;
    if (_readMode != ReadMode.vertical || !_scrollController.hasClients) return false;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <=
        MediaQuery.sizeOf(context).height * 1.5;
  }

  void _updateNextChapterBanner() {
    if (!_autoNextChapter || !_hasNextChapter || _hasAutoAdvanced) {
      if (_showNextChapterBanner) setState(() => _showNextChapterBanner = false);
      return;
    }
    final nearEnd = _isNearChapterEnd();
    if (nearEnd != _showNextChapterBanner) {
      setState(() => _showNextChapterBanner = nearEnd);
    }
    if (nearEnd) _prepareNextChapter();
  }

  /// Resolves the next chapter's page list and warms its first screens without
  /// touching the chapter that is currently on screen.
  Future<void> _prepareNextChapter() async {
    final next = _nextChapter;
    if (!_autoNextChapter) return;
    if (next == null) {
      if (_nextLocalCbzPath != null && !_isNextChapterReady && !_isNextChapterPreparing) {
        setState(() => _isNextChapterReady = true);
      }
      return;
    }
    if (_isNextChapterPreparing || _isNextChapterReady) return;

    final job = ++_nextChapterJob;
    setState(() => _isNextChapterPreparing = true);
    try {
      final isDownloaded = _mangaId > 0 &&
          await rust_storage.isChapterDownloaded(
            mangaId: _mangaId,
            volume: next.volume,
            number: next.number,
          );
      if (!mounted || job != _nextChapterJob) return;

      if (!isDownloaded) {
        final pages = await rust_api.getChapterPages(
          slugUrl: widget.slugUrl,
          volume: next.volume,
          number: next.number,
          branchId: next.branchId,
        );
        if (!mounted || job != _nextChapterJob) return;

        for (var i = 0; i < 3 && i < pages.length; i++) {
          try {
            await precacheImage(
              CachedNetworkImageProvider(
                _resolveImageUrl(pages[i].url),
                headers: const {'Referer': 'https://mangalib.org/'},
              ),
              context,
            );
          } catch (_) {}
          if (!mounted || job != _nextChapterJob) return;
        }
      }

      if (!mounted || job != _nextChapterJob) return;
      setState(() {
        _isNextChapterPreparing = false;
        _isNextChapterReady = true;
      });
    } catch (_) {
      if (!mounted || job != _nextChapterJob) return;
      setState(() => _isNextChapterPreparing = false);
    }
  }

  void _maybeAutoAdvanceToNextChapter() {
    if (!_autoNextChapter || _hasAutoAdvanced) return;
    if (_readMode != ReadMode.vertical || !_hasNextChapter) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 1) return;
    _hasAutoAdvanced = true;
    _showNextChapterBanner = false;
    _navigateToNextChapter();
  }

  int _findVisiblePageIndex() {
    if (_totalPages <= 1 || !_scrollController.hasClients) return 0;
    final target = _scrollController.offset + MediaQuery.of(context).size.height * 0.35;
    final fallback = _fallbackPageHeight();
    double accumulated = 0;
    for (int i = 0; i < _totalPages; i++) {
      accumulated += _pageHeights[i] ?? fallback;
      if (accumulated > target) return i;
    }
    return _totalPages - 1;
  }

  void _onPageMeasured(int index, double height) {
    if (height <= 0) return;
    final previous = _pageHeights[index];
    if (previous == null || (previous - height).abs() > 0.5) {
      _pageHeights[index] = height;
    }
  }

  double _fallbackPageHeight() {
    if (_pageHeights.isNotEmpty) {
      final total = _pageHeights.values.fold<double>(0, (sum, h) => sum + h);
      return total / _pageHeights.length;
    }
    return MediaQuery.of(context).size.width * _zoomLevel * 1.45;
  }

  double _pageTopOffset(int index) {
    final fallback = _fallbackPageHeight();
    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += _pageHeights[i] ?? fallback;
    }
    return offset;
  }

  int _slideForPageIndex(int pageIndex, bool isDual) =>
      isDual ? pageIndex ~/ 2 : pageIndex;

  int _slideCount(bool isDual) =>
      isDual ? (_totalPages + 1) ~/ 2 : _totalPages;

  /// The slide mapping depends on the viewport (auto dual-page mode kicks in on wide
  /// screens), so the controller has to be rebuilt when that mapping changes.
  void _syncDualLayout(bool isDual) {
    if (_appliedDualLayout == isDual) return;
    final hadLayout = _appliedDualLayout != null;
    _appliedDualLayout = isDual;
    if (!hadLayout) return;

    final slide = _slideForPageIndex(_currentPageIndex, isDual)
        .clamp(0, _slideCount(isDual) > 0 ? _slideCount(isDual) - 1 : 0);
    final previous = _pageController;
    _pageController = PageController(initialPage: slide);
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  void _onVerticalScroll() {
    if (_readMode != ReadMode.vertical || !_scrollController.hasClients || _totalPages <= 1) return;
    if (_isJumping) return;
    
    final currentVisible = _findVisiblePageIndex();
    
    if (currentVisible != _currentPageIndex) {
      _currentPageIndex = currentVisible;
      _pageIndexNotifier.value = currentVisible;
      if (!_isDownloaded) _preloadImages(currentVisible);
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

    _updateNextChapterBanner();
  }

  void _updateWindowTitle() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setTitle("Manga Loader - $_chapterTitle");
    }
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    final now = DateTime.now();
    final elapsed = now.difference(_sessionStartTime).inSeconds;
    if (elapsed > 0 && _mangaId > 0) {
      rust_storage.recordReadingSession(mangaId: _mangaId, seconds: elapsed);
    }
    _nextChapterJob++;
    _neighbourJob++;
    _scrollController.removeListener(_onVerticalScroll);
    _stopAutoScroll();
    _saveTimer?.cancel();
    _sliderDebounceTimer?.cancel();
    _showControlsNotifier.dispose();
    _pageIndexNotifier.dispose();
    if (_mangaId > 0 && _totalPages > 0) {
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
    if (ContentFilter.isBlockedText(widget.slugUrl) ||
        (widget.localCbzPath != null && ContentFilter.isBlockedText(widget.localCbzPath))) {
      setState(() {
        _isLoading = false;
        _errorMessage = ReaderStrings(
          ref.read(localeProvider)?.languageCode != 'en',
        ).contentBlocked;
      });
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });
    _pageCache.clear();
    _pageHeights.clear();
    _onlinePages = [];

    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    try {
      if (widget.localCbzPath != null && widget.localCbzPath!.isNotEmpty) {
        _cbzPath = widget.localCbzPath!;
        _isDownloaded = true;
        _totalPages = await rust_cbz.getCbzPageCount(cbzPath: _cbzPath);
        if (_totalPages == 0) {
          throw Exception(ReaderStrings(isRu).cbzReadFailed);
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

    // A bookmark opened from another chapter wins over the saved progress,
    // otherwise the jump would land on the wrong page.
    final initialPage = widget.initialPageIndex;
    if (initialPage != null && initialPage >= 0 && initialPage < _totalPages) {
      _currentPageIndex = initialPage;
    }

    if (_currentPageIndex >= _totalPages) {
      _currentPageIndex = 0;
    }

    _pageKeys = List.generate(_totalPages, (i) => GlobalKey(debugLabel: 'page_$i'));

    // The paged controller is created on the first layout pass, once the viewport
    // (and therefore the single/dual page mapping) is known.
    _pageController?.dispose();
    _pageController = null;
    _appliedDualLayout = null;
    _pageIndexNotifier.value = _currentPageIndex;

    setState(() => _isLoading = false);
    
    // For vertical mode, scroll to saved position after first frame
    if (_totalPages > 0 && _currentPageIndex > 0 && _readMode == ReadMode.vertical) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToPageIndex(_currentPageIndex);
      });
    }
    unawaited(_loadBookmarks());
  }

  void _jumpToPageIndex(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _totalPages) return;
    _currentPageIndex = targetIndex;
    _pageIndexNotifier.value = targetIndex;

    if (_readMode != ReadMode.vertical) {
      final controller = _pageController;
      if (controller != null && controller.hasClients) {
        final slide = _slideForPageIndex(targetIndex, _appliedDualLayout ?? false);
        controller.jumpToPage(slide.clamp(0, _slideCount(_appliedDualLayout ?? false) - 1));
      }
    } else if (_scrollController.hasClients) {
      _isJumping = true;
      final maxExtent = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(_pageTopOffset(targetIndex).clamp(0.0, maxExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) => _refineVerticalJump(targetIndex, 0));
    }
    _scheduleSaveProgress();
  }

  /// After landing near the estimated offset, align the target page to the top of the
  /// viewport using its real measured box. Retries a couple of frames while lazy
  /// building catches up with the requested position.
  void _refineVerticalJump(int target, int attempt, {double fraction = 0}) {
    if (!mounted || !_scrollController.hasClients) {
      _isJumping = false;
      return;
    }

    final ctx = target < _pageKeys.length ? _pageKeys[target].currentContext : null;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final deltaOnScreen = box.localToGlobal(Offset.zero).dy;
      final desired = _scrollController.offset +
          deltaOnScreen +
          (fraction > 0 ? fraction * box.size.height : 0);
      final maxExtent = _scrollController.position.maxScrollExtent;
      final clamped = desired.clamp(0.0, maxExtent);
      if ((clamped - _scrollController.offset).abs() > 1.0) {
        _scrollController.jumpTo(clamped);
      }
      _isJumping = false;
      return;
    }

    if (attempt >= 3) {
      _isJumping = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refineVerticalJump(target, attempt + 1, fraction: fraction),
    );
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
            unawaited(_prefetchPreviousChapter(_prevChapter!));
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
            unawaited(_prefetchPreviousChapter(_prevChapter!));
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
      if (mounted) {
        setState(() {});
        _updateNextChapterBanner();
      }
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
    if (!_prefetchNeighbours) return;
    await _warmChapterPages(next);
  }

  /// Previous chapters are opened less often than the next one, so they get a
  /// shallower warm-up: the page list and the first couple of images.
  Future<void> _prefetchPreviousChapter(Chapter previous) async {
    if (!_prefetchNeighbours) return;
    await _warmChapterPages(previous, maxPages: 2);
  }

  /// Loads the page list of [chapter] and caches its first screens. Nothing is
  /// written to the visible reader state, so a failure is silent.
  Future<void> _warmChapterPages(Chapter chapter, {int? maxPages}) async {
    final job = _neighbourJob;
    try {
      if (widget.slugUrl.isEmpty || _mangaId <= 0) return;
      final isDownloaded = await rust_storage.isChapterDownloaded(
        mangaId: _mangaId,
        volume: chapter.volume,
        number: chapter.number,
      );
      if (!mounted || job != _neighbourJob) return;
      if (isDownloaded) return;

      final pages = await rust_api.getChapterPages(
        slugUrl: widget.slugUrl,
        volume: chapter.volume,
        number: chapter.number,
        branchId: chapter.branchId,
      );
      if (!mounted || job != _neighbourJob) return;

      if (pages.isEmpty) return;
      final prefetchCount = (maxPages ?? _preloadRadius.clamp(1, 6))
          .clamp(1, pages.length);
      for (var i = 0; i < prefetchCount && i < pages.length; i++) {
        if (!mounted || job != _neighbourJob) return;
        unawaited(
          precacheImage(
            CachedNetworkImageProvider(
              _resolveImageUrl(pages[i].url),
              headers: const {'Referer': 'https://mangalib.org/'},
            ),
            context,
          ).catchError((_) {}),
        );
      }
    } catch (_) {}
  }

  Color get _resolvedBgColor {
    switch (_bgColor) {
      case ReadBgColor.black: return Colors.black;
      case ReadBgColor.darkGrey: return AppTokens.surfaceDeep;
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
    final end = startIndex + _preloadRadius;
    for (int i = startIndex; i < end && i < _onlinePages.length; i++) {
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
      // Keep a small window of decoded archive entries so page flips feel instant
      // without pinning a full chapter of bytes in memory.
      _pageCache[index] = data;
      _pageCache.removeWhere((k, _) => (k - index).abs() > 6);
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

    _updateNextChapterBanner();
  }

  void _scheduleSaveProgress() {
    if (_totalPages <= 0) return;
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
      // A chapter counts as read once the reader reached 90% of the pages, so the
      // last spread does not have to be opened for the chapter to be marked read.
      final threshold = _totalPages <= 1 ? 1 : (_totalPages * 0.9).ceil();
      final isCompleted = _totalPages > 0 && (_currentPageIndex + 1) >= threshold;
      await rust_storage.markChapterRead(
        mangaId: _mangaId, 
        volume: widget.volume, 
        number: widget.number, 
        pageIndex: _currentPageIndex, 
        totalPages: _totalPages, 
        isCompleted: isCompleted,
      );
      if (isCompleted) {
        if (mounted) {
          StreakNotificationService.scheduleDailyStreakReminder(
            isRu: Localizations.localeOf(context).languageCode == 'ru',
          );
        }
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

  bool _isDualPageActive(BuildContext context) {
    if (_readMode == ReadMode.vertical) return false;
    if (_dualPageMode == DualPageMode.single) return false;
    if (_dualPageMode == DualPageMode.dual) return true;
    final size = MediaQuery.of(context).size;
    return size.width >= 850 && size.width > size.height;
  }

  void _handleTap(TapUpDetails details) {
    final size = MediaQuery.of(context).size;
    final dx = details.globalPosition.dx;
    final dy = details.globalPosition.dy;
    final isRtl = _readMode == ReadMode.rtl;
    final isVertical = _readMode == ReadMode.vertical;

    if (_tapZoneLayout == TapZoneLayout.horizontal) {
      if (dy < size.height * 0.25) {
        _prevPageAction();
      } else if (dy > size.height * 0.75) {
        _nextPageAction();
      } else {
        _showControlsNotifier.value = !_showControlsNotifier.value;
      }
      return;
    }

    // In the continuous webtoon layout there is nothing to page through, so every tap
    // toggles the overlays instead of leaving dead zones on the screen edges.
    if (isVertical) {
      _showControlsNotifier.value = !_showControlsNotifier.value;
      return;
    }

    final edgeFraction = _tapZoneLayout == TapZoneLayout.edgesOnly ? 0.15 : 0.25;
    // "Inverted" swaps which edge advances; RTL already advances towards the left.
    final leftIsNext =
        _tapZoneLayout == TapZoneLayout.inverted ? !isRtl : isRtl;

    if (dx < size.width * edgeFraction) {
      if (leftIsNext) {
        _nextPageAction();
      } else {
        _prevPageAction();
      }
    } else if (dx > size.width * (1.0 - edgeFraction)) {
      if (leftIsNext) {
        _prevPageAction();
      } else {
        _nextPageAction();
      }
    } else {
      _showControlsNotifier.value = !_showControlsNotifier.value;
    }
  }

  /// Long press on the page opens the quick jump sheet. It is ignored while the
  /// chrome is visible so the overlay buttons keep their own long-press meaning.
  void _handleLongPress(LongPressStartDetails details) {
    if (_showControlsNotifier.value || _totalPages <= 0) return;
    _showPageJumpSheet();
  }

  void _prevPageAction() {
    if (_readMode == ReadMode.vertical) {
      if (_currentPageIndex > 0) _jumpToPageIndex(_currentPageIndex - 1);
      return;
    }
    final controller = _pageController;
    if (controller != null && controller.hasClients && (controller.page ?? 0) > 0) {
      controller.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _nextPageAction() {
    if (_readMode == ReadMode.vertical) {
      if (_currentPageIndex < _totalPages - 1) {
        _jumpToPageIndex(_currentPageIndex + 1);
      } else {
        _showEndOfChapter();
      }
      return;
    }

    final controller = _pageController;
    if (controller == null || !controller.hasClients) {
      _showEndOfChapter();
      return;
    }
    final isDual = _appliedDualLayout ?? false;
    final lastSlide = _slideCount(isDual) - 1;
    final currentSlide = (controller.page ?? _slideForPageIndex(_currentPageIndex, isDual)).round();
    if (currentSlide >= lastSlide) {
      _showEndOfChapter();
      return;
    }
    controller.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _showEndOfChapter() {
    _stopAutoScroll();
    final s = ReaderStrings.of(context);
    if (_nextChapter != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.nextChapterPrompt(_nextChapter!.volume, _nextChapter!.number)),
          action: SnackBarAction(
            label: s.read,
            onPressed: () {
              final branchQ = _nextChapter!.branchId != null ? "?branchId=${_nextChapter!.branchId}" : "";
              context.pushReplacement('/read/${widget.slugUrl}/${_nextChapter!.volume}/${_nextChapter!.number}$branchQ');
            },
          ),
          duration: const Duration(seconds: 4),
        )
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.endOfChapter)),
      );
    }
  }

  void _changeZoom(double newZoom) {
    newZoom = newZoom.clamp(0.5, 4.0);
    if (newZoom == _zoomLevel) return;

    if (_readMode != ReadMode.vertical || !_scrollController.hasClients) {
      setState(() => _zoomLevel = newZoom);
      return;
    }

    final visiblePage = _findVisiblePageIndex();
    double fractionInPage = 0.0;
    if (visiblePage < _pageKeys.length) {
      final box = _pageKeys[visiblePage].currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.size.height > 0) {
        fractionInPage = (-box.localToGlobal(Offset.zero).dy / box.size.height).clamp(0.0, 1.0);
      }
    }

    // Heights are expressed in pixels of the previous scale, so they must be re-measured.
    _isJumping = true;
    _pageHeights.clear();
    setState(() => _zoomLevel = newZoom);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        _isJumping = false;
        return;
      }
      final maxExtent = _scrollController.position.maxScrollExtent;
      final estimate = _pageTopOffset(visiblePage) +
          fractionInPage * _fallbackPageHeight();
      _scrollController.jumpTo(estimate.clamp(0.0, maxExtent));
      _refineVerticalJump(visiblePage, 0, fraction: fractionInPage);
    });
  }

  void _zoomIn() => _changeZoom(_zoomLevel + 0.25);

  void _zoomOut() => _changeZoom(_zoomLevel - 0.25);

  void _resetZoom() => _changeZoom(1.0);

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
    if (_isAutoScrolling) {
      _stopAutoScroll();
      return;
    }

    if (_readMode != ReadMode.vertical) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ReaderStrings.of(context).autoScrollWebtoonOnly)),
      );
      return;
    }

    setState(() {
      _isAutoScrolling = true;
      // 60 fps ticks keep the motion smooth; speed is expressed in px per second.
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (!_scrollController.hasClients) return;
        final nextOffset = _scrollController.offset + (_autoScrollSpeed * 60 * 0.016);
        if (nextOffset >= _scrollController.position.maxScrollExtent) {
          _stopAutoScroll();
          _showEndOfChapter();
        } else {
          _scrollController.jumpTo(nextOffset);
        }
      });
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
        SnackBar(content: Text(ReaderStrings.of(context).cacheCleared)),
      );
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    
    final isRtl = _readMode == ReadMode.rtl;
    final key = event.logicalKey;

    // Vertical mode: smooth scroll with arrow keys, space, pagedown/pageup
    if (_readMode == ReadMode.vertical && _scrollController.hasClients) {
      final viewportHeight = MediaQuery.of(context).size.height;
      if (key == LogicalKeyboardKey.arrowDown) {
        final target = (_scrollController.offset + viewportHeight * 0.25)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
        return;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        final target = (_scrollController.offset - viewportHeight * 0.25)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
        return;
      } else if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.pageDown) {
        final target = (_scrollController.offset + viewportHeight * 0.85)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        return;
      } else if (key == LogicalKeyboardKey.pageUp) {
        final target = (_scrollController.offset - viewportHeight * 0.85)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        return;
      }
    }

    // Horizontal mode navigation
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isRtl) {
        _prevPageAction();
      } else {
        _nextPageAction();
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (isRtl) {
        _nextPageAction();
      } else {
        _prevPageAction();
      }
    } else if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.space) {
      _nextPageAction();
    } else if (key == LogicalKeyboardKey.pageUp) {
      _prevPageAction();
    } else if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd) {
      _zoomIn();
    } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      _zoomOut();
    } else if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _resetZoom();
    } else if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.keyA) {
      if (_readMode == ReadMode.vertical) _toggleAutoScroll();
    } else if (key == LogicalKeyboardKey.home) {
      _jumpToPageIndex(0);
    } else if (key == LogicalKeyboardKey.end && _totalPages > 0) {
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
    final s = ReaderStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: Text(s.jumpToPage, style: const TextStyle(color: Colors.white)),
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
                      color: isCurrent ? AppTokens.accent : const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: isCurrent ? Colors.white : AppTokens.textPrimary,
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
              child: Text(s.close, style: const TextStyle(color: AppTokens.textPrimary)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Preferences come from the database on the app's first frame, which can land
    // after a deep link already mounted the reader. While the chapter is still
    // loading nothing has been laid out yet, so the stored profile can safely win.
    ref.listen<ReaderPrefs>(readerPrefsProvider, (_, __) => _resyncPreferencesWhileLoading());
    ref.listen<Map<String, ReaderPrefs>>(
      titleReaderPrefsProvider,
      (_, __) => _resyncPreferencesWhileLoading(),
    );

    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final s = ReaderStrings(isRu);

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
            _chapterTitle.isNotEmpty ? _chapterTitle : s.loadingChapter,
            style: const TextStyle(fontSize: 15, color: Colors.white),
          ),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppTokens.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTokens.borderStrong),
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
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: AppTokens.accent),
                ),
                const SizedBox(width: 12),
                Text(
                  s.loadingPages,
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
        backgroundColor: AppTokens.surfaceBase,
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
                color: AppTokens.surfaceRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppTokens.borderStrong),
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
                        style: const TextStyle(color: AppTokens.textPrimary, fontSize: 13, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTokens.accent,
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
                            foregroundColor: AppTokens.textPrimary,
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
          onLongPressStart: _handleLongPress,
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
                      title: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: _onTitleDragStart,
                        onHorizontalDragUpdate: _onTitleDragUpdate,
                        onHorizontalDragEnd: _onTitleDragEnd,
                        child: InkWell(
                          onTap: _allChapters.isNotEmpty ? _showChapterListDialog : null,
                          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(child: Text(_chapterTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                if (_allChapters.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_drop_down_rounded, size: 20, color: AppTokens.accent),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.tune_rounded),
                          tooltip: s.settings,
                          onPressed: _showSettingsSheet,
                        ),
                        PopupMenuButton<_ReaderMenuAction>(
                          tooltip: s.moreActions,
                          icon: const Icon(Icons.more_vert_rounded),
                          color: AppTokens.surfaceRaised,
                          position: PopupMenuPosition.under,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                            side: const BorderSide(color: AppTokens.borderStrong),
                          ),
                          onSelected: _handleMenuAction,
                          itemBuilder: (context) => [
                            if (hasPrev)
                              _buildMenuItem(
                                _ReaderMenuAction.previousChapter,
                                Icons.skip_previous_rounded,
                                s.previousChapter,
                              ),
                            if (hasNext)
                              _buildMenuItem(
                                _ReaderMenuAction.nextChapter,
                                Icons.skip_next_rounded,
                                s.nextChapter,
                              ),
                            if (hasPrev || hasNext) const PopupMenuDivider(height: 8),
                            if (_allChapters.isNotEmpty)
                              _buildMenuItem(
                                _ReaderMenuAction.chapterList,
                                Icons.format_list_bulleted_rounded,
                                s.chapterList,
                              ),
                            _buildMenuItem(
                              _ReaderMenuAction.pageGrid,
                              Icons.grid_view_rounded,
                              s.pageGrid,
                            ),
                            if (widget.slugUrl.isNotEmpty)
                              _buildMenuItem(
                                _ReaderMenuAction.bookmarks,
                                Icons.bookmarks_rounded,
                                s.bookmarks,
                              ),
                            if (_readMode == ReadMode.vertical)
                              _buildMenuItem(
                                _ReaderMenuAction.autoScroll,
                                _isAutoScrolling
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                _isAutoScrolling ? s.menuStopAutoScroll : s.menuAutoScroll,
                                color: _isAutoScrolling ? Colors.orangeAccent : null,
                              ),
                            const PopupMenuDivider(height: 8),
                            _buildMenuItem(
                              _ReaderMenuAction.comments,
                              Icons.chat_bubble_outline_rounded,
                              s.chapterComments,
                            ),
                            _buildMenuItem(
                              _ReaderMenuAction.reload,
                              Icons.refresh_rounded,
                              s.reloadChapter,
                            ),
                            _buildMenuItem(
                              _ReaderMenuAction.fullscreen,
                              _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                              _isFullscreen ? s.exitFullscreen : s.fullscreen,
                            ),
                          ],
                        ),
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
                            tooltip: s.zoomIn,
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
                            tooltip: s.zoomOut,
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
                                      activeColor: AppTokens.accent,
                                      inactiveColor: AppTokens.border,
                                      onChanged: (val) {
                                        final target = val.round();
                                        // Update visual indicator immediately
                                        _pageIndexNotifier.value = target;
                                        // Debounce the actual scroll jump
                                        _sliderDebounceTimer?.cancel();
                                        _sliderDebounceTimer = Timer(const Duration(milliseconds: 150), () {
                                          if (mounted && target != _currentPageIndex) {
                                            _jumpToPageIndex(target);
                                          }
                                        });
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
                                            label: Text(s.pageIndicator('${pageIndex + 1}', '$_totalPages'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          ),
                                          if (_allChapters.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.format_list_bulleted_rounded, size: 18, color: AppTokens.accent),
                                              tooltip: s.selectChapter,
                                              onPressed: _showChapterListDialog,
                                            ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          if (hasPrev)
                                            IconButton(
                                              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white70),
                                              tooltip: s.previousChapterInline,
                                              onPressed: _navigateToPrevChapter,
                                            ),
                                          if (hasNext) ...[
                                            FilledButton.tonalIcon(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: AppTokens.accent.withValues(alpha: 0.3),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                              onPressed: _navigateToNextChapter,
                                              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white),
                                              label: Text(
                                                _nextChapter != null ? 'Гл. ${_nextChapter!.number}' : s.nextChapterShort,
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

              ValueListenableBuilder<bool>(
                valueListenable: _showControlsNotifier,
                builder: (context, showControls, _) {
                  if (!_showNextChapterBanner) return const SizedBox.shrink();
                  final bottomInset = MediaQuery.paddingOf(context).bottom;
                  return Positioned(
                    left: 16,
                    right: 16,
                    // The control bar applies the bottom inset twice, so the banner
                    // has to clear it twice to stay above the bar.
                    bottom: showControls ? bottomInset * 2 + 128 : bottomInset + 44,
                    child: _buildNextChapterBanner(s),
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
                        color: AppTokens.surfaceRaised.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTokens.accent),
                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_circle_fill_rounded, size: 16, color: AppTokens.accent),
                          const SizedBox(width: 6),
                          Text(s.autoScrollLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.remove_rounded, size: 16, color: AppTokens.textPrimary),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () {
                              setState(() {
                                _autoScrollSpeed = (_autoScrollSpeed - 0.5).clamp(0.5, 5.0);
                              });
                              _persistPreferences();
                            },
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTokens.border,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_autoScrollSpeed}x',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_rounded, size: 16, color: AppTokens.textPrimary),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () {
                              setState(() {
                                _autoScrollSpeed = (_autoScrollSpeed + 0.5).clamp(0.5, 5.0);
                              });
                              _persistPreferences();
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
    final s = ReaderStrings(isRu);
    if (_totalPages == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded, color: Colors.grey, size: 48),
            const SizedBox(height: 16),
            Text(
              s.noPages,
              style: TextStyle(color: _bgColor == ReadBgColor.white ? Colors.black : Colors.white),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: Text(s.goBack),
            ),
          ],
        ),
      );
    } else if (_readMode == ReadMode.vertical) {
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Any manual drag takes control away from auto-scroll.
          if (_isAutoScrolling &&
              notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _stopAutoScroll();
          }
          if (notification is OverscrollNotification &&
              notification.overscroll > 0) {
            _maybeAutoAdvanceToNextChapter();
          }
          return false;
        },
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            itemCount: _totalPages + 1,
            itemBuilder: (context, i) {
              if (i == _totalPages) {
                return _buildNextChapterSwipeCard(isRu);
              }
              return _VerticalReaderPageItem(
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
                onMeasuredHeight: (height) => _onPageMeasured(i, height),
              );
            },
          ),
        ),
      );
    } else {
      final isDual = _isDualPageActive(context);
      _syncDualLayout(isDual);
      final dualSlidesCount = _slideCount(isDual);
      final totalItemsCount = dualSlidesCount + 1;
      final controller = _pageController ??= PageController(
        initialPage: _slideForPageIndex(_currentPageIndex, isDual),
      );

      return PageView.builder(
        controller: controller,
        itemCount: totalItemsCount,
        reverse: _readMode == ReadMode.rtl,
        onPageChanged: (slideIdx) {
          final targetPage = isDual ? (slideIdx * 2).clamp(0, _totalPages > 0 ? _totalPages - 1 : 0) : slideIdx;
          _onPageChanged(targetPage);
        },
        physics: const ClampingScrollPhysics(),
        itemBuilder: (context, index) {
          if (index == dualSlidesCount) {
            return Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildNextChapterSwipeCard(isRu),
                ),
              ),
            );
          }

          if (!isDual) {
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
          }

          final page1 = index * 2;
          final page2 = page1 + 1;
          final isRtl = _readMode == ReadMode.rtl;

          final item1 = _HorizontalReaderPageItem(
            key: ValueKey('h_page_$page1'),
            index: page1,
            isDownloaded: _isDownloaded,
            onlinePages: _onlinePages,
            resolveImageUrl: _resolveImageUrl,
            getCbzPage: _getCbzPage,
            reloadImage: _reloadImage,
            zoomLevel: _zoomLevel,
            cropBorders: _cropBorders,
            cropPercent: _cropPercent,
            boxFit: BoxFit.contain,
            applyColorFilter: _applyColorFilter,
          );

          final item2 = page2 < _totalPages
              ? _HorizontalReaderPageItem(
                  key: ValueKey('h_page_$page2'),
                  index: page2,
                  isDownloaded: _isDownloaded,
                  onlinePages: _onlinePages,
                  resolveImageUrl: _resolveImageUrl,
                  getCbzPage: _getCbzPage,
                  reloadImage: _reloadImage,
                  zoomLevel: _zoomLevel,
                  cropBorders: _cropBorders,
                  cropPercent: _cropPercent,
                  boxFit: BoxFit.contain,
                  applyColorFilter: _applyColorFilter,
                )
              : const SizedBox.expand();

          return Row(
            children: [
              Expanded(child: isRtl ? item2 : item1),
              Container(width: 1, color: Colors.black26),
              Expanded(child: isRtl ? item1 : item2),
            ],
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

  bool get _hasPrevChapter => _prevChapter != null || _prevLocalCbzPath != null;

  bool get _hasNextChapter => _nextChapter != null || _nextLocalCbzPath != null;

  void _onTitleDragStart(DragStartDetails details) => _titleDragDx = 0;

  void _onTitleDragUpdate(DragUpdateDetails details) => _titleDragDx += details.delta.dx;

  void _onTitleDragEnd(DragEndDetails details) {
    final dx = _titleDragDx;
    _titleDragDx = 0;
    if (dx.abs() < 40) return;
    if (dx < 0 && _hasNextChapter) {
      _navigateToNextChapter();
    } else if (dx > 0 && _hasPrevChapter) {
      _navigateToPrevChapter();
    }
  }

  void _handleMenuAction(_ReaderMenuAction action) {
    switch (action) {
      case _ReaderMenuAction.previousChapter:
        _navigateToPrevChapter();
        break;
      case _ReaderMenuAction.nextChapter:
        _navigateToNextChapter();
        break;
      case _ReaderMenuAction.chapterList:
        _showChapterListDialog();
        break;
      case _ReaderMenuAction.pageGrid:
        _showPageJumperDialog();
        break;
      case _ReaderMenuAction.bookmarks:
        _showBookmarksSheet();
        break;
      case _ReaderMenuAction.autoScroll:
        _toggleAutoScroll();
        break;
      case _ReaderMenuAction.comments:
        _showChapterComments();
        break;
      case _ReaderMenuAction.reload:
        unawaited(_reloadCurrentChapter());
        break;
      case _ReaderMenuAction.fullscreen:
        _toggleFullscreen();
        break;
    }
  }

  PopupMenuItem<_ReaderMenuAction> _buildMenuItem(
    _ReaderMenuAction action,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem<_ReaderMenuAction>(
      value: action,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? AppTokens.textPrimary),
          const SizedBox(width: AppTokens.spaceMd),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: color ?? Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showChapterComments() {
    final s = ReaderStrings.of(context);
    final currentChap = _allChapters.firstWhere(
      (c) => c.volume == widget.volume && c.number == widget.number,
      orElse: () => Chapter(
        id: _mangaId,
        volume: widget.volume,
        number: widget.number,
        name: null,
        branchId: widget.branchId,
        branchesCount: 1,
        isPaid: false,
      ),
    );
    MangaCommentsModal.show(
      context,
      relationType: currentChap.id > 0 ? 'chapter' : 'media',
      relationId: currentChap.id > 0 ? currentChap.id : _mangaId,
      title: s.commentsTitle(widget.slugUrl, widget.volume, widget.number),
    );
  }

  Future<void> _loadBookmarks() async {
    if (_mangaId <= 0) return;
    final bookmarks = await ReaderBookmarkService.forManga(_mangaId);
    if (!mounted) return;
    setState(() => _bookmarks = bookmarks);
  }

  bool _isBookmarkedAt(int pageIndex) =>
      _mangaId > 0 &&
      ReaderBookmarkService.contains(
        _bookmarks,
        mangaId: _mangaId,
        volume: widget.volume,
        number: widget.number,
        pageIndex: pageIndex,
      );

  /// Returns the new state of the page so an open sheet can update its button
  /// without waiting for the parent rebuild.
  Future<bool> _toggleBookmarkAt(int pageIndex) async {
    if (_mangaId <= 0 || widget.slugUrl.isEmpty) return false;
    final s = ReaderStrings.of(context);
    final existed = _isBookmarkedAt(pageIndex);
    final bookmark = ReaderBookmark(
      mangaId: _mangaId,
      slugUrl: widget.slugUrl,
      volume: widget.volume,
      number: widget.number,
      pageIndex: pageIndex,
      chapterTitle: _chapterTitle,
      createdAt: DateTime.now(),
    );
    final updated = await ReaderBookmarkService.toggle(bookmark);
    if (!mounted) return !existed;
    setState(() {
      _bookmarks = updated.where((entry) => entry.mangaId == _mangaId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(existed ? s.bookmarkRemoved : s.bookmarkSaved),
        duration: const Duration(seconds: 2),
      ),
    );
    return !existed;
  }

  void _showPageJumpSheet() {
    if (_totalPages <= 0) return;
    final s = ReaderStrings.of(context);
    var target = _currentPageIndex.clamp(0, _totalPages - 1);
    var marked = _isBookmarkedAt(target);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTokens.surfaceBase,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTokens.borderStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.alt_route_rounded, size: 18, color: AppTokens.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.pageJumpTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Text(
                        s.pagePosition('${target + 1}', '$_totalPages'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if (_totalPages > 1)
                    Slider(
                      value: (target + 1).toDouble().clamp(1, _totalPages.toDouble()),
                      min: 1,
                      max: _totalPages.toDouble(),
                      divisions: _totalPages - 1,
                      activeColor: AppTokens.accent,
                      onChanged: (value) {
                        setSheet(() {
                          target = value.round().clamp(1, _totalPages) - 1;
                          marked = _isBookmarkedAt(target);
                        });
                      },
                    )
                  else
                    const SizedBox(height: 10),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (widget.slugUrl.isNotEmpty) ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: marked ? AppTokens.accent : AppTokens.textPrimary,
                            side: BorderSide(
                              color: marked ? AppTokens.accent : AppTokens.borderStrong,
                            ),
                            minimumSize: const Size(0, 40),
                          ),
                          onPressed: () async {
                            final added = await _toggleBookmarkAt(target);
                            if (ctx.mounted) setSheet(() => marked = added);
                          },
                          icon: Icon(
                            marked ? Icons.bookmark_remove_rounded : Icons.bookmark_add_outlined,
                            size: 18,
                          ),
                          label: Text(marked ? s.bookmarkRemove : s.bookmarkAdd),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTokens.accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(40),
                          ),
                          onPressed: () {
                            _jumpToPageIndex(target);
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.my_location_rounded, size: 18),
                          label: Text(s.jump),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _removeBookmark(ReaderBookmark bookmark) async {
    final updated = await ReaderBookmarkService.remove(bookmark);
    if (!mounted) return;
    setState(() {
      _bookmarks = updated.where((entry) => entry.mangaId == _mangaId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  void _openBookmark(ReaderBookmark bookmark) {
    if (bookmark.volume == widget.volume && bookmark.number == widget.number) {
      _jumpToPageIndex(bookmark.pageIndex);
      Navigator.pop(context);
      return;
    }
    context.pushReplacement(
      '/read/${bookmark.slugUrl}/${bookmark.volume}/${bookmark.number}?page=${bookmark.pageIndex}',
    );
  }

  void _showBookmarksSheet() {
    final s = ReaderStrings.of(context);
    var list = List<ReaderBookmark>.of(_bookmarks);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTokens.surfaceBase,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    decoration: BoxDecoration(
                      color: AppTokens.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmarks_rounded, size: 18, color: AppTokens.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.bookmarks,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: s.close,
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppTokens.border),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bookmark_border_rounded,
                            size: 32,
                            color: AppTokens.textSecondary,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            s.bookmarksEmpty,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 52, color: AppTokens.border),
                        itemBuilder: (_, index) {
                          final bookmark = list[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.bookmark_rounded,
                              size: 19,
                              color: AppTokens.accent,
                            ),
                            title: Text(
                              bookmark.chapterTitle.isEmpty
                                  ? s.bookmarkChapter(bookmark.volume, bookmark.number)
                                  : bookmark.chapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              s.bookmarkPage('${bookmark.pageIndex + 1}'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTokens.textSecondary,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: s.deleteBookmark,
                              icon: const Icon(Icons.delete_outline_rounded, size: 19),
                              onPressed: () async {
                                await _removeBookmark(bookmark);
                                if (!ctx.mounted) return;
                                setSheet(() {
                                  list = List<ReaderBookmark>.of(_bookmarks);
                                });
                              },
                            ),
                            onTap: () => _openBookmark(bookmark),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showChapterListDialog() {
    if (_allChapters.isEmpty) return;
    final s = ReaderStrings.of(context);
    String filterQuery = '';

    final currentIndex = _allChapters.indexWhere(
      (c) => c.volume == widget.volume && c.number == widget.number,
    );
    final initialOffset = currentIndex <= 2
        ? 0.0
        : (currentIndex - 2) * _chapterTileExtent;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.surfaceBase,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
      ),
      builder: (ctx) => _ChapterListScrollHost(
        initialOffset: initialOffset,
        builder: (scrollController) => StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = _allChapters.where((c) {
              if (filterQuery.isEmpty) return true;
              final q = filterQuery.toLowerCase();
              return c.number.contains(q) || c.volume.contains(q) || (c.name ?? '').toLowerCase().contains(q);
            }).toList();

            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.7,
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTokens.borderStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.format_list_bulleted_rounded, color: AppTokens.accent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            s.chapterListTitle('${_allChapters.length}'),
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
                          hintText: s.searchChapter,
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          isDense: true,
                          filled: true,
                          fillColor: AppTokens.surfaceRaised,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (val) => setModalState(() => filterQuery = val.trim()),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        itemExtent: _chapterTileExtent,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final c = filtered[i];
                          final isCurrent = c.volume == widget.volume && c.number == widget.number;

                          return ListTile(
                            selected: isCurrent,
                            selectedTileColor: AppTokens.accent.withValues(alpha: 0.18),
                            shape: isCurrent
                                ? RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                                    side: BorderSide(color: AppTokens.accent.withValues(alpha: 0.7)),
                                  )
                                : null,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: isCurrent ? AppTokens.accent : AppTokens.surfaceRaised,
                              child: Text(
                                c.number,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isCurrent ? Colors.white : AppTokens.textPrimary,
                                ),
                              ),
                            ),
                            title: Text(
                              s.volumeChapter(c.volume, c.number),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                color: isCurrent ? Colors.white : AppTokens.textPrimary,
                              ),
                            ),
                            subtitle: c.name != null && c.name!.isNotEmpty
                                ? Text(c.name!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54))
                                : null,
                            trailing: c.isPaid
                                ? const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.amber)
                                : isCurrent
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTokens.accent.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppTokens.accent.withValues(alpha: 0.6)),
                                        ),
                                        child: Text(
                                          s.youAreHere,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppTokens.accent,
                                          ),
                                        ),
                                      )
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
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final s = ReaderStrings.of(sheetContext);
            final isVertical = _readMode == ReadMode.vertical;

            void refresh() => setModalState(() {});

            void select(ReaderPrefs next) {
              _updatePrefs(next);
              refresh();
            }

            Widget sliderRow({
              required String label,
              required String value,
              required double min,
              required double max,
              required int divisions,
              required double current,
              required ValueChanged<double> apply,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReaderSheetRow(
                    label: label,
                    control: _ReaderSheetValueBadge(value),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(sheetContext).copyWith(
                      trackHeight: 3,
                      activeTrackColor: AppTokens.accent,
                      inactiveTrackColor: AppTokens.border,
                      thumbColor: AppTokens.textPrimary,
                      overlayColor: AppTokens.accent.withValues(alpha: 0.12),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: current,
                      min: min,
                      max: max,
                      divisions: divisions,
                      onChanged: (val) {
                        setState(() => apply(val));
                        refresh();
                      },
                      onChangeEnd: (_) => _persistPreferences(),
                    ),
                  ),
                ],
              );
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.92,
              ),
              decoration: const BoxDecoration(
                color: AppTokens.surfaceBase,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      decoration: BoxDecoration(
                        color: AppTokens.borderStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                      child: Row(
                        children: [
                          const Icon(Icons.tune_rounded, size: 18, color: AppTokens.accent),
                          const SizedBox(width: AppTokens.spaceSm),
                          Expanded(
                            child: Text(
                              s.readerSettings,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AppTokens.accent,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm),
                            ),
                            onPressed: () {
                              _resetReaderSettings();
                              refresh();
                            },
                            child: Text(
                              s.resetSettings,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppTokens.border),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_hasTitleOverride) ...[
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  AppTokens.spaceMd,
                                  AppTokens.spaceXs,
                                  AppTokens.spaceXs,
                                  AppTokens.spaceXs,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTokens.accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                                  border: Border.all(color: AppTokens.accent.withValues(alpha: 0.45)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.bookmark_added_rounded, size: 15, color: AppTokens.accent),
                                    const SizedBox(width: AppTokens.spaceSm),
                                    Expanded(
                                      child: Text(
                                        s.titleOverrideNotice,
                                        style: const TextStyle(fontSize: 11.5, height: 1.3, color: AppTokens.textPrimary),
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppTokens.accent,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm),
                                      ),
                                      onPressed: () {
                                        _clearTitleOverride();
                                        refresh();
                                      },
                                      child: Text(
                                        s.resetToGlobalSettings,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppTokens.spaceMd),
                            ],
                            _ReaderSheetCard(
                              icon: Icons.chrome_reader_mode_outlined,
                              title: s.sectionMode,
                              children: [
                                Wrap(
                                  spacing: AppTokens.spaceSm,
                                  runSpacing: AppTokens.spaceSm,
                                  children: [
                                    _ReaderPresetChip(
                                      icon: Icons.view_day_rounded,
                                      label: s.presetWebtoon,
                                      selected: isVertical &&
                                          _boxFit == ReadBoxFit.fitWidth &&
                                          _tapZoneLayout == TapZoneLayout.standard &&
                                          _autoScrollSpeed == 1.5,
                                      onTap: () {
                                        _applyPreset(_ReaderPreset.webtoon);
                                        refresh();
                                      },
                                    ),
                                    _ReaderPresetChip(
                                      icon: Icons.menu_book_rounded,
                                      label: s.presetMangaRtl,
                                      selected: _readMode == ReadMode.rtl &&
                                          _boxFit == ReadBoxFit.contain &&
                                          _dualPageMode == DualPageMode.auto &&
                                          _tapZoneLayout == TapZoneLayout.standard,
                                      onTap: () {
                                        _applyPreset(_ReaderPreset.mangaRtl);
                                        refresh();
                                      },
                                    ),
                                    _ReaderPresetChip(
                                      icon: Icons.auto_stories_rounded,
                                      label: s.presetComicLtr,
                                      selected: _readMode == ReadMode.ltr &&
                                          _boxFit == ReadBoxFit.contain &&
                                          _dualPageMode == DualPageMode.single,
                                      onTap: () {
                                        _applyPreset(_ReaderPreset.comicLtr);
                                        refresh();
                                      },
                                    ),
                                  ],
                                ),
                                _ReaderSheetRow(
                                  label: s.readingMode,
                                  control: _ReaderSheetSelect<ReadMode>(
                                    value: _readMode,
                                    options: [
                                      _ReaderSheetOption(ReadMode.vertical, s.modeWebtoon),
                                      _ReaderSheetOption(ReadMode.ltr, s.modeLtr),
                                      _ReaderSheetOption(ReadMode.rtl, s.modeRtl),
                                    ],
                                    onChanged: (mode) =>
                                        select(_currentPrefs.copyWith(mode: mode.name)),
                                  ),
                                ),
                                if (!isVertical) ...[
                                  _ReaderSheetRow(
                                    label: s.pageLayout,
                                    control: _ReaderSheetSelect<DualPageMode>(
                                      value: _dualPageMode,
                                      options: [
                                        _ReaderSheetOption(DualPageMode.auto, s.layoutAuto),
                                        _ReaderSheetOption(DualPageMode.single, s.layoutSingle),
                                        _ReaderSheetOption(DualPageMode.dual, s.layoutDual),
                                      ],
                                      onChanged: (layout) =>
                                          select(_currentPrefs.copyWith(dualPage: layout.name)),
                                    ),
                                  ),
                                  _ReaderSheetRow(
                                    label: s.pageScale,
                                    control: _ReaderSheetSelect<ReadBoxFit>(
                                      value: _boxFit,
                                      options: [
                                        _ReaderSheetOption(ReadBoxFit.contain, s.scaleFitScreen),
                                        _ReaderSheetOption(ReadBoxFit.fitWidth, s.scaleFitWidth),
                                        _ReaderSheetOption(ReadBoxFit.cover, s.scaleCover),
                                      ],
                                      onChanged: (fit) =>
                                          select(_currentPrefs.copyWith(boxFit: fit.name)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            _ReaderSheetCard(
                              icon: Icons.touch_app_rounded,
                              title: s.sectionNavigation,
                              children: [
                                _ReaderSheetRow(
                                  label: s.tapZones,
                                  control: _ReaderSheetSelect<TapZoneLayout>(
                                    value: _tapZoneLayout,
                                    options: [
                                      _ReaderSheetOption(TapZoneLayout.standard, s.tapStandard),
                                      _ReaderSheetOption(TapZoneLayout.inverted, s.tapInverted),
                                      _ReaderSheetOption(TapZoneLayout.edgesOnly, s.tapEdges),
                                    ],
                                    onChanged: (zones) =>
                                        select(_currentPrefs.copyWith(tapZones: zones.name)),
                                  ),
                                ),
                              ],
                            ),
                            _ReaderSheetCard(
                              icon: Icons.image_outlined,
                              title: s.sectionImage,
                              children: [
                                _ReaderSheetRow(
                                  label: s.backgroundColor,
                                  control: _ReaderSheetSelect<ReadBgColor>(
                                    value: _bgColor,
                                    options: [
                                      _ReaderSheetOption(ReadBgColor.black, s.bgBlack),
                                      _ReaderSheetOption(ReadBgColor.darkGrey, s.bgGrey),
                                      _ReaderSheetOption(ReadBgColor.white, s.bgWhite),
                                    ],
                                    onChanged: (bg) =>
                                        select(_currentPrefs.copyWith(background: bg.name)),
                                  ),
                                ),
                                sliderRow(
                                  label: s.pageBrightness,
                                  value: '${(_brightness * 100).toInt()}%',
                                  min: 0.2,
                                  max: 1.0,
                                  divisions: 16,
                                  current: _brightness,
                                  apply: (val) => _brightness = val,
                                ),
                                _ReaderSheetRow(
                                  label: s.colorFilter,
                                  control: _ReaderSheetSelect<ReadColorFilter>(
                                    value: _filterMode,
                                    options: [
                                      _ReaderSheetOption(ReadColorFilter.none, s.filterNormal),
                                      _ReaderSheetOption(ReadColorFilter.invert, s.filterInvert),
                                      _ReaderSheetOption(ReadColorFilter.sepia, s.filterSepia),
                                    ],
                                    onChanged: (filter) =>
                                        select(_currentPrefs.copyWith(colorFilter: filter.name)),
                                  ),
                                ),
                                _ReaderSheetRow(
                                  label: s.sharpeningFilter,
                                  control: _ReaderSheetSelect<ReadSharpenMode>(
                                    value: _sharpenMode,
                                    options: [
                                      _ReaderSheetOption(ReadSharpenMode.off, s.sharpeningOff),
                                      _ReaderSheetOption(ReadSharpenMode.subtle, s.sharpeningSubtle),
                                      _ReaderSheetOption(ReadSharpenMode.high, s.sharpeningHigh),
                                    ],
                                    onChanged: (sharpen) =>
                                        select(_currentPrefs.copyWith(sharpen: sharpen.name)),
                                  ),
                                ),
                                _ReaderSheetRow(
                                  label: s.cropBorders,
                                  subtitle: s.cropBordersSubtitle,
                                  control: Switch(
                                    value: _cropBorders,
                                    onChanged: (val) =>
                                        select(_currentPrefs.copyWith(cropBorders: val)),
                                  ),
                                ),
                                if (_cropBorders)
                                  sliderRow(
                                    label: s.cropMargin,
                                    value: '${_cropPercent.toInt()}%',
                                    min: 1.0,
                                    max: 10.0,
                                    divisions: 9,
                                    current: _cropPercent,
                                    apply: (val) => _cropPercent = val,
                                  ),
                              ],
                            ),
                            _ReaderSheetCard(
                              icon: Icons.swap_vert_rounded,
                              title: s.sectionScrolling,
                              children: [
                                sliderRow(
                                  label: s.autoScrollSpeed,
                                  value: '${_autoScrollSpeed.toStringAsFixed(1)}x',
                                  min: 0.5,
                                  max: 5.0,
                                  divisions: 9,
                                  current: _autoScrollSpeed,
                                  apply: (val) => _autoScrollSpeed = val,
                                ),
                                sliderRow(
                                  label: s.pagePreload,
                                  value: '${_preloadRadius.clamp(1, 10)}',
                                  min: 1,
                                  max: 10,
                                  divisions: 9,
                                  current: _preloadRadius.toDouble().clamp(1.0, 10.0),
                                  apply: (val) => _preloadRadius = val.round().clamp(1, 12),
                                ),
                              ],
                            ),
                            _ReaderSheetCard(
                              icon: Icons.double_arrow_rounded,
                              title: s.sectionTransitions,
                              children: [
                                _ReaderSheetRow(
                                  label: s.autoNextChapterTitle,
                                  subtitle: s.autoNextChapterSubtitle,
                                  control: Switch(
                                    value: _autoNextChapter,
                                    onChanged: (val) =>
                                        select(_currentPrefs.copyWith(autoNextChapter: val)),
                                  ),
                                ),
                                _ReaderSheetRow(
                                  label: s.prefetchNeighboursTitle,
                                  subtitle: s.prefetchNeighboursSubtitle,
                                  control: Switch(
                                    value: _prefetchNeighbours,
                                    onChanged: (val) =>
                                        select(_currentPrefs.copyWith(prefetchNeighbours: val)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildNextChapterBanner(ReaderStrings s) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: AppTokens.surfaceRaised.withValues(alpha: 0.94),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: AppTokens.accent.withValues(alpha: 0.55)),
        ),
        child: InkWell(
          onTap: _navigateToNextChapter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.skip_next_rounded, size: 16, color: AppTokens.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _nextChapter != null ? s.nextChapterBanner(_nextChapter!.number) : s.nextChapter,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                if (_isNextChapterPreparing)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: AppTokens.accent),
                  )
                else if (_isNextChapterReady) ...[
                  const Icon(Icons.check_circle_rounded, size: 13, color: AppTokens.accent),
                  const SizedBox(width: 4),
                  Text(
                    s.nextChapterReady,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTokens.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNextChapterSwipeCard(bool isRu) {
    final s = ReaderStrings(isRu);
    if (_nextChapter == null && _nextLocalCbzPath == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTokens.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF383838)),
        ),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 40, color: AppTokens.accent),
            const SizedBox(height: 12),
            Text(
              s.latestChapterReached,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              s.stayTuned,
              style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
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
                    ? s.previousWithNumber(_prevChapter!.volume, _prevChapter!.number)
                    : s.previousChapter,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_allChapters.isNotEmpty) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTokens.textPrimary,
                  side: const BorderSide(color: AppTokens.accent),
                  minimumSize: const Size.fromHeight(42),
                ),
                onPressed: _showChapterListDialog,
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
                label: Text(s.allChapters),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTokens.accent,
                side: const BorderSide(color: AppTokens.accent),
                minimumSize: const Size.fromHeight(42),
              ),
              onPressed: () async {
                await _findNextChapter();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_nextChapter != null
                          ? s.nextChapterFound(_nextChapter!.volume, _nextChapter!.number)
                          : s.noNewChapters),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(s.checkNewChapters),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.accent.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_stories_rounded, color: AppTokens.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                s.chapterComplete,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_nextChapter != null)
            Text(
              s.nextWithNumber(_nextChapter!.volume, _nextChapter!.number),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              textAlign: TextAlign.center,
            )
          else if (_nextLocalCbzPath != null)
            Text(
              s.nextChapter,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          if (_nextChapter?.name != null && _nextChapter!.name!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _nextChapter!.name!,
              style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _navigateToNextChapter,
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: Text(
              s.readNextChapter,
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
              label: Text(s.chapterListCased),
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
                  ? s.previousWithNumber(_prevChapter!.volume, _prevChapter!.number)
                  : s.previousChapter,
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
  final void Function(double) onMeasuredHeight;

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
    required this.onMeasuredHeight,
  });

  @override
  State<_VerticalReaderPageItem> createState() => _VerticalReaderPageItemState();
}

class _VerticalReaderPageItemState extends State<_VerticalReaderPageItem> {
  Uint8List? _cbzBytes;
  bool _isLoadingCbz = false;
  bool _cbzError = false;
  double _reportedHeight = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isDownloaded) {
      _loadCbzBytes();
    }
  }

  @override
  void didUpdateWidget(covariant _VerticalReaderPageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The chapter can be downloaded (or auto-deleted) while it is open.
    if (widget.isDownloaded && !oldWidget.isDownloaded) {
      _loadCbzBytes();
    }
  }

  void _reportHeight() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if ((box.size.height - _reportedHeight).abs() < 1.0) return;
    _reportedHeight = box.size.height;
    widget.onMeasuredHeight(box.size.height);
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
    // Height is reported after layout so the parent can keep jump targets accurate
    // without mounting every page of the chapter.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());

    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth * widget.zoomLevel;

    double? knownAspectRatio;
    if (widget.index < widget.onlinePages.length) {
      final p = widget.onlinePages[widget.index];
      if (p.width != null && p.height != null && p.width! > 0 && p.height! > 0) {
        knownAspectRatio = p.width! / p.height!;
      }
    }

    // Decoding a 2000px wide manga page at its source resolution would pin megabytes
    // of RAM per page; decode at the on-screen pixel width instead.
    final cacheWidth =
        (itemWidth * MediaQuery.devicePixelRatioOf(context)).round().clamp(128, 4096);
    final cacheHeight = knownAspectRatio != null
        ? (cacheWidth / knownAspectRatio).round().clamp(128, 8192)
        : null;

    // Use known aspect ratio for accurate placeholder; fallback to generous 1.4x for unknown
    final placeholderHeight = (knownAspectRatio != null && knownAspectRatio > 0)
        ? itemWidth / knownAspectRatio
        : itemWidth * 1.4;

    Widget content;
    if (widget.isDownloaded) {
      if (_cbzBytes != null) {
        // Let the image determine its own height from intrinsic aspect ratio.
        // ConstrainedBox(maxWidth) will limit width; fitWidth scales height proportionally.
        content = Image.memory(
          _cbzBytes!,
          fit: BoxFit.fitWidth,
          width: itemWidth,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
        );
      } else if (_cbzError) {
        content = Container(
          width: itemWidth,
          height: placeholderHeight,
          color: AppTokens.surfaceDeep,
          child: const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
        );
      } else {
        content = Container(
          width: itemWidth,
          height: placeholderHeight,
          color: AppTokens.surfaceDeep,
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
        filterQuality: FilterQuality.high,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        // Do NOT set width/height on CachedNetworkImage — use imageBuilder for proper sizing
        imageBuilder: (ctx, imageProvider) => Image(
          image: imageProvider,
          width: itemWidth,
          fit: BoxFit.fitWidth,
          filterQuality: FilterQuality.high,
        ),
        placeholder: (ctx, url) => Container(
          width: itemWidth,
          height: placeholderHeight,
          color: AppTokens.surfaceDeep,
          child: const Center(
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
        errorWidget: (ctx, url, err) => InkWell(
          onTap: () => widget.reloadImage(pageUrl),
          child: Container(
            width: itemWidth,
            height: placeholderHeight,
            color: AppTokens.surfaceDeep,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded, color: Colors.white70, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    ReaderStrings.of(context).tapToRetry,
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
        width: itemWidth,
        height: placeholderHeight,
        color: AppTokens.surfaceDeep,
        child: const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
      );
    }

    if (widget.cropBorders) {
      final scaleFactor = 1.0 + (widget.cropPercent * 2 / 100.0);
      content = ClipRect(
        child: Transform.scale(scale: scaleFactor, child: content),
      );
    }

    // Use Align + ConstrainedBox: width is bounded to itemWidth, height is unconstrained.
    // This prevents tall images from being vertically compressed.
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Align(
        alignment: Alignment.center,
        child: widget.applyColorFilter(content),
      ),
    );
  }
}

/// Dedicated horizontal page item with its own zoom transform. InteractiveViewer is
/// mounted only while zoomed so PageView keeps receiving horizontal swipes.
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

class _HorizontalReaderPageItemState extends State<_HorizontalReaderPageItem>
    with SingleTickerProviderStateMixin {
  static const double _doubleTapScale = 2.5;

  Uint8List? _cbzBytes;
  bool _isLoadingCbz = false;
  bool _cbzError = false;

  final TransformationController _transformController = TransformationController();
  late final AnimationController _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;
  Offset _doubleTapPosition = Offset.zero;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isDownloaded) {
      _loadCbzBytes();
    }
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(_applyZoomFrame);
    _transformController.addListener(_syncZoomFlag);
  }

  @override
  void dispose() {
    _zoomAnimationController.dispose();
    _transformController.removeListener(_syncZoomFlag);
    _transformController.dispose();
    super.dispose();
  }

  double get _matrixScale => _transformController.value.getMaxScaleOnAxis();

  void _applyZoomFrame() {
    final animation = _zoomAnimation;
    if (animation != null) _transformController.value = animation.value;
  }

  /// InteractiveViewer owns a scale recognizer that would swallow the horizontal
  /// drag before PageView sees it, so the viewer only exists while zoomed in.
  void _syncZoomFlag() {
    final zoomed = _matrixScale > 1.001;
    if (zoomed == _isZoomed) return;
    if (!mounted) {
      _isZoomed = zoomed;
      return;
    }
    setState(() => _isZoomed = zoomed);
  }

  @override
  void didUpdateWidget(covariant _HorizontalReaderPageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDownloaded && !oldWidget.isDownloaded) {
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

  Widget _buildPage(bool isRu, int cacheWidth) {
    Widget content;
    if (widget.isDownloaded) {
      if (_cbzBytes != null) {
        content = Image.memory(
          _cbzBytes!,
          fit: widget.boxFit,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
        );
      } else if (_cbzError) {
        content = const Center(child: Icon(Icons.broken_image, color: Colors.white54));
      } else {
        content = const Center(
          child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
    } else if (widget.index < widget.onlinePages.length) {
      final pageUrl = widget.resolveImageUrl(widget.onlinePages[widget.index].url);
      
      content = CachedNetworkImage(
        imageUrl: pageUrl,
        httpHeaders: const {'Referer': 'https://mangalib.org/'},
        fit: widget.boxFit,
        filterQuality: FilterQuality.high,
        memCacheWidth: cacheWidth,
        placeholder: (ctx, url) => const Center(
          child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (ctx, url, err) => InkWell(
          onTap: () => widget.reloadImage(pageUrl),
          child: Container(
            color: AppTokens.surfaceDeep,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded, color: Colors.white70, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    ReaderStrings(isRu).tapToRetry,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      content = const Center(child: Icon(Icons.broken_image, color: Colors.white54));
    }

    if (widget.cropBorders) {
      final scaleFactor = 1.0 + (widget.cropPercent * 2 / 100.0);
      content = ClipRect(
        child: Transform.scale(scale: scaleFactor, child: content),
      );
    }

    return widget.applyColorFilter(content);
  }

  /// Decodes at the pixels the page actually occupies on screen. The double-tap matrix
  /// scale is deliberately excluded: changing the decode size swaps the provider, which
  /// makes CachedNetworkImage drop the bitmap and fade its spinner back in mid-gesture.
  int _decodeWidth(double logicalWidth, double devicePixelRatio) {
    final zoom = widget.zoomLevel.clamp(1.0, 4.0);
    return (logicalWidth * devicePixelRatio * zoom).round().clamp(128, 4096);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    final zoomOut = _matrixScale > 1.05;
    final target = zoomOut
        ? Matrix4.identity()
        : _anchoredScaleMatrix(_doubleTapPosition, _doubleTapScale);
    _zoomAnimationController.stop();
    _zoomAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: target,
    ).animate(
      CurvedAnimation(parent: _zoomAnimationController, curve: Curves.easeOutCubic),
    );
    _zoomAnimationController.forward(from: 0.0);
  }

  /// M = T(-anchor * (scale - 1)) * S(scale) keeps the tapped pixel under the finger.
  Matrix4 _anchoredScaleMatrix(Offset anchor, double scale) {
    return Matrix4.identity()
      ..translateByDouble(-anchor.dx * (scale - 1), -anchor.dy * (scale - 1), 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    _zoomAnimationController.stop();
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    if (_matrixScale > 1.02) return;
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    // Resolved outside of LayoutBuilder: inherited widgets cannot be depended on from
    // a builder that runs during layout.
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final fallbackWidth = MediaQuery.sizeOf(context).width;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final baseScale = widget.zoomLevel.clamp(1.0, 4.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : fallbackWidth;
        final page = _buildPage(isRu, _decodeWidth(logicalWidth, devicePixelRatio));

        final Widget body = (_isZoomed || baseScale > 1.001)
            ? InteractiveViewer(
                transformationController: _transformController,
                minScale: 1.0,
                maxScale: 4.0,
                clipBehavior: Clip.none,
                onInteractionStart: _handleInteractionStart,
                onInteractionEnd: _handleInteractionEnd,
                child: Center(
                  child: Transform.scale(scale: baseScale, child: page),
                ),
              )
            : Center(child: page);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          child: body,
        );
      },
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

class _ReaderSheetCard extends StatelessWidget {
  const _ReaderSheetCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.fromLTRB(AppTokens.spaceMd, AppTokens.spaceSm, AppTokens.spaceMd, AppTokens.spaceSm),
      decoration: BoxDecoration(
        color: AppTokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.spaceXs, bottom: AppTokens.spaceXs),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppTokens.accent),
                const SizedBox(width: AppTokens.spaceSm),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _ReaderSheetRow extends StatelessWidget {
  const _ReaderSheetRow({
    required this.label,
    this.subtitle,
    required this.control,
  });

  final String label;
  final String? subtitle;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 11, height: 1.3, color: AppTokens.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          control,
        ],
      ),
    );
  }
}

class _ReaderSheetValueBadge extends StatelessWidget {
  const _ReaderSheetValueBadge(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 52),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm, vertical: AppTokens.spaceXs),
      decoration: BoxDecoration(
        color: AppTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.borderStrong),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Colors.white,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
    );
  }
}

class _ReaderSheetOption<T> {
  const _ReaderSheetOption(this.value, this.label);

  final T value;
  final String label;
}

class _ReaderSheetSelect<T> extends StatelessWidget {
  const _ReaderSheetSelect({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<_ReaderSheetOption<T>> options;
  final ValueChanged<T> onChanged;

  _ReaderSheetOption<T> get _current {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return options.first;
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: '',
      initialValue: value,
      color: AppTokens.surfaceRaised,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: const BorderSide(color: AppTokens.borderStrong),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<T>(
            value: option.value,
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  child: option.value == value
                      ? const Icon(Icons.check_rounded, size: 16, color: AppTokens.accent)
                      : null,
                ),
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: option.value == value ? FontWeight.w600 : FontWeight.normal,
                    color: option.value == value ? Colors.white : AppTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
          decoration: BoxDecoration(
            color: AppTokens.surfaceRaised,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            border: Border.all(color: AppTokens.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _current.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more_rounded, size: 16, color: AppTokens.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderPresetChip extends StatelessWidget {
  const _ReaderPresetChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTokens.accent.withValues(alpha: 0.16) : AppTokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        side: BorderSide(color: selected ? AppTokens.accent : AppTokens.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: selected ? AppTokens.accent : AppTokens.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppTokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterListScrollHost extends StatefulWidget {
  const _ChapterListScrollHost({
    required this.initialOffset,
    required this.builder,
  });

  final double initialOffset;
  final Widget Function(ScrollController controller) builder;

  @override
  State<_ChapterListScrollHost> createState() => _ChapterListScrollHostState();
}

class _ChapterListScrollHostState extends State<_ChapterListScrollHost> {
  late final ScrollController _controller =
      ScrollController(initialScrollOffset: widget.initialOffset);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}
