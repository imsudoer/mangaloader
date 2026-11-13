import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart' hide DownloadProgress;
import 'package:window_manager/window_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mangaloader/l10n/strings/details_strings.dart';
import 'package:mangaloader/providers/manga_provider.dart';
import 'package:mangaloader/providers/download_provider.dart';
import 'package:mangaloader/providers/library_provider.dart';
import 'package:mangaloader/providers/streak_provider.dart';
import 'package:mangaloader/providers/continue_reading_provider.dart';
import 'package:mangaloader/services/download_queue_service.dart';
import 'package:mangaloader/widgets/download_button.dart';
import 'package:mangaloader/widgets/manga_card.dart' show coverHeroTag;
import 'package:mangaloader/widgets/manga_share_modal.dart';
import 'package:mangaloader/widgets/manga_comments_modal.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/utils/title_match.dart';
import 'package:mangaloader/utils/reading_order.dart';
import 'package:mangaloader/services/content_filter.dart';
import 'package:mangaloader/theme/app_theme.dart';
import 'package:mangaloader/theme/app_tokens.dart';

final mangaHistoryProvider = FutureProvider.family<List<ChapterHistory>, int>((ref, mangaId) async {
  return rust_storage.getChapterHistory(mangaId: mangaId);
});

final mangaDownloadedChaptersProvider = FutureProvider.family<List<DownloadedChapterInfo>, int>((ref, mangaId) async {
  return rust_storage.getDownloadedChapters(mangaId: mangaId);
});

class MangaDetailsPage extends ConsumerStatefulWidget {
  final String slugUrl;
  const MangaDetailsPage({super.key, required this.slugUrl});

  @override
  ConsumerState<MangaDetailsPage> createState() => _MangaDetailsPageState();
}

