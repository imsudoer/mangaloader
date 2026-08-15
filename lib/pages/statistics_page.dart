import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/statistics_provider.dart';
import 'package:mangaloader/src/rust/api/models.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final statsAsync = ref.watch(statisticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isRu ? 'Статистика чтения' : 'Reading Statistics', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: statsAsync.when(
        data: (stats) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(statisticsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary 2x3 Grid
              _buildSummarySection(stats, isRu),
              const SizedBox(height: 20),

              // Genres Section
              _buildGenresSection(stats.topGenres, isRu),
              const SizedBox(height: 20),

              // Time of Day Section
              _buildTimeOfDaySection(stats.timeOfDay, isRu),
              const SizedBox(height: 20),

              // Streaks Section
              _buildStreakSection(stats, isRu),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
      ),
    );
  }

  Widget _buildSummarySection(ReadingStatistics stats, bool isRu) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isRu ? 'Общие показатели' : 'Overview',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildMetricCard(Icons.menu_book_rounded, '${stats.totalChaptersRead}', isRu ? 'Прочитано глав' : 'Chapters Read', const Color(0xFF64B5F6))),
            const SizedBox(width: 10),
            Expanded(child: _buildMetricCard(Icons.auto_stories_rounded, '${stats.totalPagesRead}', isRu ? 'Страниц прочитано' : 'Pages Read', const Color(0xFF81C784))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildMetricCard(Icons.task_alt_rounded, '${stats.completedMangaCount}', isRu ? 'Завершено тайтлов' : 'Completed Manga', const Color(0xFFFFB74D))),
            const SizedBox(width: 10),
            Expanded(child: _buildMetricCard(Icons.bookmark_outline_rounded, '${stats.inProgressMangaCount}', isRu ? 'В процессе чтения' : 'In Progress', const Color(0xFFBA68C8))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildMetricCard(Icons.folder_outlined, '${stats.totalLibraryCount}', isRu ? 'Всего в библиотеке' : 'Library Titles', const Color(0xFF8A897C))),
            const SizedBox(width: 10),
            Expanded(child: _buildMetricCard(Icons.download_done_rounded, '${stats.totalDownloadedChapters}', isRu ? 'Скачано глав (CBZ)' : 'Downloaded (CBZ)', const Color(0xFF4FC3F7))),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(IconData icon, String value, String label, Color accentColor) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF353535), width: 0.8),
      ),
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: accentColor),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFFBDBBB0)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenresSection(List<GenreCount> genres, bool isRu) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF353535), width: 0.8),
      ),
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart_outline_rounded, size: 20, color: Color(0xFF8A897C)),
                const SizedBox(width: 8),
                Text(
                  isRu ? 'Любимые жанры' : 'Top Genres',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (genres.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  isRu ? 'Пока нет данных. Читайте больше глав!' : 'No data yet. Read more chapters!',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A897C)),
                ),
              )
            else
              ...genres.map((g) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(g.name, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
                          Text('${g.percentage}% (${g.count})', style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A897C))),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (g.percentage / 100).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: const Color(0xFF2A2A2A),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8A897C)),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeOfDaySection(TimeOfDayDistribution tod, bool isRu) {
    final total = tod.nightCount + tod.morningCount + tod.afternoonCount + tod.eveningCount;
    double calcPct(int count) => total > 0 ? (count / total * 100) : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF353535), width: 0.8),
      ),
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 20, color: Color(0xFF8A897C)),
                const SizedBox(width: 8),
                Text(
                  isRu ? 'Время активности' : 'Reading Activity Time',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _buildTimePeriodItem(Icons.nightlight_round, isRu ? 'Ночь' : 'Night', '00:00 - 06:00', '${calcPct(tod.nightCount.toInt()).toStringAsFixed(0)}%', const Color(0xFF5C6BC0))),
                Expanded(child: _buildTimePeriodItem(Icons.wb_sunny_outlined, isRu ? 'Утро' : 'Morning', '06:00 - 12:00', '${calcPct(tod.morningCount.toInt()).toStringAsFixed(0)}%', const Color(0xFFFFB74D))),
                Expanded(child: _buildTimePeriodItem(Icons.wb_sunny_rounded, isRu ? 'День' : 'Afternoon', '12:00 - 18:00', '${calcPct(tod.afternoonCount.toInt()).toStringAsFixed(0)}%', const Color(0xFF4FC3F7))),
                Expanded(child: _buildTimePeriodItem(Icons.bedtime_outlined, isRu ? 'Вечер' : 'Evening', '18:00 - 24:00', '${calcPct(tod.eveningCount.toInt()).toStringAsFixed(0)}%', const Color(0xFFAB47BC))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePeriodItem(IconData icon, String title, String timeRange, String pct, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(pct, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(timeRange, style: const TextStyle(fontSize: 9, color: Color(0xFF8A897C))),
      ],
    );
  }

  Widget _buildStreakSection(ReadingStatistics stats, bool isRu) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF353535), width: 0.8),
      ),
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.whatshot_rounded, size: 20, color: Color(0xFFFF5722)),
                const SizedBox(width: 8),
                Text(
                  isRu ? 'Рекорды стрика' : 'Streak Highlights',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text('${stats.currentStreakDays}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text(isRu ? 'Текущий стрик' : 'Current Streak', style: const TextStyle(fontSize: 11, color: Color(0xFFBDBBB0))),
                  ],
                ),
                Container(width: 1, height: 30, color: const Color(0xFF353535)),
                Column(
                  children: [
                    Text('${stats.maxStreakDays}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                    Text(isRu ? 'Лучший рекорд' : 'Best Record', style: const TextStyle(fontSize: 11, color: Color(0xFFBDBBB0))),
                  ],
                ),
                Container(width: 1, height: 30, color: const Color(0xFF353535)),
                Column(
                  children: [
                    Text('${stats.totalActiveDays}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF81C784))),
                    Text(isRu ? 'Дней в приложении' : 'Active Days', style: const TextStyle(fontSize: 11, color: Color(0xFFBDBBB0))),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
