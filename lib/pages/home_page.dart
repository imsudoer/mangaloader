import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/widgets/manga_card.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/providers/streak_provider.dart';
import 'package:mangaloader/providers/continue_reading_provider.dart';
import 'package:mangaloader/widgets/update_bottom_sheet.dart';
import 'package:mangaloader/widgets/reading_streak_button.dart';
import 'package:mangaloader/widgets/continue_reading_section.dart';
import 'package:mangaloader/services/streak_notification_service.dart';

final homeDataProvider = FutureProvider.autoDispose<HomePageData>((ref) async {
  return await rust_api.getHomepage();
});

final topViewsPeriodProvider = StateProvider<String>((ref) => 'day');

final topViewsCustomProvider = FutureProvider.autoDispose.family<List<MangaSearchResult>, String>((ref, time) async {
  return await rust_api.getTopViews(time: time);
});

final recommendationsProvider = FutureProvider.autoDispose<List<RecommendedManga>>((ref) async {
  return await rust_storage.getRecommendations(limit: 10);
});

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _dismissedUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdatesSilently();
    });
  }

  Future<void> _checkUpdatesSilently() async {
    final autoCheck = ref.read(autoCheckUpdatesProvider);
    if (!autoCheck) return;
    final currentUpdate = ref.read(availableUpdateProvider);
    if (currentUpdate != null) return;

    try {
      final channel = ref.read(updateChannelProvider);
      final info = await UpdateChecker.checkForUpdates(channel: channel);
      if (info != null && info.hasUpdate && mounted) {
        ref.read(availableUpdateProvider.notifier).state = info;
        final isRu = Localizations.localeOf(context).languageCode == 'ru';
        StreakNotificationService.showUpdateNotificationOnce(info, isRu: isRu);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final homeAsync = ref.watch(homeDataProvider);
    final topPeriod = ref.watch(topViewsPeriodProvider);
    final availableUpdate = ref.watch(availableUpdateProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF8A897C),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Manga Loader', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
          ],
        ),
        actions: [
          const ReadingStreakButton(),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: isRu ? 'История чтения' : 'Reading History',
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: isRu ? 'Каталог и поиск' : 'Catalog & Search',
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.link_rounded),
            tooltip: isRu ? 'Вставить ссылку' : 'Paste Link',
            onPressed: () => _showPasteLinkDialog(context, isRu),
          ),
        ],
      ),
      body: homeAsync.when(
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(homeDataProvider);
            ref.invalidate(topViewsCustomProvider);
            ref.invalidate(continueReadingProvider);
            ref.read(streakProvider.notifier).loadStreak();
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              // Available Update Banner
              if (availableUpdate != null && !_dismissedUpdate) ...[
                _buildUpdateBanner(context, availableUpdate, isRu),
                const SizedBox(height: 12),
              ],

              // Continue Reading (Always at the top)
              ContinueReadingSection(isRu: isRu),
              const SizedBox(height: 16),

              // Recommendations Section
              _buildRecommendationsSection(isRu),
              const SizedBox(height: 20),

              // Popular Section
              if (data.popular.isNotEmpty) ...[
                _buildSectionHeader(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: Colors.orangeAccent,
                  title: isRu ? 'Популярное' : 'Popular',
                  subtitle: isRu ? 'Самые читаемые тайтлы' : 'Most read titles',
                  onSeeAll: () => context.go('/search'),
                  isRu: isRu,
                ),
                const SizedBox(height: 12),
                _buildHorizontalMangaList(data.popular),
                const SizedBox(height: 24),
              ],

              // Top Views with Period Filter
              _buildTopViewsSection(topPeriod, data.topViews, isRu),
              const SizedBox(height: 24),

              // Latest Updates
              if (data.latestUpdates.isNotEmpty) ...[
                _buildSectionHeader(
                  icon: Icons.update_rounded,
                  iconColor: Colors.lightBlueAccent,
                  title: isRu ? 'Свежие обновления' : 'Latest Updates',
                  subtitle: isRu ? 'Недавно вышедшие главы' : 'Recently updated chapters',
                  onSeeAll: () => context.go('/search'),
                  isRu: isRu,
                ),
                const SizedBox(height: 12),
                _buildHorizontalMangaList(data.latestUpdates),
                const SizedBox(height: 24),
              ],

              // New Releases
              if (data.newest.isNotEmpty) ...[
                _buildSectionHeader(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: Colors.amberAccent,
                  title: isRu ? 'Новинки' : 'New Releases',
                  subtitle: isRu ? 'Недавно добавленные произведения' : 'Recently added manga',
                  onSeeAll: () => context.go('/search'),
                  isRu: isRu,
                ),
                const SizedBox(height: 12),
                _buildHorizontalMangaList(data.newest),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  isRu ? 'Не удалось загрузить рекомендации' : 'Failed to load recommendations',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('$err', style: const TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(homeDataProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(isRu ? 'Повторить' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopViewsSection(String currentPeriod, List<MangaSearchResult> defaultItems, bool isRu) {
    final asyncViews = ref.watch(topViewsCustomProvider(currentPeriod));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.trending_up_rounded, size: 20, color: Colors.greenAccent),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRu ? 'Топ по просмотрам' : 'Top Views',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        isRu ? 'Самые просматриваемые' : 'Most viewed titles',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFBDBBB0)),
                      ),
                    ],
                  ),
                ],
              ),
              // Period Switcher Chips
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF3E3E3E)),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPeriodBtn('day', isRu ? 'День' : 'Day', currentPeriod),
                    _buildPeriodBtn('week', isRu ? 'Неделя' : 'Week', currentPeriod),
                    _buildPeriodBtn('month', isRu ? 'Месяц' : 'Month', currentPeriod),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        asyncViews.when(
          data: (items) => _buildHorizontalMangaList(items.isNotEmpty ? items : defaultItems),
          loading: () => const SizedBox(
            height: 230,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => _buildHorizontalMangaList(defaultItems),
        ),
      ],
    );
  }

  Widget _buildPeriodBtn(String key, String label, String activeKey) {
    final isActive = key == activeKey;
    return InkWell(
      onTap: () {
        ref.read(topViewsPeriodProvider.notifier).state = key;
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF8A897C) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.white : const Color(0xFFBDBBB0),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onSeeAll,
    required bool isRu,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFBDBBB0)),
                  ),
                ],
              ),
            ],
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(isRu ? 'Все' : 'See all', style: const TextStyle(color: Color(0xFFD2D7DF))),
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalMangaList(List<MangaSearchResult> items) {
    return SizedBox(
      height: 230,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final manga = items[index];
          return Container(
            width: 140,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: MangaCard(
              manga: manga,
              onTap: () => context.push('/manga/${manga.slugUrl}'),
            ),
          );
        },
      ),
    );
  }

  void _showPasteLinkDialog(BuildContext context, bool isRu) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(isRu ? 'Вставить ссылку' : 'Paste Link'),
        content: TextField(
          decoration: const InputDecoration(hintText: 'https://mangalib.me/...'),
          onSubmitted: (val) {
            Navigator.pop(ctx);
            final parsedUrl = rust_api.parseMangaUrl(url: val);
            if (parsedUrl != null) {
              context.push('/manga/$parsedUrl');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(isRu ? 'Неверная ссылка' : 'Invalid link')),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildUpdateBanner(BuildContext context, AppUpdateInfo update, bool isRu) {
    return InkWell(
      onTap: () => AppUpdateBottomSheet.show(context, ref, update, isRu),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF8A897C).withValues(alpha: 0.22),
              const Color(0xFF2C2C2C),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF8A897C).withValues(alpha: 0.45),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF8A897C).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF8A897C).withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: const Icon(Icons.system_update_rounded, color: Color(0xFFD2D7DF), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isRu ? 'Новое обновление' : 'New Update',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8A897C),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          update.tagName.startsWith('v') ? update.tagName : 'v${update.tagName}',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isRu ? 'Нажмите, чтобы открыть список изменений' : 'Tap to see changelog & install',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFFBDBBB0)),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8A897C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => AppUpdateBottomSheet.show(context, ref, update, isRu),
              child: Text(isRu ? 'Обновить' : 'Update', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
              tooltip: isRu ? 'Скрыть' : 'Dismiss',
              onPressed: () => setState(() => _dismissedUpdate = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationsSection(bool isRu) {
    final recAsync = ref.watch(recommendationsProvider);

    return recAsync.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.recommend_rounded,
              iconColor: const Color(0xFF81C784),
              title: isRu ? 'Рекомендации для вас' : 'Recommended For You',
              subtitle: isRu ? 'На основе ваших вкусов' : 'Based on your reading preferences',
              onSeeAll: () => context.go('/search'),
              isRu: isRu,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 230,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final rec = items[index];
                  final mangaSearch = MangaSearchResult(
                    id: rec.mangaId,
                    name: rec.name,
                    rusName: rec.rusName,
                    engName: '',
                    slug: '',
                    slugUrl: rec.slugUrl,
                    coverUrl: rec.coverUrl,
                    coverThumbUrl: rec.coverThumbUrl,
                    mangaType: rec.mangaType,
                    typeId: 0,
                    status: '',
                    statusId: 0,
                    ageRestriction: '',
                    ratingAverage: rec.ratingAverage,
                    ratingVotes: '0',
                    releaseDate: null,
                  );

                  return Container(
                    width: 140,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: MangaCard(
                      manga: mangaSearch,
                      onTap: () => context.push('/manga/${rec.slugUrl}'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

