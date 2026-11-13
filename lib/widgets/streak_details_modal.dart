import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mangaloader/l10n/strings/streak_details_strings.dart';
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/providers/streak_provider.dart';
import 'package:mangaloader/utils/plural.dart';
import 'package:mangaloader/theme/app_tokens.dart';

class StreakDetailsModal extends ConsumerWidget {
  final ReadingStreakInfo streak;
  final bool isRu;

  const StreakDetailsModal({
    super.key,
    required this.streak,
    required this.isRu,
  });

  static Future<void> show(BuildContext context, WidgetRef ref, ReadingStreakInfo streak, bool isRu) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StreakDetailsModal(streak: streak, isRu: isRu),
    );
  }

  Color _getFlameColor(int days, bool isActiveToday) {
    if (days == 0 || !isActiveToday) return const Color(0xFF9E9E9E);
    if (days < 3) return const Color(0xFFFF9800); // 1-2: Bronze
    if (days < 7) return const Color(0xFFFF6D00); // 3-6: Amber
    if (days < 14) return const Color(0xFFFF1744); // 7-13: Crimson
    if (days < 30) return const Color(0xFFD500F9); // 14-29: Violet
    if (days < 50) return const Color(0xFF00E5FF); // 30-49: Cyan Plasma
    if (days < 100) return const Color(0xFFFFD700); // 50-99: Gold
    if (days < 200) return const Color(0xFFFF3D00); // 100-199: Solar Phoenix
    if (days < 365) return const Color(0xFFAA00FF); // 200-364: Cosmic Amethyst
    if (days < 500) return const Color(0xFF00E676); // 365-499: Emerald Year
    if (days < 750) return const Color(0xFFFF007F); // 500-749: Supernova
    if (days < 1000) return const Color(0xFF7C4DFF); // 750-999: Void Dragon
    return const Color(0xFFFFEA00); // 1000+: Eternal Manga God
  }

  String _getRankTitle(int days, bool isRu) {
    final s = StreakDetailsStrings(isRu);
    if (days == 0) return s.rankSpark;
    if (days < 3) return s.rankFirstSpark;
    if (days < 7) return s.rankIgnited;
    if (days < 14) return s.rankBlazing;
    if (days < 30) return s.rankFlameKeeper;
    if (days < 50) return s.rankPlasmaMaster;
    if (days < 100) return s.rankGoldenTorch;
    if (days < 200) return s.rankSolarPhoenix;
    if (days < 365) return s.rankCosmicWarden;
    if (days < 500) return s.rankEmeraldYear;
    if (days < 750) return s.rankCelestialSupernova;
    if (days < 1000) return s.rankVoidDragon;
    return s.rankEternalMangaGod;
  }

  void _shareStreak(BuildContext context) {
    final s = StreakDetailsStrings(isRu);
    final days = streak.currentStreak.toInt();
    final rank = _getRankTitle(days, isRu);
    final text = s.shareText(Plural.days(days, isRu ? 'ru' : 'en'), rank);
    SharePlus.instance.share(ShareParams(text: text));
  }

  void _showSecretDialog(BuildContext context, WidgetRef ref) {
    final s = StreakDetailsStrings(isRu);
    final controller = TextEditingController(text: '${streak.currentStreak}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surfaceCard,
        title: Text(s.syncStreakTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: s.streakDaysLabel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.accent),
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val >= 0) {
                ref.read(streakProvider.notifier).syncStreak(val);
                Navigator.pop(ctx);
                Navigator.pop(context);
              }
            },
            child: Text(s.apply),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = StreakDetailsStrings(isRu);
    final days = streak.currentStreak.toInt();
    final flameColor = _getFlameColor(days, streak.isActiveToday);
    final rankTitle = _getRankTitle(days, isRu);
    final currentStreak = streak.currentStreak.toInt();
    final maxStreak = streak.maxStreak.toInt();

    // Week days calculation for tracker
    final now = DateTime.now();
    final weekDays = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final dStr = "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      final isToday = i == 6;
      final isDone = streak.historyDates.contains(dStr) || (isToday && streak.isActiveToday);
      return {'day': d, 'isDone': isDone, 'isToday': isToday};
    });

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: AppTokens.surfaceBase,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: flameColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTokens.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Giant Evolving Flame Badge (with secret long-press testing gesture)
              GestureDetector(
                onLongPress: () => _showSecretDialog(context, ref),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: flameColor.withValues(alpha: 0.15),
                    border: Border.all(color: flameColor.withValues(alpha: 0.5), width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: flameColor.withValues(alpha: 0.25),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      days >= 7 ? Icons.whatshot_rounded : Icons.local_fire_department_rounded,
                      size: 52,
                      color: flameColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Streak Count & Rank
              Text(
                Plural.days(currentStreak, isRu ? 'ru' : 'en'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: flameColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: flameColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  rankTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: flameColor,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Today's Status Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: streak.isActiveToday
                      ? Colors.green.shade900.withValues(alpha: 0.2)
                      : AppTokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: streak.isActiveToday
                        ? Colors.green.shade700.withValues(alpha: 0.4)
                        : AppTokens.borderStrong,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      streak.isActiveToday ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: streak.isActiveToday ? Colors.greenAccent : AppTokens.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        streak.isActiveToday
                            ? s.goalCompleted('${streak.todayChaptersCount}')
                            : s.goalPending,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: streak.isActiveToday ? Colors.white : AppTokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 7-Day Week History Ring
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  s.weekActivity,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTokens.textSecondary),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (idx) {
                  final item = weekDays[idx];
                  final isDone = item['isDone'] as bool;
                  final isToday = item['isToday'] as bool;
                  final d = item['day'] as DateTime;
                  final label = s.weekDayLabels[d.weekday - 1];

                  return Column(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? flameColor.withValues(alpha: 0.25)
                              : AppTokens.surfaceRaised,
                          border: Border.all(
                            color: isToday
                                ? flameColor
                                : (isDone ? flameColor.withValues(alpha: 0.6) : AppTokens.borderStrong),
                            width: isToday ? 2.0 : 1.0,
                          ),
                        ),
                        child: Center(
                          child: isDone
                              ? Icon(Icons.check_rounded, size: 18, color: flameColor)
                              : Text(
                                  '${d.day}',
                                  style: const TextStyle(fontSize: 11, color: AppTokens.accent),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isToday ? Colors.white : AppTokens.accent,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 20),

              // Statistics Row
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppTokens.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTokens.borderStrong),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.emoji_events_outlined, size: 18, color: AppTokens.accent),
                          const SizedBox(height: 4),
                          Text(
                            s.bestStreakDays('$maxStreak'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            s.bestStreak,
                            style: const TextStyle(fontSize: 10.5, color: AppTokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppTokens.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTokens.borderStrong),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.menu_book_rounded, size: 18, color: AppTokens.accent),
                          const SizedBox(height: 4),
                          Text(
                            '${streak.totalChaptersRead}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            s.chaptersRead,
                            style: const TextStyle(fontSize: 10.5, color: AppTokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppTokens.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTokens.borderStrong),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18, color: AppTokens.accent),
                          const SizedBox(height: 4),
                          Text(
                            '${streak.totalDaysRead}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            s.activeDays,
                            style: const TextStyle(fontSize: 10.5, color: AppTokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Share Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: flameColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _shareStreak(context),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(
                    s.shareStreak,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // All Achievements Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.textPrimary,
                    side: const BorderSide(color: AppTokens.borderStrong),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    GoRouter.of(context).push('/achievements');
                  },
                  icon: const Icon(Icons.emoji_events_rounded, size: 18, color: Color(0xFFFFD700)),
                  label: Text(
                    s.allAchievements,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