class _MangaDetailsPageState extends ConsumerState<MangaDetailsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _chapterSearchQuery = '';
  String _chapterFilter = 'all'; // 'all', 'downloaded', 'unread'
  bool _isAscending = true;
  bool _isBatchMode = false;
  final Set<String> _selectedChapters = {};
  List<DownloadQueueItem> _queueItems = DownloadQueueService.instance.items;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    DownloadQueueService.instance.queue.addListener(_syncQueueItems);
  }

  @override
  void dispose() {
    DownloadQueueService.instance.queue.removeListener(_syncQueueItems);
    _tabController.dispose();
    super.dispose();
  }

  void _syncQueueItems() {
    if (!mounted) return;
    final next = DownloadQueueService.instance.items;
    if (identical(next, _queueItems)) return;
    setState(() => _queueItems = next);
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(mangaDetailsProvider(widget.slugUrl));
    final chaptersAsync = ref.watch(mangaChaptersProvider(widget.slugUrl));
    final downloadList = ref.watch(downloadProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final s = DetailsStrings(isRu);

    ref.listen<int>(downloadCompletionTickProvider, (_, __) {
      ref.invalidate(mangaDownloadedChaptersProvider);
      ref.invalidate(mangaHistoryProvider);
    });

    return Scaffold(
      body: detailsAsync.when(
        data: (manga) {
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            final titleStr = manga.rusName.isNotEmpty ? manga.rusName : manga.name;
            windowManager.setTitle("Manga Loader - $titleStr");
          }
          final historyAsync = ref.watch(mangaHistoryProvider(manga.id));
          final libraryList = ref.watch(libraryProvider).value ?? [];
          final isInLibrary = libraryList.any((e) => e.mangaId == manga.id);

          final dynamicAccent = _getDynamicAccentColor(manga);

          return SafeArea(
            bottom: false,
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                // Collapsible Header (Cover, Badges, Titles, Stats, Action Buttons)
                SliverToBoxAdapter(
                  child: _buildStickyHeader(context, ref, manga, isRu, chaptersAsync, historyAsync, isInLibrary, dynamicAccent),
                ),
                // Pinned Tab Bar with Dynamic Palette
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: dynamicAccent.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dynamicAccent, width: 1.2),
                      ),
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: AppTokens.textSecondary,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      tabs: [
                        Tab(text: s.tabAbout),
                        Tab(text: s.tabChapters),
                        Tab(text: s.comments),
                      ],
                    ),
                  ),
                ),
              ],
              // Scrollable Tabs Content
              body: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: About / Details
                  _buildAboutTab(manga, isRu),

                  // Tab 2: Chapters List
                  _buildChaptersTab(context, ref, manga, chaptersAsync, historyAsync, downloadList, isRu),

                  // Tab 3: Reviews / Comments
                  _buildCommentsTab(manga.id, isRu),
                ],
              ),
            ),
          );
        },
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) {
          final cleanError = e.toString().replaceAll('Exception: ', '');
          final isBlocked = cleanError.contains('законодательства РФ') || cleanError.contains('regulations');
          if (isBlocked) {
            return Scaffold(
              appBar: AppBar(title: Text(s.contentUnavailable)),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.block_rounded, size: 56, color: AppTokens.accent),
                      const SizedBox(height: 16),
                      Text(
                        cleanError,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, color: AppTokens.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Scaffold(
            appBar: AppBar(title: Text(s.errorTitle)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(s.loadFailed('$e'), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => ref.invalidate(mangaDetailsProvider(widget.slugUrl)),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(s.retry),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getDynamicAccentColor(MangaDetails manga) {
    int hash = manga.slugUrl.hashCode;
    if (manga.genres.isNotEmpty) {
      hash ^= manga.genres.first.name.hashCode;
    }
    final hue = (hash.abs() % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.50, 0.56).toColor();
  }

  Widget _buildStickyHeader(
    BuildContext context,
    WidgetRef ref,
    MangaDetails manga,
    bool isRu,
    AsyncValue<List<Chapter>> chaptersAsync,
    AsyncValue<List<ChapterHistory>> historyAsync,
    bool isInLibrary,
    Color dynamicAccent,
  ) {
    final s = DetailsStrings(isRu);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            dynamicAccent.withValues(alpha: 0.18),
            AppTokens.surfaceBase,
          ],
        ),
        border: const Border(bottom: BorderSide(color: Color(0xFF2E2E2E), width: 1)),
      ),
      child: Stack(
        children: [
          // Subtle blurred background cover
          Positioned.fill(
            child: Opacity(
              opacity: 0.12,
              child: CachedNetworkImage(
                imageUrl: manga.coverUrl,
                httpHeaders: const {'Referer': 'https://mangalib.org/'},
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Nav Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                      tooltip: s.back,
                      onPressed: () => context.pop(),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: AppTokens.textPrimary, size: 20),
                      tooltip: s.share,
                      onPressed: () => MangaShareModal.show(context, manga, dynamicAccent),
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_browser_rounded, color: AppTokens.textPrimary, size: 20),
                      tooltip: s.openOnMangalib,
                      onPressed: () async {
                        final uri = Uri.parse('https://mangalib.org/ru/manga/${manga.slugUrl}');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Manga Identity Row (Cover + Badges + Titles + Stats)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTokens.accent.withValues(alpha: 0.4), width: 1),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Hero(
                          tag: coverHeroTag(manga.slugUrl),
                          child: CachedNetworkImage(
                            imageUrl: manga.coverUrl,
                            httpHeaders: const {'Referer': 'https://mangalib.org/'},
                            width: 76,
                            height: 108,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(width: 76, height: 108, color: AppTokens.border),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Info Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Badges (Type, Status, Age Restriction)
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              if (manga.mangaType.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: dynamicAccent,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    manga.mangaType,
                                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              if (manga.status.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTokens.border,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    manga.status,
                                    style: const TextStyle(color: AppTokens.textPrimary, fontSize: 10.5),
                                  ),
                                ),
                              if (manga.ageRestriction.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTokens.border,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    manga.ageRestriction,
                                    style: const TextStyle(color: AppTokens.textSecondary, fontSize: 10.5),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),

                          // Main Russian Title
                          Text(
                            manga.rusName.isNotEmpty ? manga.rusName : manga.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          // Original Title
                          if (manga.rusName.isNotEmpty && manga.name.isNotEmpty && manga.name != manga.rusName) ...[
                            const SizedBox(height: 2),
                            Text(
                              manga.name,
                              style: const TextStyle(color: AppTokens.textSecondary, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],

                          const SizedBox(height: 5),
                          // Rating & Stats Row
                          Row(
                            children: [
                              if (manga.ratingAverage != "0") ...[
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 15),
                                const SizedBox(width: 3),
                                Text(
                                  manga.ratingAverage,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                if (manga.ratingVotes != "0")
                                  Text(
                                    ' (${manga.ratingVotes})',
                                    style: const TextStyle(color: AppTokens.textSecondary, fontSize: 10.5),
                                  ),
                                const SizedBox(width: 10),
                              ],
                              const Icon(Icons.menu_book_rounded, color: AppTokens.textSecondary, size: 13),
                              const SizedBox(width: 3),
                              Text(
                                s.chaptersCount('${manga.chaptersCount}'),
                                style: const TextStyle(color: AppTokens.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Action Buttons Row
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: dynamicAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                        onPressed: () async {
                          await rust_storage.saveManga(manga: manga);
                          final existing = await rust_storage.getMangaListType(mangaId: manga.id);
                          if (existing == null || existing.isEmpty) {
                            await rust_storage.addToList(mangaId: manga.id, listType: 'reading');
                          }
                          ref.read(libraryProvider.notifier).loadAll();

                          chaptersAsync.whenData((chapters) async {
                            if (chapters.isEmpty) return;

                            final history = historyAsync.value ?? [];
                            final lastProg = history.firstOrNull;

                            if (lastProg != null) {
                              await context.push('/read/${manga.slugUrl}/${lastProg.volume}/${lastProg.number}');
                            } else {
                              final sorted = List<Chapter>.from(chapters);
                              sorted.sort((a, b) {
                                final va = double.tryParse(a.volume) ?? 0.0;
                                final vb = double.tryParse(b.volume) ?? 0.0;
                                if (va != vb) return va.compareTo(vb);
                                final na = double.tryParse(a.number) ?? 0.0;
                                final nb = double.tryParse(b.number) ?? 0.0;
                                return na.compareTo(nb);
                              });
                              final firstCh = sorted.firstWhere((c) => !c.isPaid, orElse: () => sorted.first);
                              await context.push('/read/${manga.slugUrl}/${firstCh.volume}/${firstCh.number}?branchId=${firstCh.branchId ?? ""}');
                            }
                            if (context.mounted) {
                              ref.read(libraryProvider.notifier).loadAll();
                              ref.invalidate(mangaHistoryProvider(manga.id));
                              ref.invalidate(continueReadingProvider);
                              ref.read(streakProvider.notifier).loadStreak();
                            }
                          });
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Builder(
                          builder: (context) {
                            final history = historyAsync.value ?? [];
                            final lastProg = history.firstOrNull;
                            if (lastProg != null) {
                              return Text(
                                s.continueReading(lastProg.volume, lastProg.number),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            }
                            return Text(
                              s.startReading,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isInLibrary ? AppTokens.textPrimary : AppTokens.textSecondary,
                          side: BorderSide(
                            color: isInLibrary ? AppTokens.accent : AppTokens.borderStrong,
                            width: 1.5,
                          ),
                          backgroundColor: isInLibrary ? AppTokens.accent.withValues(alpha: 0.15) : Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                        onPressed: () async {
                          await rust_storage.saveManga(manga: manga);
                          if (!context.mounted) return;
                          if (!isInLibrary) {
                            await ref.read(libraryProvider.notifier).addToList(manga.id, 'reading');
                            ref.invalidate(libraryProvider);
                            setState(() {});
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(s.addedToLibrary)),
                              );
                            }
                          } else {
                            _showLibrarySheet(context, ref, manga, isRu);
                          }
                        },
                        icon: Icon(
                          isInLibrary ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                          size: 16,
                          color: isInLibrary ? AppTokens.textPrimary : AppTokens.textSecondary,
                        ),
                        label: Text(
                          isInLibrary ? s.inList : s.bookmark,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      style: IconButton.styleFrom(
                        side: const BorderSide(color: AppTokens.borderStrong, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        padding: const EdgeInsets.all(10),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppTokens.textPrimary),
                      tooltip: s.comments,
                      onPressed: () {
                        MangaCommentsModal.show(
                          context,
                          relationType: 'media',
                          relationId: manga.id,
                          title: manga.rusName.isNotEmpty ? manga.rusName : manga.name,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChaptersTab(
    BuildContext context,
    WidgetRef ref,
    MangaDetails manga,
    AsyncValue<List<Chapter>> chaptersAsync,
    AsyncValue<List<ChapterHistory>> historyAsync,
    List<DownloadProgress> downloadList,
    bool isRu,
  ) {
    final downloadedAsync = ref.watch(mangaDownloadedChaptersProvider(manga.id));
    final downloadedChapters = downloadedAsync.value ?? [];
    final history = historyAsync.value ?? [];
    final s = DetailsStrings(isRu);

    return chaptersAsync.when(
      data: (rawChapters) {
        final List<Chapter> chapters = rawChapters.isNotEmpty
            ? List<Chapter>.from(rawChapters)
            : downloadedChapters.map((dc) => Chapter(
                id: dc.id,
                volume: dc.volume,
                number: dc.number,
                name: null,
                branchId: dc.branchId,
                branchesCount: 1,
                isPaid: false,
              )).toList();

        if (chapters.isEmpty) {
          final isLicensed = (manga.publisherName != null && manga.publisherName!.isNotEmpty) || manga.chaptersCount > 0;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isLicensed ? Icons.verified_user_outlined : Icons.menu_book_rounded,
                    size: 48,
                    color: isLicensed ? Colors.amber.shade700 : AppTokens.accent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isLicensed
                      ? s.licensed
                      : s.emptyChapters,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isLicensed
                      ? s.licensedDescription(
                          manga.publisherName != null && manga.publisherName!.isNotEmpty ? ' (${manga.publisherName})' : '',
                        )
                      : s.noChaptersUploaded,
                    style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTokens.textPrimary,
                          side: const BorderSide(color: AppTokens.borderStrong),
                        ),
                        onPressed: () async {
                          final uri = Uri.parse('https://mangalib.org/ru/${manga.slugUrl}');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                        label: Text(s.openOnMangalib),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
                        onPressed: () {
                          ref.invalidate(mangaChaptersProvider(widget.slugUrl));
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(s.refresh),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        var list = chapters.where((c) {
          if (_chapterSearchQuery.isNotEmpty) {
            final query = _chapterSearchQuery.toLowerCase();
            final matchNum = c.number.toLowerCase().contains(query);
            final matchVol = c.volume.toLowerCase().contains(query);
            final matchName = (c.name ?? '').toLowerCase().contains(query);
            if (!matchNum && !matchVol && !matchName) return false;
          }

          if (_chapterFilter == 'downloaded') {
            return downloadedChapters.any((dc) => dc.volume == c.volume && dc.number == c.number);
          } else if (_chapterFilter == 'unread') {
            return !history.any((h) => h.volume == c.volume && h.number == c.number && h.isCompleted);
          } else if (_chapterFilter == 'not_downloaded') {
            return !downloadedChapters.any((dc) => dc.volume == c.volume && dc.number == c.number);
          }

          return true;
        }).toList();

        // Sort chapters numerically
        list.sort((a, b) {
          final volA = double.tryParse(a.volume) ?? 0.0;
          final volB = double.tryParse(b.volume) ?? 0.0;
          final numA = double.tryParse(a.number) ?? 0.0;
          final numB = double.tryParse(b.number) ?? 0.0;
          final compVol = volA.compareTo(volB);
          if (compVol != 0) return compVol;
          return numA.compareTo(numB);
        });

        if (!_isAscending) {
          list = list.reversed.toList();
        }

        final headerChildren = <Widget>[
          // Chapter controls bar
          Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: s.chapterSearchHint,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: AppTokens.surfaceRaised,
                    ),
                    onChanged: (val) => setState(() => _chapterSearchQuery = val),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: _isBatchMode ? s.exitBatch : s.batchSelect,
                  icon: Icon(_isBatchMode ? Icons.checklist_rtl_rounded : Icons.checklist_rounded, size: 20, color: _isBatchMode ? AppTokens.accent : null),
                  onPressed: () => setState(() {
                    _isBatchMode = !_isBatchMode;
                    if (!_isBatchMode) _selectedChapters.clear();
                  }),
                ),
                IconButton(
                  tooltip: _isAscending ? s.oldestFirst : s.newestFirst,
                  icon: Icon(_isAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 20),
                  onPressed: () => setState(() => _isAscending = !_isAscending),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Quick Filter Chips (Все, Скачанные, Непрочитанные)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(s.allFilter('${chapters.length}')),
                    selected: _chapterFilter == 'all',
                    selectedColor: AppTokens.accent,
                    backgroundColor: AppTokens.surfaceRaised,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _chapterFilter == 'all' ? Colors.white : AppTokens.textPrimary,
                      fontWeight: _chapterFilter == 'all' ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: _chapterFilter == 'all' ? AppTokens.accent : AppTokens.borderStrong,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _chapterFilter = 'all'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(s.downloadedFilter('${downloadedChapters.length}')),
                    selected: _chapterFilter == 'downloaded',
                    selectedColor: AppTokens.accent,
                    backgroundColor: AppTokens.surfaceRaised,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _chapterFilter == 'downloaded' ? Colors.white : AppTokens.textPrimary,
                      fontWeight: _chapterFilter == 'downloaded' ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: _chapterFilter == 'downloaded' ? AppTokens.accent : AppTokens.borderStrong,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _chapterFilter = 'downloaded'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(s.unread),
                    selected: _chapterFilter == 'unread',
                    selectedColor: AppTokens.accent,
                    backgroundColor: AppTokens.surfaceRaised,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _chapterFilter == 'unread' ? Colors.white : AppTokens.textPrimary,
                      fontWeight: _chapterFilter == 'unread' ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: _chapterFilter == 'unread' ? AppTokens.accent : AppTokens.borderStrong,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _chapterFilter = 'unread'),
                  ),
                ],
              ),
            ),

            if (_isBatchMode) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTokens.accent),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          if (_selectedChapters.length == list.where((c) => !c.isPaid).length) {
                            _selectedChapters.clear();
                          } else {
                            _selectedChapters.clear();
                            for (final c in list) {
                              if (!c.isPaid) _selectedChapters.add('${c.volume}_${c.number}');
                            }
                          }
                        });
                      },
                      icon: Icon(
                        _selectedChapters.length == list.where((c) => !c.isPaid).length && list.isNotEmpty
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                        size: 16,
                        color: AppTokens.textPrimary,
                      ),
                      label: Text(
                        _selectedChapters.length == list.where((c) => !c.isPaid).length && list.isNotEmpty
                            ? s.deselect
                            : s.allFilter('${list.where((c) => !c.isPaid).length}'),
                        style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTokens.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      onPressed: _selectedChapters.isEmpty ? null : () async {
                        final toDownload = list.where((c) => _selectedChapters.contains('${c.volume}_${c.number}')).toList();
                        
                        // Sort batch downloads chronologically ascending
                        toDownload.sort((a, b) {
                          final volA = double.tryParse(a.volume) ?? 0.0;
                          final volB = double.tryParse(b.volume) ?? 0.0;
                          final numA = double.tryParse(a.number) ?? 0.0;
                          final numB = double.tryParse(b.number) ?? 0.0;
                          final compVol = volA.compareTo(volB);
                          if (compVol != 0) return compVol;
                          return numA.compareTo(numB);
                        });

                        await DownloadQueueService.instance.enqueue(
                          ref: ref,
                          slugUrl: manga.slugUrl,
                          mangaId: manga.id,
                          chapters: [
                            for (final ch in toDownload)
                              ChapterDownloadRequest(
                                volume: ch.volume,
                                number: ch.number,
                                branchId: ch.branchId,
                              ),
                          ],
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                s.queuedForDownload('${toDownload.length}'),
                              ),
                            ),
                          );
                          setState(() {
                            _selectedChapters.clear();
                            _isBatchMode = false;
                          });
                        }
                      },
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(
                        s.downloadCount('${_selectedChapters.length}'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
          ];

          // Chapter tiles are built lazily: long-running titles easily exceed a
          // thousand chapters, and mounting them all froze the tab.
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: headerChildren.length + list.length,
            itemBuilder: (context, index) {
              if (index < headerChildren.length) return headerChildren[index];
              final ch = list[index - headerChildren.length];
              final isRead = history.any((h) => h.volume == ch.volume && h.number == ch.number && h.isCompleted);
              final localChapter = downloadedChapters.where((dc) => dc.volume == ch.volume && dc.number == ch.number).firstOrNull;
              final isDownloadedLocally = localChapter != null;

              final progressItem = downloadList.where(
                (p) => p.mangaSlug == manga.slugUrl && p.chapterVolume == ch.volume && p.chapterNumber == ch.number,
              ).firstOrNull;

              final queueItem = _queueItems.where(
                (item) => item.mangaId == manga.id && item.volume == ch.volume && item.number == ch.number,
              ).firstOrNull;
              final isQueueFailed = queueItem?.status == DownloadQueueStatus.failed;

                final double downloadProgress;
                if (progressItem != null) {
                  if (progressItem.state == DownloadState.completed) {
                    downloadProgress = 1.0;
                  } else if (progressItem.state == DownloadState.queued) {
                    downloadProgress = -2.0;
                  } else {
                    downloadProgress = (progressItem.currentPage / (progressItem.totalPages > 0 ? progressItem.totalPages : 1)).clamp(0.0, 1.0);
                  }
                } else if (isDownloadedLocally) {
                  downloadProgress = 1.0;
                } else if (queueItem != null) {
                  switch (queueItem.status) {
                    case DownloadQueueStatus.completed:
                      downloadProgress = 1.0;
                    case DownloadQueueStatus.queued:
                    case DownloadQueueStatus.waitingForWifi:
                      downloadProgress = -2.0;
                    case DownloadQueueStatus.downloading:
                      downloadProgress = 0.0;
                    case DownloadQueueStatus.failed:
                      downloadProgress = -1.0;
                  }
                } else {
                  downloadProgress = -1.0;
                }

                final key = '${ch.volume}_${ch.number}';
                final isSelected = _selectedChapters.contains(key);

                return Card(
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected
                      ? AppTokens.accent
                      : (isRead ? AppTokens.accent.withValues(alpha: 0.3) : AppTokens.border),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: _isBatchMode && !ch.isPaid
                    ? Checkbox(
                        value: isSelected,
                        activeColor: AppTokens.accent,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedChapters.add(key);
                            } else {
                              _selectedChapters.remove(key);
                            }
                          });
                        },
                      )
                    : Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isRead
                            ? AppTokens.accent.withValues(alpha: 0.2)
                            : AppTokens.border,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isDownloadedLocally
                            ? Icons.offline_pin_rounded
                            : (isRead ? Icons.done_all_rounded : Icons.menu_book_rounded),
                          size: 16,
                          color: isDownloadedLocally
                            ? AppTokens.accent
                            : (isRead ? AppTokens.textPrimary : AppTokens.textSecondary),
                        ),
                      ),
                  title: Row(
                    children: [
                      Text(
                        s.volumeChapter(ch.volume, ch.number),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isRead ? AppTokens.textSecondary : Colors.white,
                        ),
                      ),
                      if (localChapter != null && localChapter.pageCount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          s.pages('${localChapter.pageCount}'),
                          style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
                        ),
                      ] else if (history.any((h) => h.volume == ch.volume && h.number == ch.number && h.totalPages > 0)) ...[
                        const SizedBox(width: 6),
                        Text(
                          s.pages(
                            '${history.firstWhere((h) => h.volume == ch.volume && h.number == ch.number).totalPages}',
                          ),
                          style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
                        ),
                      ],
                      if (isDownloadedLocally) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTokens.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CBZ',
                            style: TextStyle(fontSize: 10, color: AppTokens.textPrimary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      if (ch.isPaid) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade900.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_rounded, size: 11, color: Colors.amberAccent),
                              const SizedBox(width: 4),
                              Text(
                                s.locked,
                                style: const TextStyle(fontSize: 10, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: ch.name != null && ch.name!.isNotEmpty
                    ? Text(ch.name!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary))
                    : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Direct Read Play Button
                      IconButton.filledTonal(
                        icon: Icon(ch.isPaid ? Icons.lock_outline_rounded : (isDownloadedLocally ? Icons.folder_zip_rounded : Icons.play_arrow_rounded), size: 18),
                        tooltip: ch.isPaid 
                          ? s.paidAccess
                          : (isDownloadedLocally 
                              ? s.readOffline
                              : s.readOnline),
                        style: IconButton.styleFrom(
                          backgroundColor: ch.isPaid 
                            ? Colors.amber.shade900.withValues(alpha: 0.2) 
                            : AppTokens.accent.withValues(alpha: 0.2),
                          foregroundColor: ch.isPaid ? Colors.amberAccent : AppTokens.textPrimary,
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () async {
                          await rust_storage.saveManga(manga: manga);
                          final existing = await rust_storage.getMangaListType(mangaId: manga.id);
                          if (existing == null || existing.isEmpty) {
                            await rust_storage.addToList(mangaId: manga.id, listType: 'reading');
                          }
                          ref.read(libraryProvider.notifier).loadAll();
                          if (context.mounted) {
                            if (localChapter != null) {
                              await context.push('/read-local?path=${Uri.encodeComponent(localChapter.downloadPath)}');
                            } else {
                              await context.push('/read/${manga.slugUrl}/${ch.volume}/${ch.number}?branchId=${ch.branchId ?? ""}');
                            }
                            if (context.mounted) {
                              ref.read(libraryProvider.notifier).loadAll();
                              ref.invalidate(mangaHistoryProvider(manga.id));
                              ref.invalidate(mangaDownloadedChaptersProvider(manga.id));
                            }
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      if (!ch.isPaid)
                        DownloadButton(
                          progress: downloadProgress,
                          failed: isQueueFailed,
                          onPressed: () async {
                            if (isQueueFailed && queueItem != null) {
                              await DownloadQueueService.instance.retry(queueItem);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(s.retryChapter(ch.volume, ch.number))),
                                );
                              }
                              return;
                            }
                            if (localChapter != null) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(s.alreadyDownloaded)),
                                );
                              }
                              return;
                            }
                            await DownloadQueueService.instance.enqueue(
                              ref: ref,
                              slugUrl: manga.slugUrl,
                              mangaId: manga.id,
                              chapters: [
                                ChapterDownloadRequest(
                                  volume: ch.volume,
                                  number: ch.number,
                                  branchId: ch.branchId,
                                ),
                              ],
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(s.queuedChapter(ch.volume, ch.number))),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                  onTap: () async {
                    await rust_storage.saveManga(manga: manga);
                    final existing = await rust_storage.getMangaListType(mangaId: manga.id);
                    if (existing == null || existing.isEmpty) {
                      await rust_storage.addToList(mangaId: manga.id, listType: 'reading');
                    }
                    ref.read(libraryProvider.notifier).loadAll();
                    if (context.mounted) {
                      if (localChapter != null) {
                        await context.push('/read-local?path=${Uri.encodeComponent(localChapter.downloadPath)}');
                      } else {
                        await context.push('/read/${manga.slugUrl}/${ch.volume}/${ch.number}?branchId=${ch.branchId ?? ""}');
                      }
                      if (context.mounted) {
                        ref.read(libraryProvider.notifier).loadAll();
                        ref.invalidate(mangaHistoryProvider(manga.id));
                        ref.invalidate(mangaDownloadedChaptersProvider(manga.id));
                        ref.invalidate(continueReadingProvider);
                        ref.read(streakProvider.notifier).loadStreak();
                      }
                    }
                  },
                ),
              );
            },
          );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.amber),
              const SizedBox(height: 12),
              Text(
                s.chaptersLoadFailed('$e'),
                style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
                onPressed: () => ref.refresh(mangaChaptersProvider(widget.slugUrl)),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(s.retryAttempt),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutTab(MangaDetails manga, bool isRu) {
    final s = DetailsStrings(isRu);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // The whole franchise, ordered, for readers who opened a middle entry.
        _buildReadingOrderSection(manga, isRu),

        // Other formats of the same story (manga / light novel / etc.)
        _buildAlternateEditionsSection(manga, isRu),

        // Authors & Artists Cards
        if (manga.authors.isNotEmpty || manga.artists.isNotEmpty) ...[
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (manga.authors.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.edit_note_rounded, size: 18, color: AppTokens.textPrimary),
                        const SizedBox(width: 8),
                        Text(s.authors, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            manga.authors.map((a) => a.name).join(', '),
                            style: const TextStyle(color: AppTokens.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (manga.authors.isNotEmpty && manga.artists.isNotEmpty) const Divider(height: 16),
                  if (manga.artists.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.brush_rounded, size: 18, color: AppTokens.textPrimary),
                        const SizedBox(width: 8),
                        Text(s.artists, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            manga.artists.map((a) => a.name).join(', '),
                            style: const TextStyle(color: AppTokens.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Synopsis Card
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.synopsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  manga.summary.isNotEmpty ? manga.summary : s.noSynopsis,
                  style: const TextStyle(color: AppTokens.textPrimary, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Genres & Tags
        if (manga.genres.isNotEmpty) ...[
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.genres, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: manga.genres.map((g) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTokens.border,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(g.name, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
                    )).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (manga.tags.isNotEmpty) ...[
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.tags, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: manga.tags.map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTokens.surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTokens.borderStrong),
                      ),
                      child: Text(t.name, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
                    )).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Relations section (e.g. source novel, adaptation, sequel)
        _buildRelationsSection(manga.slugUrl, isRu),

        // Similar manga section
        _buildSimilarSection(manga.slugUrl, isRu),
      ],
    );
  }

  /// Relations that may be rendered. RuStore builds must not show a blocked
  /// title even when MangaLib links to it from an allowed one.
  List<MangaRelationItem> _relations(String slugUrl) {
    final relations = ref.watch(mangaRelationsProvider(slugUrl)).valueOrNull ??
        const <MangaRelationItem>[];
    return ContentFilter.filterRelations(relations);
  }

  /// Entries of the same story published in another medium. Relations provide the
  /// linked ones, the catalog lookup covers pairs MangaLib never linked.
  List<MangaSearchResult> _otherFormats(
    MangaDetails manga,
    List<MangaRelationItem> relations,
  ) {
    final currentTitle = primaryTitle(
      name: manga.name,
      rusName: manga.rusName,
      engName: manga.engName,
    );
    if (currentTitle.trim().isEmpty) return const [];

    final currentKind = editionKindOf(manga.mangaType);
    final nameMatches = ref
            .watch(alternateEditionsProvider(AlternateEditionsQuery(
              id: manga.id,
              title: currentTitle,
              kind: currentKind,
            )))
            .valueOrNull ??
        const <MangaSearchResult>[];

    final seen = <String>{manga.slugUrl};
    final editions = <MangaSearchResult>[];

    void addCandidate(MangaSearchResult candidate) {
      if (candidate.slugUrl.isEmpty || !seen.add(candidate.slugUrl)) return;
      final kind = editionKindOf(candidate.mangaType);
      if (kind == EditionKind.other || kind == currentKind) return;
      if (ContentFilter.isBlockedSearchResult(candidate)) return;
      editions.add(candidate);
    }

    for (final relation in relations) {
      addCandidate(relation.manga);
    }
    for (final candidate in nameMatches) {
      addCandidate(candidate);
    }
    return editions;
  }

  /// Orders the franchise around the current title, so a reader who opened a
  /// sequel by accident sees what to read first.
  Widget _buildReadingOrderSection(MangaDetails manga, bool isRu) {
    final s = DetailsStrings(isRu);
    final relations = _relations(manga.slugUrl);
    final order = buildReadingOrder(
      current: manga,
      relations: relations,
      otherFormats: _otherFormats(manga, relations),
    );
    // Only a real franchise is worth a block; alternate formats alone are
    // already covered by the section below.
    if (order.length < 2 ||
        !order.any((step) =>
            !step.isCurrent && step.kind != ReadingStepKind.otherFormat)) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppTokens.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: const BorderSide(color: AppTokens.borderStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.format_list_numbered_rounded,
                    size: 18, color: AppTokens.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.readingOrder,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.readingOrderSubtitle,
              style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < order.length; index++)
              _buildReadingOrderRow(order[index], index, isRu),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingOrderRow(ReadingStep step, int index, bool isRu) {
    final s = DetailsStrings(isRu);
    final label = step.isCurrent
        ? s.youAreHere
        : (step.relationLabel.isNotEmpty ? step.relationLabel : step.formatLabel);
    final highlight = step.isCurrent ? AppTokens.accent : AppTokens.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: step.isCurrent
            ? AppTokens.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: InkWell(
          onTap: step.isCurrent ? null : () => context.push('/manga/${step.slugUrl}'),
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              border: Border.all(
                color: step.isCurrent
                    ? AppTokens.accent.withValues(alpha: 0.55)
                    : AppTokens.border,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: highlight,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: step.isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      if (label.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: highlight),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!step.isCurrent)
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppTokens.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Suggests the same story published in another format (manga next to a light novel).
  /// Relations catch the officially linked ones; a title lookup covers the rest.
  Widget _buildAlternateEditionsSection(MangaDetails manga, bool isRu) {
    final s = DetailsStrings(isRu);
    final relations = _relations(manga.slugUrl);
    final editions = _otherFormats(manga, relations);
    if (editions.isEmpty) return const SizedBox.shrink();

    final formats = editions
        .map((e) => e.mangaType.trim())
        .where((label) => label.isNotEmpty)
        .toSet()
        .join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF262620),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF4A4A3E)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_stories_rounded,
                    size: 18, color: AppTokens.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.anotherVersion,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (formats.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                s.availableAs(formats),
                style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: editions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, index) {
                  final edition = editions[index];
                  final title = primaryTitle(
                    name: edition.name,
                    rusName: edition.rusName,
                    engName: edition.engName,
                  );
                  final cover = edition.coverThumbUrl.isNotEmpty
                      ? edition.coverThumbUrl
                      : edition.coverUrl;

                  return SizedBox(
                    width: 104,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => ctx.push('/manga/${edition.slugUrl}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 104,
                                  height: 128,
                                  child: cover.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: cover,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 240,
                                          errorWidget: (_, __, ___) =>
                                              const ColoredBox(
                                            color: Color(0xFF333333),
                                            child: Icon(Icons.broken_image,
                                                size: 20, color: Colors.white54),
                                          ),
                                        )
                                      : const ColoredBox(
                                          color: Color(0xFF333333),
                                          child: Icon(Icons.menu_book_rounded,
                                              size: 20, color: Colors.white54),
                                        ),
                                ),
                              ),
                              if (edition.mangaType.isNotEmpty)
                                Positioned(
                                  left: 4,
                                  top: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      edition.mangaType,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.25,
                              color: AppTokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelationsSection(String slugUrl, bool isRu) {
    final s = DetailsStrings(isRu);
    final relationsAsync = ref.watch(mangaRelationsProvider(slugUrl));

    return relationsAsync.when(
      data: (rawRelations) {
        final relations = ContentFilter.filterRelations(rawRelations);
        if (relations.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Row(
                children: [
                  const Icon(Icons.hub_rounded, size: 18, color: AppTokens.accent),
                  const SizedBox(width: 8),
                  Text(
                    s.relations,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: relations.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final item = relations[i];
                  final m = item.manga;
                  final title = m.rusName.isNotEmpty ? m.rusName : m.name;

                  return InkWell(
                    onTap: () => context.push('/manga/${m.slugUrl}'),
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 105,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: CachedNetworkImage(
                                  imageUrl: m.coverUrl,
                                  httpHeaders: const {'Referer': 'https://mangalib.org/'},
                                  width: 105,
                                  height: 135,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(color: AppTokens.surfaceRaised),
                                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppTokens.accent, width: 0.8),
                                  ),
                                  child: Text(
                                    item.relationTitle,
                                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildSimilarSection(String slugUrl, bool isRu) {
    final s = DetailsStrings(isRu);
    final similarAsync = ref.watch(mangaSimilarProvider(slugUrl));

    return similarAsync.when(
      data: (similarList) {
        if (similarList.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 18, color: AppTokens.accent),
                  const SizedBox(width: 8),
                  Text(
                    s.similar,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: similarList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final item = similarList[i];
                  final m = item.manga;
                  final title = m.rusName.isNotEmpty ? m.rusName : m.name;

                  return InkWell(
                    onTap: () => context.push('/manga/${m.slugUrl}'),
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 105,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: CachedNetworkImage(
                                  imageUrl: m.coverUrl,
                                  httpHeaders: const {'Referer': 'https://mangalib.org/'},
                                  width: 105,
                                  height: 135,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(color: AppTokens.surfaceRaised),
                                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                                ),
                              ),
                              if (item.votesUp > 0)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.thumb_up_rounded, size: 9, color: AppTokens.accent),
                                        const SizedBox(width: 2),
                                        Text('${item.votesUp}', style: const TextStyle(fontSize: 9, color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
                          ),
                          if (item.reason.isNotEmpty)
                            Text(
                              item.reason,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9, color: AppTokens.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildCommentsTab(int mangaId, bool isRu) {
    final s = DetailsStrings(isRu);
    final commentsAsync = ref.watch(mangaCommentsProvider(mangaId));

    return commentsAsync.when(
      data: (commentsData) {
        final rootComments = commentsData.root;
        final replies = commentsData.replies;

        if (rootComments.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.forum_outlined, size: 48, color: AppTokens.accent),
                  const SizedBox(height: 12),
                  Text(
                    s.noComments,
                    style: const TextStyle(color: AppTokens.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: rootComments.length,
          itemBuilder: (context, index) {
            final root = rootComments[index];
            final rootReplies = replies.where((r) => r.rootId == root.id).toList();

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTokens.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCommentTile(root, isRu, isReply: false),
                    if (rootReplies.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: const BoxDecoration(
                          border: Border(left: BorderSide(color: AppTokens.accent, width: 2)),
                        ),
                        child: Column(
                          children: rootReplies.map((reply) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _buildCommentTile(reply, isRu, isReply: true),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка загрузки комментариев: $e')),
    );
  }

  Widget _buildCommentTile(CommentItem comment, bool isRu, {required bool isReply}) {
    String dateStr = comment.createdAt;
    if (dateStr.contains('T')) {
      final parts = dateStr.split('T');
      final date = parts.first;
      final time = parts.length > 1 ? parts[1].split('.').first : '';
      dateStr = '$date $time';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: isReply ? 26 : 32,
                height: isReply ? 26 : 32,
                child: comment.userAvatar.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: comment.userAvatar,
                      httpHeaders: const {'Referer': 'https://mangalib.org/'},
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppTokens.border),
                      errorWidget: (_, __, ___) => const Icon(Icons.account_circle, size: 28),
                    )
                  : const Icon(Icons.account_circle, size: 28),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.username,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isReply ? 12 : 13,
                      color: isReply ? AppTokens.textPrimary : Colors.white,
                    ),
                  ),
                  if (dateStr.isNotEmpty)
                    Text(
                      dateStr,
                      style: const TextStyle(fontSize: 10, color: AppTokens.textSecondary),
                    ),
                ],
              ),
            ),
            if (comment.votesUp > 0 || comment.votesDown > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (comment.votesUp > 0) ...[
                    const Icon(Icons.thumb_up_alt_outlined, size: 13, color: AppTokens.accent),
                    const SizedBox(width: 3),
                    Text('${comment.votesUp}', style: const TextStyle(fontSize: 11, color: AppTokens.textPrimary)),
                    const SizedBox(width: 6),
                  ],
                  if (comment.votesDown > 0) ...[
                    const Icon(Icons.thumb_down_alt_outlined, size: 13, color: Colors.redAccent),
                    const SizedBox(width: 3),
                    Text('${comment.votesDown}', style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
                  ],
                ],
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          comment.text,
          style: TextStyle(
            color: AppTokens.textPrimary,
            fontSize: isReply ? 12 : 13,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  String _libraryCategoryLabel(String key, DetailsStrings s) {
    switch (key) {
      case 'reading': return s.categoryReading;
      case 'plan_to_read': return s.categoryPlanToRead;
      case 'completed': return s.categoryCompleted;
      case 'favorites': return s.categoryFavorites;
      case 'on_hold': return s.categoryOnHold;
      default: return s.categoryDropped;
    }
  }

  void _showLibrarySheet(BuildContext context, WidgetRef ref, MangaDetails manga, bool isRu) async {
    final currentListType = await rust_storage.getMangaListType(mangaId: manga.id);

    if (!context.mounted) return;

    final s = DetailsStrings(isRu);
    final categories = [
      (key: 'reading', icon: Icons.auto_stories_rounded),
      (key: 'plan_to_read', icon: Icons.bookmark_outline_rounded),
      (key: 'completed', icon: Icons.check_circle_outline_rounded),
      (key: 'favorites', icon: Icons.favorite_outline_rounded),
      (key: 'on_hold', icon: Icons.pause_circle_outline_rounded),
      (key: 'dropped', icon: Icons.cancel_outlined),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTokens.surfaceRaised,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.libraryCategory,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const Divider(height: 20),
              ...categories.map((cat) {
                final isSelected = currentListType == cat.key;
                return ListTile(
                  leading: Icon(
                    cat.icon, 
                    color: isSelected ? AppTokens.accent : AppTokens.textSecondary,
                  ),
                  title: Text(
                    _libraryCategoryLabel(cat.key, s),
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppTokens.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check_rounded, color: AppTokens.accent) : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await rust_storage.saveManga(manga: manga);
                    await ref.read(libraryProvider.notifier).addToList(manga.id, cat.key);
                    ref.invalidate(libraryProvider);
                    setState(() {});
                    if (context.mounted) {
                      final name = _libraryCategoryLabel(cat.key, s);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.movedTo(name))),
                      );
                    }
                  },
                );
              }),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: Text(s.removeFromLibrary, style: const TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref.read(libraryProvider.notifier).removeFromList(manga.id, 'all');
                  ref.invalidate(libraryProvider);
                  setState(() {});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.removedFromLibrary)),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverTabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surfaceBase,
        border: Border(
          bottom: BorderSide(
            color: overlapsContent ? AppTokens.accent.withValues(alpha: 0.3) : const Color(0xFF2E2E2E),
            width: 1,
          ),
        ),
      ),
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return _tabBar != oldDelegate._tabBar;
  }
}

