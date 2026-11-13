import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/l10n/strings/statistics_strings.dart';
import 'package:mangaloader/providers/statistics_provider.dart';
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/theme/app_theme.dart';
import 'package:mangaloader/theme/app_tokens.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final s = StatisticsStrings(isRu);
    final statsAsync = ref.watch(statisticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: statsAsync.when(
        data: (stats) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(statisticsProvider);
            ref.invalidate(readingSessionStatsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary 2x3 Grid
              _buildSummarySection(stats, isRu),
              const SizedBox(height: 20),

              // Real Reading Time Section
              _buildReadingTimeSection(ref, isRu),
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
        error: (e, _) => Center(child: Text(s.error('$e'))),
      ),
    );
  }

  Widget _buildSummarySection(ReadingStatistics stats, bool isRu) {
    final s = StatisticsStrings(isRu);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.overview,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildMetricCard(Icons.menu_book_rounded, '${stats.totalChaptersRead}', s.chaptersRead, const Color(0xFF64B5F6))),
            const SizedBox(width: 10),
            Expanded(child: _buildMetricCard(Icons.auto_stories_rounded, '${stats.totalPagesRead}', s.pagesRead, const Color(0xFF81C784))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildMetricCard(Icons.task_alt_rounded, '${stats.completedMangaCount}', s.completedManga, const Color(0xFFFFB74D))),
            const SizedBox(width: 10),
            Expanded(child: _buildMetricCard(Icons.bookmark_outline_rounded, '${stats.inProgressMangaCount}', s.inProgress, const Color(0xFFBA68C8))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildMetricCard(Icons.folder_outlined, '${stats.totalLibraryCount}', s.libraryTitles, AppTokens.accent)),
            const SizedBox(width: 10),
            Expanded(child: _buildMetricCard(Icons.download_done_rounded, '${stats.totalDownloadedChapters}', s.downloadedChapters, const Color(0xFF4FC3F7))),
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
        side: const BorderSide(color: AppTokens.border, width: 0.8),
      ),
      color: AppTokens.surfaceBase,
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
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenresSection(List<GenreCount> genres, bool isRu) {
    final s = StatisticsStrings(isRu);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTokens.border, width: 0.8),
      ),
      color: AppTokens.surfaceBase,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart_outline_rounded, size: 20, color: AppTokens.accent),
                const SizedBox(width: 8),
                Text(
                  s.topGenres,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (genres.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  s.noGenreData,
                  style: const TextStyle(fontSize: 12, color: AppTokens.accent),
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
                          Text('${g.percentage}% (${g.count})', style: const TextStyle(fontSize: 11.5, color: AppTokens.accent, fontFeatures: AppTheme.tabularFigures)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (g.percentage / 100).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: const Color(0xFF2A2A2A),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.accent),
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
    final s = StatisticsStrings(isRu);
    final total = tod.nightCount + tod.morningCount + tod.afternoonCount + tod.eveningCount;
    double calcPct(int count) => total > 0 ? (count / total * 100) : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTokens.border, width: 0.8),
      ),
      color: AppTokens.surfaceBase,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 20, color: AppTokens.accent),
                const SizedBox(width: 8),
                Text(
                  s.activityTime,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _buildTimePeriodItem(Icons.nightlight_round, s.night, '00:00 - 06:00', '${calcPct(tod.nightCount.toInt()).toStringAsFixed(0)}%', const Color(0xFF5C6BC0))),
                Expanded(child: _buildTimePeriodItem(Icons.wb_sunny_outlined, s.morning, '06:00 - 12:00', '${calcPct(tod.morningCount.toInt()).toStringAsFixed(0)}%', const Color(0xFFFFB74D))),
                Expanded(child: _buildTimePeriodItem(Icons.wb_sunny_rounded, s.afternoon, '12:00 - 18:00', '${calcPct(tod.afternoonCount.toInt()).toStringAsFixed(0)}%', const Color(0xFF4FC3F7))),
                Expanded(child: _buildTimePeriodItem(Icons.bedtime_outlined, s.evening, '18:00 - 24:00', '${calcPct(tod.eveningCount.toInt()).toStringAsFixed(0)}%', const Color(0xFFAB47BC))),
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
        Text(pct, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFeatures: AppTheme.tabularFigures)),
        const SizedBox(height: 2),
        Text(timeRange, style: const TextStyle(fontSize: 9, color: AppTokens.accent)),
      ],
    );
  }

  Widget _buildStreakSection(ReadingStatistics stats, bool isRu) {
    final s = StatisticsStrings(isRu);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTokens.border, width: 0.8),
      ),
      color: AppTokens.surfaceBase,
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
                  s.streakHighlights,
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
                    Text('${stats.currentStreakDays}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, fontFeatures: AppTheme.tabularFigures)),
                    Text(s.currentStreak, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
                  ],
                ),
                Container(width: 1, height: 30, color: AppTokens.border),
                Column(
                  children: [
                    Text('${stats.maxStreakDays}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFFFD700), fontFeatures: AppTheme.tabularFigures)),
                    Text(s.bestRecord, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
                  ],
                ),
                Container(width: 1, height: 30, color: AppTokens.border),
                Column(
                  children: [
                    Text('${stats.totalActiveDays}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF81C784), fontFeatures: AppTheme.tabularFigures)),
                    Text(s.activeDays, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingTimeSection(WidgetRef ref, bool isRu) {
    final s = StatisticsStrings(isRu);
    final sessionAsync = ref.watch(readingSessionStatsProvider);

    return sessionAsync.when(
      data: (sessions) {
        String formatSecs(int secs) {
          if (secs <= 0) return s.zeroMinutes;
          final h = secs ~/ 3600;
          final m = (secs % 3600) ~/ 60;
          if (h > 0) {
            return s.durationHoursMinutes('$h', '$m');
          }
          return s.durationMinutes('$m');
        }

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTokens.border, width: 0.8),
          ),
          color: AppTokens.surfaceBase,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 20, color: Color(0xFF64B5F6)),
                    const SizedBox(width: 8),
                    Text(
                      s.readingTimeTracker,
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
                        Text(formatSecs(sessions.todayReadingSeconds), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, fontFeatures: AppTheme.tabularFigures)),
                        Text(s.today, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
                      ],
                    ),
                    Container(width: 1, height: 28, color: AppTokens.border),
                    Column(
                      children: [
                        Text(formatSecs(sessions.weekReadingSeconds), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF81C784), fontFeatures: AppTheme.tabularFigures)),
                        Text(s.lastSevenDays, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
                      ],
                    ),
                    Container(width: 1, height: 28, color: AppTokens.border),
                    Column(
                      children: [
                        Text(formatSecs(sessions.totalReadingSeconds), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFFB74D), fontFeatures: AppTheme.tabularFigures)),
                        Text(s.allTime, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
