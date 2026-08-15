import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/models/achievement.dart';
import 'package:mangaloader/providers/streak_provider.dart';
import 'package:mangaloader/providers/library_provider.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/models.dart';

class AchievementsOverview {
  final List<Achievement> achievements;
  final int totalXp;
  final int level;
  final String levelTitleRu;
  final String levelTitleEn;
  final int currentLevelXp;
  final int nextLevelXp;
  final int unlockedCount;
  final int totalCount;

  const AchievementsOverview({
    required this.achievements,
    required this.totalXp,
    required this.level,
    required this.levelTitleRu,
    required this.levelTitleEn,
    required this.currentLevelXp,
    required this.nextLevelXp,
    required this.unlockedCount,
    required this.totalCount,
  });

  double get levelProgress => (nextLevelXp - currentLevelXp) > 0
      ? (totalXp - currentLevelXp) / (nextLevelXp - currentLevelXp)
      : 1.0;
}

final achievementsProvider = FutureProvider<AchievementsOverview>((ref) async {
  final streak = ref.watch(streakProvider).value;
  final libraryList = ref.watch(libraryProvider).value ?? [];
  final isAmoled = ref.watch(amoledModeProvider);

  final streakDays = streak?.maxStreak.toInt() ?? 0;
  final totalChapters = streak?.totalChaptersRead.toInt() ?? 0;
  final totalDays = streak?.totalDaysRead.toInt() ?? 0;

  // Query SQLite for additional statistics
  int downloadedChaptersCount = 0;
  int completedMangaCount = 0;
  final libraryCount = libraryList.length;

  try {
    final downloadedGroups = await rust_storage.getDownloadedMangaGroups();
    for (final g in downloadedGroups) {
      downloadedChaptersCount += g.chapters.length;
    }
  } catch (_) {}

  completedMangaCount = libraryList.where((e) => e.listType == ListType.completed).length;

  final all = <Achievement>[
    // --- 1. STREAKS ---
    Achievement(
      id: 'streak_1',
      category: AchievementCategory.streak,
      titleRu: 'Первая искра',
      titleEn: 'First Spark',
      descRu: 'Поддержите стрик чтения в течение 1 дня',
      descEn: 'Maintain a 1-day reading streak',
      icon: Icons.local_fire_department_rounded,
      iconColor: const Color(0xFFFF9800),
      tier: AchievementTier.bronze,
      xp: 10,
      maxProgress: 1,
      currentProgress: streakDays >= 1 ? 1 : 0,
      isUnlocked: streakDays >= 1,
    ),
    Achievement(
      id: 'streak_3',
      category: AchievementCategory.streak,
      titleRu: 'Разгорающееся пламя',
      titleEn: 'Kindling Flame',
      descRu: 'Поддержите стрик чтения в течение 3 дней подряд',
      descEn: 'Keep a 3-day consecutive reading streak',
      icon: Icons.local_fire_department_rounded,
      iconColor: const Color(0xFFFF6D00),
      tier: AchievementTier.bronze,
      xp: 20,
      maxProgress: 3,
      currentProgress: streakDays.clamp(0, 3),
      isUnlocked: streakDays >= 3,
    ),
    Achievement(
      id: 'streak_7',
      category: AchievementCategory.streak,
      titleRu: 'Огненный читатель',
      titleEn: 'Blazing Reader',
      descRu: 'Достигните стрика в 7 дней подряд',
      descEn: 'Achieve a 7-day reading streak',
      icon: Icons.whatshot_rounded,
      iconColor: const Color(0xFFFF1744),
      tier: AchievementTier.silver,
      xp: 40,
      maxProgress: 7,
      currentProgress: streakDays.clamp(0, 7),
      isUnlocked: streakDays >= 7,
    ),
    Achievement(
      id: 'streak_14',
      category: AchievementCategory.streak,
      titleRu: 'Хранитель пламени',
      titleEn: 'Flame Keeper',
      descRu: 'Две недели ежедневного чтения (14 дней)',
      descEn: 'Two weeks of daily reading streak (14 days)',
      icon: Icons.whatshot_rounded,
      iconColor: const Color(0xFFD500F9),
      tier: AchievementTier.silver,
      xp: 60,
      maxProgress: 14,
      currentProgress: streakDays.clamp(0, 14),
      isUnlocked: streakDays >= 14,
    ),
    Achievement(
      id: 'streak_30',
      category: AchievementCategory.streak,
      titleRu: 'Неоновый марафон',
      titleEn: 'Neon Marathon',
      descRu: 'Целый месяц непрерывного чтения (30 дней)',
      descEn: 'A full month of continuous reading (30 days)',
      icon: Icons.whatshot_rounded,
      iconColor: const Color(0xFF00E5FF),
      tier: AchievementTier.gold,
      xp: 100,
      maxProgress: 30,
      currentProgress: streakDays.clamp(0, 30),
      isUnlocked: streakDays >= 30,
    ),
    Achievement(
      id: 'streak_50',
      category: AchievementCategory.streak,
      titleRu: 'Золотой рубеж',
      titleEn: 'Golden Milestone',
      descRu: '50 дней ежедневного чтения',
      descEn: '50 consecutive days of reading',
      icon: Icons.whatshot_rounded,
      iconColor: const Color(0xFFFFD700),
      tier: AchievementTier.gold,
      xp: 150,
      maxProgress: 50,
      currentProgress: streakDays.clamp(0, 50),
      isUnlocked: streakDays >= 50,
    ),
    Achievement(
      id: 'streak_100',
      category: AchievementCategory.streak,
      titleRu: 'Сотня без перерыва',
      titleEn: 'Centurion of Manga',
      descRu: '100 дней подряд с зажженным огоньком',
      descEn: '100 consecutive days with an active reading flame',
      icon: Icons.whatshot_rounded,
      iconColor: const Color(0xFFFF3D00),
      tier: AchievementTier.platinum,
      xp: 250,
      maxProgress: 100,
      currentProgress: streakDays.clamp(0, 100),
      isUnlocked: streakDays >= 100,
    ),
    Achievement(
      id: 'streak_200',
      category: AchievementCategory.streak,
      titleRu: 'Солнечный феникс',
      titleEn: 'Solar Phoenix',
      descRu: '200 дней нерушимого стрика',
      descEn: '200 days unbroken streak',
      icon: Icons.whatshot_rounded,
      iconColor: const Color(0xFFAA00FF),
      tier: AchievementTier.platinum,
      xp: 400,
      maxProgress: 200,
      currentProgress: streakDays.clamp(0, 200),
      isUnlocked: streakDays >= 200,
    ),
    Achievement(
      id: 'streak_365',
      category: AchievementCategory.streak,
      titleRu: 'Год с мангой',
      titleEn: 'A Year of Manga',
      descRu: '365 дней ежедневного чтения без единого пропуска',
      descEn: '365 days of reading without skipping a day',
      icon: Icons.whatshot_rounded,
      iconColor: const Color(0xFF00E676),
      tier: AchievementTier.legendary,
      xp: 750,
      maxProgress: 365,
      currentProgress: streakDays.clamp(0, 365),
      isUnlocked: streakDays >= 365,
    ),
    Achievement(
      id: 'streak_500',
      category: AchievementCategory.streak,
      titleRu: 'Небесная сверхновая',
      titleEn: 'Celestial Supernova',
      descRu: '500 дней ежедневного погружения в истории',
      descEn: '500 days reading streak',
      icon: Icons.whatshot_rounded,
      iconColor: const Color(0xFFFF007F),
      tier: AchievementTier.legendary,
      xp: 1000,
      maxProgress: 500,
      currentProgress: streakDays.clamp(0, 500),
      isUnlocked: streakDays >= 500,
    ),
    Achievement(
      id: 'streak_1000',
      category: AchievementCategory.streak,
      titleRu: 'Вечный бог манги',
      titleEn: 'Eternal Manga God',
      descRu: '1000 дней стрика — абсолютная легенда MangaLoader',
      descEn: '1000 days reading streak — absolute legend',
      icon: Icons.whatshot_rounded,
      iconColor: const Color(0xFFFFEA00),
      tier: AchievementTier.legendary,
      xp: 2000,
      maxProgress: 1000,
      currentProgress: streakDays.clamp(0, 1000),
      isUnlocked: streakDays >= 1000,
    ),

    // --- 2. CHAPTERS READ ---
    Achievement(
      id: 'chap_1',
      category: AchievementCategory.chapters,
      titleRu: 'Первая страница',
      titleEn: 'First Chapter',
      descRu: 'Прочитайте 1 любую главу',
      descEn: 'Read your first chapter',
      icon: Icons.menu_book_rounded,
      iconColor: const Color(0xFF81C784),
      tier: AchievementTier.bronze,
      xp: 10,
      maxProgress: 1,
      currentProgress: totalChapters >= 1 ? 1 : 0,
      isUnlocked: totalChapters >= 1,
    ),
    Achievement(
      id: 'chap_25',
      category: AchievementCategory.chapters,
      titleRu: 'Начало пути',
      titleEn: 'On the Path',
      descRu: 'Прочитайте 25 глав',
      descEn: 'Read 25 chapters',
      icon: Icons.auto_stories_rounded,
      iconColor: const Color(0xFF64B5F6),
      tier: AchievementTier.bronze,
      xp: 25,
      maxProgress: 25,
      currentProgress: totalChapters.clamp(0, 25),
      isUnlocked: totalChapters >= 25,
    ),
    Achievement(
      id: 'chap_100',
      category: AchievementCategory.chapters,
      titleRu: 'Книжный червь',
      titleEn: 'Bookworm',
      descRu: 'Прочитайте 100 глав',
      descEn: 'Read 100 chapters',
      icon: Icons.auto_stories_rounded,
      iconColor: const Color(0xFF4FC3F7),
      tier: AchievementTier.silver,
      xp: 50,
      maxProgress: 100,
      currentProgress: totalChapters.clamp(0, 100),
      isUnlocked: totalChapters >= 100,
    ),
    Achievement(
      id: 'chap_250',
      category: AchievementCategory.chapters,
      titleRu: 'Неутомимый читатель',
      titleEn: 'Tireless Reader',
      descRu: 'Прочитайте 250 глав',
      descEn: 'Read 250 chapters',
      icon: Icons.auto_stories_rounded,
      iconColor: const Color(0xFFBA68C8),
      tier: AchievementTier.silver,
      xp: 80,
      maxProgress: 250,
      currentProgress: totalChapters.clamp(0, 250),
      isUnlocked: totalChapters >= 250,
    ),
    Achievement(
      id: 'chap_500',
      category: AchievementCategory.chapters,
      titleRu: 'Пожиратель страниц',
      titleEn: 'Page Devourer',
      descRu: 'Прочитайте 500 глав',
      descEn: 'Read 500 chapters',
      icon: Icons.auto_stories_rounded,
      iconColor: const Color(0xFFFFB74D),
      tier: AchievementTier.gold,
      xp: 150,
      maxProgress: 500,
      currentProgress: totalChapters.clamp(0, 500),
      isUnlocked: totalChapters >= 500,
    ),
    Achievement(
      id: 'chap_1000',
      category: AchievementCategory.chapters,
      titleRu: 'Тысячник',
      titleEn: 'Chapter Millennial',
      descRu: 'Прочитайте 1 000 глав',
      descEn: 'Read 1,000 chapters',
      icon: Icons.emoji_events_rounded,
      iconColor: const Color(0xFFFFD700),
      tier: AchievementTier.gold,
      xp: 250,
      maxProgress: 1000,
      currentProgress: totalChapters.clamp(0, 1000),
      isUnlocked: totalChapters >= 1000,
    ),
    Achievement(
      id: 'chap_2500',
      category: AchievementCategory.chapters,
      titleRu: 'Манга-маньяк',
      titleEn: 'Manga Maniac',
      descRu: 'Прочитайте 2 500 глав',
      descEn: 'Read 2,500 chapters',
      icon: Icons.military_tech_rounded,
      iconColor: const Color(0xFFFF5722),
      tier: AchievementTier.platinum,
      xp: 450,
      maxProgress: 2500,
      currentProgress: totalChapters.clamp(0, 2500),
      isUnlocked: totalChapters >= 2500,
    ),
    Achievement(
      id: 'chap_5000',
      category: AchievementCategory.chapters,
      titleRu: 'Ходячая мангапедия',
      titleEn: 'Living Mangapedia',
      descRu: 'Прочитайте 5 000 глав',
      descEn: 'Read 5,000 chapters',
      icon: Icons.workspace_premium_rounded,
      iconColor: const Color(0xFFFF1744),
      tier: AchievementTier.legendary,
      xp: 800,
      maxProgress: 5000,
      currentProgress: totalChapters.clamp(0, 5000),
      isUnlocked: totalChapters >= 5000,
    ),

    // --- 3. LIBRARY & COLLECTION ---
    Achievement(
      id: 'lib_1',
      category: AchievementCategory.library,
      titleRu: 'Свой уголок',
      titleEn: 'My Corner',
      descRu: 'Добавьте 1 тайтл в библиотеку',
      descEn: 'Add 1 manga to your library',
      icon: Icons.bookmark_add_rounded,
      iconColor: const Color(0xFF8A897C),
      tier: AchievementTier.bronze,
      xp: 10,
      maxProgress: 1,
      currentProgress: libraryCount >= 1 ? 1 : 0,
      isUnlocked: libraryCount >= 1,
    ),
    Achievement(
      id: 'lib_10',
      category: AchievementCategory.library,
      titleRu: 'Коллекционер',
      titleEn: 'Collector',
      descRu: 'Добавьте 10 тайтлов в библиотеку',
      descEn: 'Add 10 manga to library',
      icon: Icons.bookmarks_rounded,
      iconColor: const Color(0xFF64B5F6),
      tier: AchievementTier.bronze,
      xp: 25,
      maxProgress: 10,
      currentProgress: libraryCount.clamp(0, 10),
      isUnlocked: libraryCount >= 10,
    ),
    Achievement(
      id: 'lib_50',
      category: AchievementCategory.library,
      titleRu: 'Архивариус',
      titleEn: 'Archivist',
      descRu: 'Соберите 50 тайтлов в библиотеке',
      descEn: 'Collect 50 titles in library',
      icon: Icons.folder_special_rounded,
      iconColor: const Color(0xFFFFB74D),
      tier: AchievementTier.silver,
      xp: 75,
      maxProgress: 50,
      currentProgress: libraryCount.clamp(0, 50),
      isUnlocked: libraryCount >= 50,
    ),
    Achievement(
      id: 'lib_100',
      category: AchievementCategory.library,
      titleRu: 'Музей манги',
      titleEn: 'Manga Museum',
      descRu: 'Соберите 100 тайтлов в библиотеке',
      descEn: 'Collect 100 titles in library',
      icon: Icons.account_balance_rounded,
      iconColor: const Color(0xFFFFD700),
      tier: AchievementTier.gold,
      xp: 150,
      maxProgress: 100,
      currentProgress: libraryCount.clamp(0, 100),
      isUnlocked: libraryCount >= 100,
    ),
    Achievement(
      id: 'comp_1',
      category: AchievementCategory.library,
      titleRu: 'Финал истории',
      titleEn: 'Story Finale',
      descRu: 'Полностью прочитайте 1 тайтл',
      descEn: 'Complete reading 1 manga series',
      icon: Icons.check_circle_outline_rounded,
      iconColor: const Color(0xFF81C784),
      tier: AchievementTier.bronze,
      xp: 30,
      maxProgress: 1,
      currentProgress: completedMangaCount >= 1 ? 1 : 0,
      isUnlocked: completedMangaCount >= 1,
    ),
    Achievement(
      id: 'comp_10',
      category: AchievementCategory.library,
      titleRu: 'Коллекционер концовок',
      titleEn: 'Ending Collector',
      descRu: 'Полностью прочитайте 10 тайтлов',
      descEn: 'Complete reading 10 manga series',
      icon: Icons.task_alt_rounded,
      iconColor: const Color(0xFF4CAF50),
      tier: AchievementTier.gold,
      xp: 150,
      maxProgress: 10,
      currentProgress: completedMangaCount.clamp(0, 10),
      isUnlocked: completedMangaCount >= 10,
    ),

    // --- 4. DOWNLOADS & OFFLINE ---
    Achievement(
      id: 'down_1',
      category: AchievementCategory.downloads,
      titleRu: 'Все свое ношу с собой',
      titleEn: 'Pocket Reader',
      descRu: 'Скачайте 1 главу для оффлайн-чтения',
      descEn: 'Download 1 chapter for offline reading',
      icon: Icons.download_done_rounded,
      iconColor: const Color(0xFF4FC3F7),
      tier: AchievementTier.bronze,
      xp: 15,
      maxProgress: 1,
      currentProgress: downloadedChaptersCount >= 1 ? 1 : 0,
      isUnlocked: downloadedChaptersCount >= 1,
    ),
    Achievement(
      id: 'down_25',
      category: AchievementCategory.downloads,
      titleRu: 'Готов к бункеру',
      titleEn: 'Bunker Ready',
      descRu: 'Скачайте 25 глав в формате CBZ',
      descEn: 'Download 25 chapters as CBZ',
      icon: Icons.downloading_rounded,
      iconColor: const Color(0xFF29B6F6),
      tier: AchievementTier.silver,
      xp: 50,
      maxProgress: 25,
      currentProgress: downloadedChaptersCount.clamp(0, 25),
      isUnlocked: downloadedChaptersCount >= 25,
    ),
    Achievement(
      id: 'down_100',
      category: AchievementCategory.downloads,
      titleRu: 'Оффлайн-титан',
      titleEn: 'Offline Titan',
      descRu: 'Скачайте 100 глав',
      descEn: 'Download 100 chapters',
      icon: Icons.offline_pin_rounded,
      iconColor: const Color(0xFF0288D1),
      tier: AchievementTier.gold,
      xp: 150,
      maxProgress: 100,
      currentProgress: downloadedChaptersCount.clamp(0, 100),
      isUnlocked: downloadedChaptersCount >= 100,
    ),

    // --- 5. SPECIAL & MISC ---
    Achievement(
      id: 'spec_amoled',
      category: AchievementCategory.special,
      titleRu: 'Повелитель тьмы',
      titleEn: 'Lord of Shadows',
      descRu: 'Включите режим Pure AMOLED в настройках',
      descEn: 'Enable Pure AMOLED mode in Settings',
      icon: Icons.brightness_2_rounded,
      iconColor: const Color(0xFF9E9E9E),
      tier: AchievementTier.bronze,
      xp: 20,
      maxProgress: 1,
      currentProgress: isAmoled ? 1 : 0,
      isUnlocked: isAmoled,
    ),
    Achievement(
      id: 'spec_days_10',
      category: AchievementCategory.special,
      titleRu: 'Преданный фанат',
      titleEn: 'Devoted Fan',
      descRu: 'Проведите 10 активных дней в приложении',
      descEn: 'Spend 10 active days in app',
      icon: Icons.calendar_month_rounded,
      iconColor: const Color(0xFF8A897C),
      tier: AchievementTier.silver,
      xp: 50,
      maxProgress: 10,
      currentProgress: totalDays.clamp(0, 10),
      isUnlocked: totalDays >= 10,
    ),
    Achievement(
      id: 'spec_days_100',
      category: AchievementCategory.special,
      titleRu: 'Ветеран MangaLoader',
      titleEn: 'MangaLoader Veteran',
      descRu: '100 активных дней в приложении',
      descEn: '100 active days in app',
      icon: Icons.stars_rounded,
      iconColor: const Color(0xFFFFD700),
      tier: AchievementTier.platinum,
      xp: 200,
      maxProgress: 100,
      currentProgress: totalDays.clamp(0, 100),
      isUnlocked: totalDays >= 100,
    ),
  ];

  int totalXp = 0;
  int unlockedCount = 0;
  for (final a in all) {
    if (a.isUnlocked) {
      totalXp += a.xp;
      unlockedCount++;
    }
  }

  // Level formula: Level = sqrt(totalXp / 25) + 1
  final level = (totalXp / 100).floor() + 1;
  final currentLevelXp = (level - 1) * 100;
  final nextLevelXp = level * 100;

  String levelTitleRu = 'Новичок';
  String levelTitleEn = 'Beginner';
  if (level >= 20) {
    levelTitleRu = 'Бог манги';
    levelTitleEn = 'Manga God';
  } else if (level >= 15) {
    levelTitleRu = 'Легендарный читатель';
    levelTitleEn = 'Legendary Reader';
  } else if (level >= 10) {
    levelTitleRu = 'Мастер историй';
    levelTitleEn = 'Story Master';
  } else if (level >= 6) {
    levelTitleRu = 'Опытный мангака-фан';
    levelTitleEn = 'Experienced Reader';
  } else if (level >= 3) {
    levelTitleRu = 'Увлечённый читатель';
    levelTitleEn = 'Enthusiastic Reader';
  }

  return AchievementsOverview(
    achievements: all,
    totalXp: totalXp,
    level: level,
    levelTitleRu: levelTitleRu,
    levelTitleEn: levelTitleEn,
    currentLevelXp: currentLevelXp,
    nextLevelXp: nextLevelXp,
    unlockedCount: unlockedCount,
    totalCount: all.length,
  );
});
