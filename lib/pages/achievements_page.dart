import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mangaloader/models/achievement.dart';
import 'package:mangaloader/providers/achievements_provider.dart';

class AchievementsPage extends ConsumerStatefulWidget {
  const AchievementsPage({super.key});

  @override
  ConsumerState<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends ConsumerState<AchievementsPage> {
  String _selectedCategory = 'all';

  void _shareAchievement(Achievement a, bool isRu) {
    final title = isRu ? a.titleRu : a.titleEn;
    final desc = isRu ? a.descRu : a.descEn;
    final text = isRu
        ? 'Я получил достижение «$title» ($desc) в MangaLoader! +${a.xp} XP'
        : 'I unlocked the achievement "$title" ($desc) in MangaLoader! +${a.xp} XP';
    SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(achievementsProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return Scaffold(
      appBar: AppBar(
        title: Text(isRu ? 'Достижения' : 'Achievements', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: overviewAsync.when(
        data: (overview) {
          final list = overview.achievements.where((a) {
            if (_selectedCategory == 'all') return true;
            if (_selectedCategory == 'unlocked') return a.isUnlocked;
            if (_selectedCategory == 'streak') return a.category == AchievementCategory.streak;
            if (_selectedCategory == 'chapters') return a.category == AchievementCategory.chapters;
            if (_selectedCategory == 'library') return a.category == AchievementCategory.library;
            if (_selectedCategory == 'downloads') return a.category == AchievementCategory.downloads;
            if (_selectedCategory == 'special') return a.category == AchievementCategory.special;
            return true;
          }).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(achievementsProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Level & XP Hero Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFF3E3E3E), width: 1),
                  ),
                  color: const Color(0xFF242424),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF8A897C).withValues(alpha: 0.25),
                                border: Border.all(color: const Color(0xFF8A897C), width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  '${overview.level}',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isRu ? overview.levelTitleRu : overview.levelTitleEn,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${overview.totalXp} XP • ${overview.unlockedCount} / ${overview.totalCount} ${isRu ? "открыто" : "unlocked"}',
                                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFD2D7DF)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: overview.levelProgress,
                            minHeight: 6,
                            backgroundColor: const Color(0xFF353535),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8A897C)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${overview.totalXp} XP',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFBDBBB0)),
                            ),
                            Text(
                              '${overview.nextLevelXp} XP (${isRu ? "След. уровень" : "Next level"})',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFBDBBB0)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Category Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', isRu ? 'Все' : 'All', overview.achievements.length),
                      const SizedBox(width: 8),
                      _buildFilterChip('unlocked', isRu ? 'Полученные' : 'Unlocked', overview.unlockedCount),
                      const SizedBox(width: 8),
                      _buildFilterChip('streak', isRu ? 'Стрики' : 'Streaks', 11),
                      const SizedBox(width: 8),
                      _buildFilterChip('chapters', isRu ? 'Главы' : 'Chapters', 8),
                      const SizedBox(width: 8),
                      _buildFilterChip('library', isRu ? 'Библиотека' : 'Library', 6),
                      const SizedBox(width: 8),
                      _buildFilterChip('downloads', isRu ? 'Оффлайн' : 'Downloads', 3),
                      const SizedBox(width: 8),
                      _buildFilterChip('special', isRu ? 'Особые' : 'Special', 3),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Achievements List
                ...list.map((a) => _buildAchievementCard(a, isRu)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, int count) {
    final isSelected = _selectedCategory == key;
    return FilterChip(
      selected: isSelected,
      label: Text('$label ($count)'),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : const Color(0xFFD2D7DF),
      ),
      selectedColor: const Color(0xFF8A897C),
      backgroundColor: const Color(0xFF2C2C2C),
      side: BorderSide(color: isSelected ? const Color(0xFF8A897C) : const Color(0xFF3E3E3E)),
      onSelected: (_) => setState(() => _selectedCategory = key),
    );
  }

  Widget _buildAchievementCard(Achievement a, bool isRu) {
    final tierColor = a.getTierColor();
    final isDone = a.isUnlocked;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDone ? tierColor.withValues(alpha: 0.5) : const Color(0xFF353535),
          width: isDone ? 1.2 : 0.8,
        ),
      ),
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? a.iconColor.withValues(alpha: 0.2) : const Color(0xFF2A2A2A),
                border: Border.all(
                  color: isDone ? a.iconColor.withValues(alpha: 0.6) : const Color(0xFF3A3A3A),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Icon(
                  a.icon,
                  color: isDone ? a.iconColor : const Color(0xFF757575),
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          isRu ? a.titleRu : a.titleEn,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: isDone ? Colors.white : const Color(0xFFBDBBB0),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tierColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: tierColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '+${a.xp} XP',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: tierColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isRu ? a.descRu : a.descEn,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFBDBBB0)),
                  ),
                  const SizedBox(height: 8),

                  // Progress bar or Done Badge
                  if (a.maxProgress > 1) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: a.progressRatio,
                        minHeight: 4,
                        backgroundColor: const Color(0xFF2C2C2C),
                        valueColor: AlwaysStoppedAnimation<Color>(isDone ? a.iconColor : const Color(0xFF8A897C)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${a.currentProgress} / ${a.maxProgress}',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A897C)),
                        ),
                        if (isDone)
                          InkWell(
                            onTap: () => _shareAchievement(a, isRu),
                            child: Row(
                              children: [
                                const Icon(Icons.share_rounded, size: 12, color: Color(0xFF8A897C)),
                                const SizedBox(width: 4),
                                Text(
                                  isRu ? 'Поделиться' : 'Share',
                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A897C), fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ] else if (isDone) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: () => _shareAchievement(a, isRu),
                          child: Row(
                            children: [
                              const Icon(Icons.share_rounded, size: 12, color: Color(0xFF8A897C)),
                              const SizedBox(width: 4),
                              Text(
                                isRu ? 'Поделиться' : 'Share',
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A897C), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
