import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mangaloader/src/rust/api/models.dart';

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
    if (days < 3) return const Color(0xFFFF9800);
    if (days < 7) return const Color(0xFFFF6D00);
    if (days < 14) return const Color(0xFFFF1744);
    if (days < 30) return const Color(0xFFD500F9);
    if (days < 50) return const Color(0xFF00E5FF);
    if (days < 100) return const Color(0xFFFFD700);
    return const Color(0xFFFF3D00);
  }

  String _getRankTitle(int days, bool isRu) {
    if (days == 0) return isRu ? 'Искра' : 'Spark';
    if (days < 3) return isRu ? 'Первый огонёк' : 'First Spark';
    if (days < 7) return isRu ? 'Разгорающийся' : 'Ignited Reader';
    if (days < 14) return isRu ? 'Огненный читатель' : 'Blazing Reader';
    if (days < 30) return isRu ? 'Хранитель пламени' : 'Flame Keeper';
    if (days < 50) return isRu ? 'Неоновый призрак' : 'Plasma Master';
    if (days < 100) return isRu ? 'Золотой факел' : 'Golden Torch';
    return isRu ? 'Легендарное солнце' : 'Solar Legend';
  }

  void _shareStreak(BuildContext context) {
    final days = streak.currentStreak.toInt();
    final rank = _getRankTitle(days, isRu);
    final text = isRu
        ? 'Мой стрик в MangaLoader: $days ${days == 1 ? "день" : (days < 5 ? "дня" : "дней")} подряд! Ранг: $rank. Читаю каждый день!'
        : 'My reading streak in MangaLoader is $days days! Rank: $rank. Reading every day!';
    SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final weekDayLabelsRu = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final weekDayLabelsEn = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
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
                    color: const Color(0xFF3E3E3E),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Giant Evolving Flame Badge
              Container(
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
              const SizedBox(height: 12),

              // Streak Count & Rank
              Text(
                '$currentStreak ${isRu ? (currentStreak == 1 ? "день" : (currentStreak < 5 && currentStreak > 1 ? "дня" : "дней")) : "days"}',
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
                      : const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: streak.isActiveToday
                        ? Colors.green.shade700.withValues(alpha: 0.4)
                        : const Color(0xFF3E3E3E),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      streak.isActiveToday ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: streak.isActiveToday ? Colors.greenAccent : const Color(0xFF8A897C),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        streak.isActiveToday
                            ? (isRu
                                ? 'Сегодня цель выполнена! Прочитано глав: ${streak.todayChaptersCount}'
                                : 'Daily goal completed! Chapters read: ${streak.todayChaptersCount}')
                            : (isRu
                                ? 'Прочитайте 1 главу сегодня, чтобы зажечь огонёк!'
                                : 'Read 1 chapter today to keep your streak!'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: streak.isActiveToday ? Colors.white : const Color(0xFFD2D7DF),
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
                  isRu ? 'Активность за последние 7 дней:' : 'Last 7 Days Activity:',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFBDBBB0)),
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
                  final label = (isRu ? weekDayLabelsRu : weekDayLabelsEn)[d.weekday - 1];

                  return Column(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? flameColor.withValues(alpha: 0.25)
                              : const Color(0xFF2C2C2C),
                          border: Border.all(
                            color: isToday
                                ? flameColor
                                : (isDone ? flameColor.withValues(alpha: 0.6) : const Color(0xFF3E3E3E)),
                            width: isToday ? 2.0 : 1.0,
                          ),
                        ),
                        child: Center(
                          child: isDone
                              ? Icon(Icons.check_rounded, size: 18, color: flameColor)
                              : Text(
                                  '${d.day}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF8A897C)),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isToday ? Colors.white : const Color(0xFF8A897C),
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
                        color: const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF3E3E3E)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.emoji_events_outlined, size: 18, color: Color(0xFF8A897C)),
                          const SizedBox(height: 4),
                          Text(
                            '$maxStreak ${isRu ? "дн." : "d."}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            isRu ? 'Рекорд стрика' : 'Best Streak',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFFBDBBB0)),
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
                        color: const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF3E3E3E)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.menu_book_rounded, size: 18, color: Color(0xFF8A897C)),
                          const SizedBox(height: 4),
                          Text(
                            '${streak.totalChaptersRead}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            isRu ? 'Всего глав' : 'Chapters Read',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFFBDBBB0)),
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
                        color: const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF3E3E3E)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF8A897C)),
                          const SizedBox(height: 4),
                          Text(
                            '${streak.totalDaysRead}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            isRu ? 'Дней с нами' : 'Active Days',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFFBDBBB0)),
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
                    isRu ? 'Поделиться стриком' : 'Share Streak',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
