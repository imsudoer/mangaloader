import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/streak_provider.dart';
import 'package:mangaloader/widgets/streak_details_modal.dart';

class ReadingStreakButton extends ConsumerWidget {
  const ReadingStreakButton({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(streakProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return streakAsync.when(
      data: (streak) {
        final days = streak.currentStreak.toInt();
        final isActiveToday = streak.isActiveToday;
        final flameColor = _getFlameColor(days, isActiveToday);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => StreakDetailsModal.show(context, ref, streak, isRu),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: flameColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: flameColor.withValues(alpha: isActiveToday ? 0.7 : 0.3),
                  width: isActiveToday ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    days >= 7 ? Icons.whatshot_rounded : Icons.local_fire_department_rounded,
                    size: 18,
                    color: flameColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$days',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: flameColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox(width: 24, height: 24),
      error: (_, __) => const SizedBox(),
    );
  }
}
