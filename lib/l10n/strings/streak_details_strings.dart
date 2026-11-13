import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class StreakDetailsStrings extends AppStrings {
  const StreakDetailsStrings(super.isRu);

  factory StreakDetailsStrings.of(BuildContext context) =>
      StreakDetailsStrings(AppStrings.isRussian(context));

  String get rankSpark => isRu ? 'Искра' : 'Spark';
  String get rankFirstSpark => isRu ? 'Первый огонёк' : 'First Spark';
  String get rankIgnited => isRu ? 'Разгорающийся' : 'Ignited Reader';
  String get rankBlazing => isRu ? 'Огненный читатель' : 'Blazing Reader';
  String get rankFlameKeeper => isRu ? 'Хранитель пламени' : 'Flame Keeper';
  String get rankPlasmaMaster => isRu ? 'Неоновый призрак' : 'Plasma Master';
  String get rankGoldenTorch => isRu ? 'Золотой факел' : 'Golden Torch';
  String get rankSolarPhoenix => isRu ? 'Солнечный феникс' : 'Solar Phoenix';
  String get rankCosmicWarden => isRu ? 'Космический страж' : 'Cosmic Warden';
  String get rankEmeraldYear => isRu ? 'Изумрудный год' : 'Emerald Year';
  String get rankCelestialSupernova =>
      isRu ? 'Небесная сверхновая' : 'Celestial Supernova';
  String get rankVoidDragon =>
      isRu ? 'Пламя дракона пустоты' : 'Void Dragon Fire';
  String get rankEternalMangaGod =>
      isRu ? 'Вечный бог манги' : 'Eternal Manga God';

  String shareText(String days, String rank) => isRu
      ? 'Мой стрик в MangaLoader: $days подряд! Ранг: $rank. Читаю каждый день!'
      : 'My reading streak in MangaLoader is $days! Rank: $rank. Reading every day!';

  String get syncStreakTitle =>
      isRu ? 'Синхронизация стрика' : 'Sync Streak';
  String get streakDaysLabel => isRu ? 'Количество дней' : 'Streak Days';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get apply => isRu ? 'Применить' : 'Apply';

  String goalCompleted(String chapters) => isRu
      ? 'Сегодня цель выполнена! Прочитано глав: $chapters'
      : 'Daily goal completed! Chapters read: $chapters';
  String get goalPending => isRu
      ? 'Прочитайте 1 главу сегодня, чтобы зажечь огонёк!'
      : 'Read 1 chapter today to keep your streak!';
  String get weekActivity => isRu
      ? 'Активность за последние 7 дней:'
      : 'Last 7 Days Activity:';
  List<String> get weekDayLabels => isRu
      ? const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
      : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  String bestStreakDays(String days) =>
      isRu ? '$days дн.' : '$days d.';
  String get bestStreak => isRu ? 'Рекорд стрика' : 'Best Streak';
  String get chaptersRead => isRu ? 'Всего глав' : 'Chapters Read';
  String get activeDays => isRu ? 'Дней с нами' : 'Active Days';

  String get shareStreak => isRu ? 'Поделиться стриком' : 'Share Streak';
  String get allAchievements => isRu ? 'Все достижения' : 'All Achievements';
}