import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mangaloader/l10n/strings/achievements_strings.dart';
import 'package:mangaloader/models/achievement.dart';
import 'package:mangaloader/providers/achievements_provider.dart';
import 'package:mangaloader/providers/streak_provider.dart';
import 'package:mangaloader/services/achievement_events.dart';
import 'package:mangaloader/theme/app_tokens.dart';
import 'package:mangaloader/widgets/achievement_card.dart';

class AchievementsPage extends ConsumerStatefulWidget {
  const AchievementsPage({super.key});

  @override
  ConsumerState<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends ConsumerState<AchievementsPage> {
  static const List<String> _categories = [
    'all',
    'chapters',
    'streak',
    'library',
    'downloads',
    'titles',
    'special',
    'secrets',
  ];
  static const List<String> _filters = ['all', 'inProgress', 'unlocked'];

  String _category = 'all';
  String _filter = 'all';
  final Stopwatch _session = Stopwatch();

  @override
  void initState() {
    super.initState();
    final events = AchievementEvents.instance;
    events.increment('achievements_visits');
    final chapters = ref.read(streakProvider).value?.totalChaptersRead.toInt() ?? 0;
    if (chapters == 0) {
      events.increment('start_of_path');
    }
    _session.start();
  }

  @override
  void dispose() {
    if (_session.isRunning) {
      _session.stop();
      final seconds = _session.elapsed.inSeconds;
      if (seconds > 0) {
        AchievementEvents.instance.increment('achievements_seconds', seconds);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final s = AchievementsStrings(isRu);
    final overviewAsync = ref.watch(achievementsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: overviewAsync.when(
        data: (overview) {
          final all = overview.achievements;
          final filtered = _applyFilters(all);
          final counts = _categoryCounts(all);
          final secretTotal = all.where((a) => a.isSecret).length;
          final secretUnlocked = all.where((a) => a.isSecret && a.isUnlocked).length;
          final nearest = _nearest(all);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _buildHero(s, overview, secretUnlocked, secretTotal),
                ),
              ),
              if (nearest != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildNearest(s, nearest, isRu),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 0, 0),
                  child: _buildCategoryRail(s, counts),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _buildFilters(s),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.filter_alt_off_rounded, size: 40, color: AppTokens.textSecondary),
                          const SizedBox(height: 10),
                          Text(
                            isRu ? 'Здесь пока пусто' : 'Nothing here yet',
                            style: const TextStyle(color: AppTokens.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 215,
                      mainAxisSpacing: 11,
                      crossAxisSpacing: 11,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final achievement = filtered[index];
                      return AchievementGridCard(
                        achievement: achievement,
                        isRu: isRu,
                        onTap: () => AchievementDetailSheet.show(context, achievement, isRu),
                      );
                    },
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_outlined, size: 44, color: AppTokens.textSecondary),
                const SizedBox(height: 12),
                Text(
                  isRu ? 'Не удалось загрузить достижения' : 'Could not load achievements',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTokens.textSecondary),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(achievementsProvider),
                  child: Text(isRu ? 'Повторить' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(
    AchievementsStrings s,
    AchievementsOverview overview,
    int secretUnlocked,
    int secretTotal,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF232320), Color(0xFF171717)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 78,
                      height: 78,
                      child: CircularProgressIndicator(
                        value: overview.levelProgress,
                        strokeWidth: 5,
                        backgroundColor: AppTokens.border,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.accent),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${overview.level}',
                          style: const TextStyle(fontSize: 26, height: 1, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.levelLabel.toUpperCase(),
                          style: const TextStyle(fontSize: 7.5, letterSpacing: 1, color: AppTokens.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Localizations.localeOf(context).languageCode == 'ru'
                          ? overview.levelTitleRu
                          : overview.levelTitleEn,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    Text(
                    '${overview.totalXp} XP · ${overview.nextLevelXp - overview.totalXp} '
                    '${Localizations.localeOf(context).languageCode == 'ru' ? 'XP до ${overview.level + 1} ур.' : 'XP to lvl ${overview.level + 1}'}',
                    style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
                  ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: overview.levelProgress,
                        minHeight: 6,
                        backgroundColor: AppTokens.border,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _heroStat(
                  s.collectionLabel,
                  '${overview.unlockedCount}/${overview.totalCount}',
                  Icons.collections_bookmark_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _heroStat(
                  s.secretsLabel,
                  '$secretUnlocked/$secretTotal',
                  Icons.lock_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _heroStat(
                  s.levelLabel,
                  '${overview.level}',
                  Icons.military_tech_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppTokens.accent),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTokens.textSecondary, fontSize: 8.5),
          ),
        ],
      ),
    );
  }

  Widget _buildNearest(AchievementsStrings s, Achievement nearest, bool isRu) {
    final remaining = nearest.maxProgress - nearest.currentProgress;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => AchievementDetailSheet.show(context, nearest, isRu),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTokens.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTokens.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTokens.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(nearest.icon, size: 20, color: AppTokens.accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.nearestTitle.toUpperCase(),
                    style: const TextStyle(fontSize: 8.5, letterSpacing: 1, color: AppTokens.textSecondary, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nearest.isSecret && !nearest.isUnlocked
                        ? s.secretTitle
                        : (isRu ? nearest.titleRu : nearest.titleEn),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: nearest.progressRatio,
                      minHeight: 4,
                      backgroundColor: AppTokens.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              s.remaining('$remaining'),
              style: const TextStyle(fontSize: 10.5, color: AppTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRail(AchievementsStrings s, Map<String, int> counts) {
    final labels = <String, String>{
      'all': s.filterAll,
      'chapters': s.filterChapters,
      'streak': s.filterStreaks,
      'library': s.filterLibrary,
      'downloads': s.filterDownloads,
      'titles': s.filterTitles,
      'special': s.filterSpecial,
      'secrets': s.filterSecrets,
    };
    final icons = <String, IconData>{
      'all': Icons.grid_view_rounded,
      'chapters': Icons.menu_book_rounded,
      'streak': Icons.local_fire_department_rounded,
      'library': Icons.collections_bookmark_rounded,
      'downloads': Icons.download_rounded,
      'titles': Icons.auto_stories_rounded,
      'special': Icons.auto_awesome_rounded,
      'secrets': Icons.lock_rounded,
    };

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final key = _categories[index];
          final selected = key == _category;
          return InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () => setState(() => _category = key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? AppTokens.accent.withValues(alpha: 0.18) : AppTokens.surfaceRaised,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: selected ? AppTokens.accent : AppTokens.borderStrong),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icons[key], size: 13, color: selected ? AppTokens.accent : AppTokens.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    labels[key] ?? key,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: selected ? Colors.white : AppTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${counts[key] ?? 0}',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: selected ? AppTokens.accent : AppTokens.textSecondary,
                      fontWeight: FontWeight.w800,
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

  Widget _buildFilters(AchievementsStrings s) {
    final labels = <String, String>{
      'all': s.filterAll,
      'inProgress': s.filterInProgress,
      'unlocked': s.filterUnlocked,
    };
    return Row(
      children: [
        for (var i = 0; i < _filters.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _filter = _filters[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _filter == _filters[i] ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _filter == _filters[i] ? AppTokens.borderStrong : AppTokens.border,
                  ),
                ),
                child: Text(
                  labels[_filters[i]] ?? _filters[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: _filter == _filters[i] ? FontWeight.bold : FontWeight.w500,
                    color: _filter == _filters[i] ? Colors.white : AppTokens.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Map<String, int> _categoryCounts(List<Achievement> all) {
    final counts = <String, int>{'all': all.length};
    for (final category in AchievementCategory.values) {
      counts[category.name] = all.where((a) => a.category == category).length;
    }
    return counts;
  }

  List<Achievement> _applyFilters(List<Achievement> all) {
    var list = all.where((a) {
      if (_category != 'all' && a.category.name != _category) return false;
      if (_filter == 'unlocked') return a.isUnlocked;
      if (_filter == 'inProgress') return !a.isUnlocked && a.currentProgress > 0;
      return true;
    }).toList();

    list.sort((a, b) {
      if (a.isUnlocked != b.isUnlocked) return a.isUnlocked ? -1 : 1;
      final progress = b.progressRatio.compareTo(a.progressRatio);
      if (progress != 0) return progress;
      return b.tier.index.compareTo(a.tier.index);
    });
    return list;
  }

  Achievement? _nearest(List<Achievement> all) {
    Achievement? best;
    for (final achievement in all) {
      if (achievement.isUnlocked) continue;
      if (achievement.isSecret) continue;
      if (achievement.currentProgress <= 0) continue;
      if (best == null || achievement.progressRatio > best.progressRatio) {
        best = achievement;
      }
    }
    return best;
  }
}