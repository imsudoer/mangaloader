import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mangaloader/models/achievement.dart';
import 'package:mangaloader/services/achievement_events.dart';
import 'package:mangaloader/src/rust/api/models.dart';

/// Everything the extra achievements need. The catalog itself stays a pure
/// function of this data so the provider only has to fetch the snapshot once.
class AchievementData {
  const AchievementData({
    required this.snapshot,
    required this.streakDays,
    required this.totalChapters,
    required this.totalDays,
    required this.downloads,
    required this.downloadBytes,
    required this.libraryCount,
    required this.completedLibrary,
    required this.favorites,
    required this.planned,
    required this.dropped,
    required this.onHold,
    required this.reading,
    required this.amoled,
    required this.scheduleEnabled,
    required this.wifiOnly,
    required this.storageLimitSet,
    required this.prefetchNeighbours,
    required this.library,
    required this.events,
    required this.now,
  });

  final AchievementSnapshot snapshot;
  final int streakDays;
  final int totalChapters;
  final int totalDays;
  final int downloads;
  final int downloadBytes;
  final int libraryCount;
  final int completedLibrary;
  final int favorites;
  final int planned;
  final int dropped;
  final int onHold;
  final int reading;
  final bool amoled;
  final bool scheduleEnabled;
  final bool wifiOnly;
  final bool storageLimitSet;
  final bool prefetchNeighbours;
  final List<LibraryEntry> library;
  final AchievementEvents events;
  final DateTime now;
}

/// Adds the new achievements to the original streak/chapter/library/download
/// set. Exact duplicates of milestones that already exist are intentionally not
/// repeated: their old cards keep the unlock and XP.
List<Achievement> buildExtraAchievements(AchievementData d) {
  final snap = d.snapshot;
  final manga = snap.manga;
  final library = d.library;
  final events = d.events;

  final genres = <String>{
    for (final item in manga)
      for (final genre in item.genres)
        if (genre.trim().isNotEmpty) genre.trim().toLowerCase(),
  };

  final dates = <DateTime>[];
  for (final raw in snap.readDates) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) dates.add(DateTime(parsed.year, parsed.month, parsed.day));
  }
  dates.sort();
  final weekdays = {for (final date in dates) date.weekday};
  final months = {for (final date in dates) date.month};
  final seasons = <int>{
    for (final date in dates)
      switch (date.month) {
        12 || 1 || 2 => 0,
        3 || 4 || 5 => 1,
        6 || 7 || 8 => 2,
        _ => 3,
      },
  };

  int genreChapters(List<String> needles) {
    var total = 0;
    for (final item in manga) {
      final hasGenre = item.genres.any((genre) {
        final value = genre.toLowerCase();
        return needles.any((needle) => value.contains(needle));
      });
      if (hasGenre) total += item.chaptersRead.toInt();
    }
    return total;
  }

  bool completedOfType(List<String> needles) =>
      manga.any((item) => item.isCompleted && needles.any((needle) => item.mangaType.toLowerCase().contains(needle)));

  AchievementMangaStat? findTitle(List<String> needles) {
    for (final item in manga) {
      final haystack = '${item.slugUrl} ${item.name} ${item.rusName}'.toLowerCase();
      if (needles.any((needle) => haystack.contains(needle))) return item;
    }
    return null;
  }

  Achievement titleCard({
    required String id,
    required String titleRu,
    required String titleEn,
    required List<String> needles,
    required int chapters,
    required AchievementTier tier,
    required IconData icon,
    required String descRu,
    required String descEn,
    bool secret = false,
    String hintRu = '',
    String hintEn = '',
    bool completeOnly = false,
    int Function()? extra,
  }) {
    final found = findTitle(needles);
    final read = found?.chaptersRead.toInt() ?? 0;
    final unlockedGate = extra == null || extra() > 0;
    final int current;
    final int max;
    if (completeOnly) {
      current = (found?.isCompleted ?? false) ? 1 : 0;
      max = 1;
    } else {
      max = chapters;
      current = unlockedGate ? read.clamp(0, chapters) : 0;
    }
    return _make(
      id: id,
      category: AchievementCategory.titles,
      tier: tier,
      titleRu: titleRu,
      titleEn: titleEn,
      descRu: descRu,
      descEn: descEn,
      icon: icon,
      max: max,
      current: current,
      secret: secret,
      hintRu: hintRu,
      hintEn: hintEn,
      titleSlug: found?.slugUrl,
      titleCoverUrl: found?.coverUrl,
    );
  }



  bool hasFourSundays() {
    final sundays = [
      for (final date in dates)
        if (date.weekday == DateTime.sunday) date,
    ];
    for (var i = 0; i + 3 < sundays.length; i++) {
      final delta = sundays[i + 3].difference(sundays[i]).inDays;
      if (delta >= 21 && delta <= 23) return true;
    }
    return false;
  }

  bool hasReturnAfterGap() {
    for (var i = 1; i < dates.length; i++) {
      if (dates[i].difference(dates[i - 1]).inDays <= 1) continue;
      // Three consecutive days after the pause.
      final run = [dates[i]];
      for (var j = i + 1; j < dates.length && run.length < 3; j++) {
        if (dates[j].difference(run.last).inDays == 1) {
          run.add(dates[j]);
        }
      }
      if (run.length >= 3) return true;
    }
    return false;
  }

  bool finishedInOneDay() {
    for (final item in manga) {
      if (!item.isCompleted || item.chaptersRead < 5) continue;
      final first = DateTime.tryParse(item.firstReadAt);
      final last = DateTime.tryParse(item.lastReadAt);
      if (first == null || last == null) continue;
      if (first.year == last.year && first.month == last.month && first.day == last.day) {
        return true;
      }
    }
    return false;
  }

  int completedInSameGenre() {
    var best = 0;
    for (final genre in genres) {
      final count = manga
          .where((item) => item.isCompleted && item.genres.any((g) => g.toLowerCase() == genre))
          .length;
      if (count > best) best = count;
    }
    return best;
  }

  double? ratingOf(LibraryEntry entry) => double.tryParse(entry.ratingAverage);

  bool hasLowRated = library.any((entry) {
    final rating = ratingOf(entry);
    return rating != null && rating > 0 && rating < 6;
  });
  bool hasMasterpiece = library.any(
    (entry) => entry.listType == ListType.completed && (ratingOf(entry) ?? 0) >= 9,
  );

  bool hasRetroTitle() => manga.any((item) {
        final year = int.tryParse(item.releaseDate.split('-').first);
        return year != null && year > 1900 && year < 2000;
      });
  bool hasFreshTitle() => manga.any((item) {
        final year = int.tryParse(item.releaseDate.split('-').first);
        return year != null && year == d.now.year;
      });

  bool hasDoubleShift = snap.doubleShiftDays > 0;
  bool hasRtl = events.setOf('rtl_days').isNotEmpty;
  bool hasLtr = events.setOf('ltr_days').isNotEmpty;
  bool hasVertical = events.setOf('vertical_days').isNotEmpty;
  final rtlDays = events.setOf('rtl_days');
  final ltrDays = events.setOf('ltr_days');
  final bothModesSameDay = rtlDays.any(ltrDays.contains);

  int inDays(DateTime? first) {
    if (first == null) return 0;
    return DateTime(d.now.year, d.now.month, d.now.day)
        .difference(DateTime(first.year, first.month, first.day))
        .inDays;
  }

  final firstRead = DateTime.tryParse(snap.firstReadAt);
  final unreadPlanned = d.planned >= 50 && d.totalChapters == 0;
  final hasCopiedLog = events['copied_logs'] >= 1;
  final hasDeadLink = events['dead_links'] >= 1;
  final minutesOnAchievements = events['achievements_seconds'] >= 60;
  final languageSwitched = events['language_switches'] >= 1;
  final jumpedToEnd = events['jump_to_end'] >= 1;
  final offlineRead = events['offline_reads'] >= 1;
  final nightDownload = events['night_downloads'] >= 1;
  final commentsPosted = events['comments_posted'] >= 1;
  final replyPosted = events['comment_replies'] >= 1;
  final votesCast = events['votes_cast'] >= 1;
  final silentReader = d.totalChapters >= 100 && events['votes_cast'] == 0;
  final usedSchedule = d.scheduleEnabled;
  final usedWifiOnly = d.wifiOnly;
  final usedStorageLimit = d.storageLimitSet;
  final prefetchOn = d.prefetchNeighbours;

  final list = <Achievement>[
    // ---------------- Volume and reading rhythm ----------------
    _make(
      id: 'extra_chap_10',
      category: AchievementCategory.chapters,
      tier: AchievementTier.bronze,
      titleRu: 'Десятка',
      titleEn: 'Perfect Ten',
      descRu: 'Прочитайте 10 глав',
      descEn: 'Read 10 chapters',
      icon: Icons.looks_one_rounded,
      max: 10,
      current: d.totalChapters,
    ),
    _make(
      id: 'extra_chap_50',
      category: AchievementCategory.chapters,
      tier: AchievementTier.silver,
      titleRu: 'Полсотни',
      titleEn: 'Fifty Covers',
      descRu: 'Прочитайте 50 глав',
      descEn: 'Read 50 chapters',
      icon: Icons.filter_5_rounded,
      max: 50,
      current: d.totalChapters,
    ),
    _make(
      id: 'extra_pages_1000',
      category: AchievementCategory.chapters,
      tier: AchievementTier.silver,
      titleRu: 'Тысяча страниц',
      titleEn: 'Thousand Pages',
      descRu: 'Прочитайте 1000 страниц',
      descEn: 'Read 1000 pages',
      icon: Icons.pages_rounded,
      max: 1000,
      current: snap.totalPagesRead.toInt(),
    ),
    _make(
      id: 'extra_first_volume',
      category: AchievementCategory.chapters,
      tier: AchievementTier.bronze,
      titleRu: 'Первый том',
      titleEn: 'First Volume',
      descRu: 'Завершите все главы одного тома',
      descEn: 'Finish every chapter of one volume',
      icon: Icons.book_rounded,
      current: manga.any((item) => item.isCompleted && item.chaptersRead >= 5) ? 1 : 0,
    ),
    _make(
      id: 'extra_ten_volumes',
      category: AchievementCategory.chapters,
      tier: AchievementTier.gold,
      titleRu: 'Десять томов',
      titleEn: 'Ten Volumes',
      descRu: 'Завершите 10 томов',
      descEn: 'Finish 10 volumes',
      icon: Icons.library_books_rounded,
      max: 10,
      current: manga.where((item) => item.isCompleted).length,
    ),
    _make(
      id: 'extra_marathon',
      category: AchievementCategory.chapters,
      tier: AchievementTier.gold,
      titleRu: 'Марафонец',
      titleEn: 'Marathoner',
      descRu: 'Прочитайте 20 глав за сутки',
      descEn: 'Read 20 chapters in one day',
      icon: Icons.bolt_rounded,
      max: 20,
      current: snap.maxChaptersInDay.toInt(),
    ),
    _make(
      id: 'extra_one_day',
      category: AchievementCategory.chapters,
      tier: AchievementTier.gold,
      titleRu: 'Залпом',
      titleEn: 'In One Sitting',
      descRu: 'Завершите тайтл за одни сутки',
      descEn: 'Finish a title within one day',
      icon: Icons.local_fire_department_rounded,
      current: finishedInOneDay() ? 1 : 0,
    ),
    _make(
      id: 'extra_three_hours',
      category: AchievementCategory.chapters,
      tier: AchievementTier.gold,
      titleRu: 'Запой',
      titleEn: 'Binge Session',
      descRu: 'Проведите за чтением 3 часа без перерыва',
      descEn: 'Read for 3 hours in one session',
      icon: Icons.timer_rounded,
      max: 10800,
      current: snap.maxSessionSeconds.toInt(),
    ),
    _make(
      id: 'extra_hours_100',
      category: AchievementCategory.chapters,
      tier: AchievementTier.platinum,
      titleRu: 'Сто часов',
      titleEn: 'Hundred Hours',
      descRu: 'Проведите за чтением 100 часов',
      descEn: 'Spend 100 hours reading',
      icon: Icons.hourglass_bottom_rounded,
      max: 360000,
      current: snap.totalReadingSeconds.toInt(),
    ),
    _make(
      id: 'extra_hours_1000',
      category: AchievementCategory.chapters,
      tier: AchievementTier.legendary,
      titleRu: 'Тысяча часов',
      titleEn: 'Thousand Hours',
      descRu: 'Проведите за чтением 1000 часов',
      descEn: 'Spend 1000 hours reading',
      icon: Icons.hourglass_top_rounded,
      max: 3600000,
      current: snap.totalReadingSeconds.toInt(),
    ),

    // ---------------- Time and streaks ----------------
    _make(
      id: 'extra_return',
      category: AchievementCategory.streak,
      tier: AchievementTier.silver,
      titleRu: 'Возвращение',
      titleEn: 'The Return',
      descRu: 'Вернитесь после пропуска и продержитесь 3 дня',
      descEn: 'Return after a pause and keep a 3-day streak',
      icon: Icons.replay_rounded,
      current: hasReturnAfterGap() ? 1 : 0,
    ),
    _make(
      id: 'extra_double_shift',
      category: AchievementCategory.streak,
      tier: AchievementTier.silver,
      titleRu: 'Двойная смена',
      titleEn: 'Double Shift',
      descRu: 'Читайте до 08:00 и после 22:00 в один день',
      descEn: 'Read before 08:00 and after 22:00 on the same day',
      icon: Icons.dark_mode_rounded,
      current: hasDoubleShift ? 1 : 0,
    ),
    _make(
      id: 'extra_night_10',
      category: AchievementCategory.streak,
      tier: AchievementTier.silver,
      titleRu: 'Ночная смена',
      titleEn: 'Night Shift',
      descRu: 'Прочитайте 10 глав ночью',
      descEn: 'Read 10 chapters at night',
      icon: Icons.nightlight_round,
      max: 10,
      current: snap.nightReads.toInt(),
    ),
    _make(
      id: 'extra_dawn',
      category: AchievementCategory.streak,
      tier: AchievementTier.silver,
      titleRu: 'Рассвет',
      titleEn: 'At Dawn',
      descRu: 'Прочитайте главу в 05:00',
      descEn: 'Read a chapter at 05:00',
      icon: Icons.wb_twilight_rounded,
      current: snap.earlyReads.toInt() > 0 ? 1 : 0,
    ),
    _make(
      id: 'extra_sunday_ritual',
      category: AchievementCategory.streak,
      tier: AchievementTier.gold,
      titleRu: 'Воскресный ритуал',
      titleEn: 'Sunday Ritual',
      descRu: 'Читайте 4 воскресенья подряд',
      descEn: 'Read on four Sundays in a row',
      icon: Icons.event_available_rounded,
      current: hasFourSundays() ? 1 : 0,
    ),
    _make(
      id: 'extra_perfect_week',
      category: AchievementCategory.streak,
      tier: AchievementTier.silver,
      titleRu: 'Идеальная неделя',
      titleEn: 'Perfect Week',
      descRu: 'Прочитайте хотя бы по главе в каждый день недели',
      descEn: 'Read on every day of the week',
      icon: Icons.calendar_view_week_rounded,
      current: weekdays.length >= 7 ? 1 : 0,
    ),
    _make(
      id: 'extra_calendar',
      category: AchievementCategory.streak,
      tier: AchievementTier.gold,
      titleRu: 'Календарь',
      titleEn: 'Full Calendar',
      descRu: 'Читайте хотя бы раз в каждом месяце года',
      descEn: 'Read at least once in every month',
      icon: Icons.calendar_month_rounded,
      current: months.length >= 12 ? 1 : 0,
    ),
    _make(
      id: 'extra_long_liver',
      category: AchievementCategory.streak,
      tier: AchievementTier.platinum,
      titleRu: 'Долгожитель',
      titleEn: 'Long Liver',
      descRu: 'Читайте в приложении 365 дней',
      descEn: 'Keep reading in the app for 365 days',
      icon: Icons.workspace_premium_rounded,
      max: 365,
      current: inDays(firstRead),
    ),
    _make(
      id: 'extra_monday_morning',
      category: AchievementCategory.streak,
      tier: AchievementTier.silver,
      titleRu: 'Утро понедельника',
      titleEn: 'Monday Morning',
      descRu: 'Прочитайте главу в понедельник до 09:00',
      descEn: 'Read a chapter on Monday before 09:00',
      icon: Icons.wb_sunny_outlined,
      current: snap.mondayMorningReads.toInt() > 0 ? 1 : 0,
    ),
    _make(
      id: 'extra_season',
      category: AchievementCategory.streak,
      tier: AchievementTier.gold,
      titleRu: 'Сезонник',
      titleEn: 'Four Seasons',
      descRu: 'Читайте зимой, весной, летом и осенью',
      descEn: 'Read in winter, spring, summer and autumn',
      icon: Icons.park_rounded,
      current: seasons.length >= 4 ? 1 : 0,
    ),

    // ---------------- Genres and formats ----------------
    _make(
      id: 'extra_genres_5',
      category: AchievementCategory.special,
      tier: AchievementTier.bronze,
      titleRu: 'Дегустатор',
      titleEn: 'Taster',
      descRu: 'Прочитайте тайтлы 5 разных жанров',
      descEn: 'Read titles from 5 different genres',
      icon: Icons.restaurant_menu_rounded,
      max: 5,
      current: genres.length,
    ),
    _make(
      id: 'extra_genres_15',
      category: AchievementCategory.special,
      tier: AchievementTier.gold,
      titleRu: 'Всеядный',
      titleEn: 'Omnivore',
      descRu: 'Прочитайте тайтлы 15 разных жанров',
      descEn: 'Read titles from 15 different genres',
      icon: Icons.dinner_dining_rounded,
      max: 15,
      current: genres.length,
    ),
    _make(
      id: 'extra_romance_20',
      category: AchievementCategory.special,
      tier: AchievementTier.silver,
      titleRu: 'Романтик',
      titleEn: 'Romantic',
      descRu: 'Прочитайте 20 глав романтики',
      descEn: 'Read 20 romance chapters',
      icon: Icons.favorite_rounded,
      max: 20,
      current: genreChapters(['роман']),
    ),
    _make(
      id: 'extra_action_20',
      category: AchievementCategory.special,
      tier: AchievementTier.silver,
      titleRu: 'Кровь и сталь',
      titleEn: 'Blood and Steel',
      descRu: 'Прочитайте 20 глав экшена',
      descEn: 'Read 20 action chapters',
      icon: Icons.gavel_rounded,
      max: 20,
      current: genreChapters(['боевик', 'экшн', 'action']),
    ),
    _make(
      id: 'extra_mystery_20',
      category: AchievementCategory.special,
      tier: AchievementTier.silver,
      titleRu: 'Детектив',
      titleEn: 'Detective',
      descRu: 'Прочитайте 20 глав детектива',
      descEn: 'Read 20 mystery chapters',
      icon: Icons.search_rounded,
      max: 20,
      current: genreChapters(['детектив', 'mystery']),
    ),
    _make(
      id: 'extra_slice_20',
      category: AchievementCategory.special,
      tier: AchievementTier.bronze,
      titleRu: 'Уютный вечер',
      titleEn: 'Cozy Evening',
      descRu: 'Прочитайте 20 глав повседневности',
      descEn: 'Read 20 slice-of-life chapters',
      icon: Icons.local_cafe_rounded,
      max: 20,
      current: genreChapters(['повседнев', 'slice']),
    ),
    _make(
      id: 'extra_horror_night',
      category: AchievementCategory.special,
      tier: AchievementTier.silver,
      titleRu: 'Ужас в темноте',
      titleEn: 'Horror in the Dark',
      descRu: 'Прочитайте хоррор после 23:00',
      descEn: 'Read horror after 23:00',
      icon: Icons.visibility_off_rounded,
      current: genreChapters(['ужас', 'хоррор', 'horror']) > 0 && snap.nightReads.toInt() > 0 ? 1 : 0,
    ),
    _make(
      id: 'extra_manhwa',
      category: AchievementCategory.special,
      tier: AchievementTier.gold,
      titleRu: 'Манхва-пилигрим',
      titleEn: 'Manhwa Pilgrim',
      descRu: 'Завершите манхву',
      descEn: 'Finish a manhwa',
      icon: Icons.auto_stories_rounded,
      current: completedOfType(['манхва', 'manhwa']) ? 1 : 0,
    ),
    _make(
      id: 'extra_manhua',
      category: AchievementCategory.special,
      tier: AchievementTier.gold,
      titleRu: 'Маньхуа-странник',
      titleEn: 'Manhua Wanderer',
      descRu: 'Завершите маньхуа',
      descEn: 'Finish a manhua',
      icon: Icons.travel_explore_rounded,
      current: completedOfType(['маньхуа', 'manhua']) ? 1 : 0,
    ),
    _make(
      id: 'extra_one_shot',
      category: AchievementCategory.special,
      tier: AchievementTier.bronze,
      titleRu: 'Ваншот',
      titleEn: 'One Shot',
      descRu: 'Прочитайте ваншот',
      descEn: 'Read a one-shot',
      icon: Icons.crop_portrait_rounded,
      current: manga.any((item) => item.mangaType.toLowerCase().contains('ваншот') || item.mangaType.toLowerCase().contains('one')) ? 1 : 0,
    ),
    _make(
      id: 'extra_retro',
      category: AchievementCategory.special,
      tier: AchievementTier.silver,
      titleRu: 'Ретро-клуб',
      titleEn: 'Retro Club',
      descRu: 'Прочитайте тайтл, вышедший до 2000 года',
      descEn: 'Read a title released before 2000',
      icon: Icons.history_rounded,
      current: hasRetroTitle() ? 1 : 0,
    ),
    _make(
      id: 'extra_fresh',
      category: AchievementCategory.special,
      tier: AchievementTier.bronze,
      titleRu: 'Свежий номер',
      titleEn: 'Fresh Off the Press',
      descRu: 'Прочитайте тайтл текущего года',
      descEn: 'Read a title released this year',
      icon: Icons.new_releases_rounded,
      current: hasFreshTitle() ? 1 : 0,
    ),

    // ---------------- Title-bound ----------------
    titleCard(
      id: 'title_horimiya',
      titleRu: 'Соседи по парте',
      titleEn: 'Desk Neighbours',
      needles: ['horimiya', 'хоримия'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.favorite_rounded,
      descRu: 'Прочитайте 10 глав «Хоримии»',
      descEn: 'Read 10 chapters of Horimiya',
    ),
    titleCard(
      id: 'title_hori_san',
      titleRu: 'Омаке',
      titleEn: 'Omake',
      needles: ['hori-san', 'хори-сан'],
      chapters: 5,
      tier: AchievementTier.silver,
      icon: Icons.auto_stories_rounded,
      descRu: 'Прочитайте 5 глав «Хори-сан и Миямура-кун»',
      descEn: 'Read 5 chapters of Hori-san to Miyamura-kun',
    ),
    titleCard(
      id: 'title_one_piece',
      titleRu: 'Король пиратов',
      titleEn: 'Pirate King',
      needles: ['one-piece', 'one piece', 'ван пис'],
      chapters: 100,
      tier: AchievementTier.platinum,
      icon: Icons.sailing_rounded,
      descRu: 'Прочитайте 100 глав One Piece',
      descEn: 'Read 100 chapters of One Piece',
    ),
    titleCard(
      id: 'title_berserk',
      titleRu: 'Чёрный мечник',
      titleEn: 'Black Swordsman',
      needles: ['berserk', 'берсерк'],
      chapters: 10,
      tier: AchievementTier.gold,
      icon: Icons.gavel_rounded,
      descRu: 'Прочитайте 10 глав Berserk ночью',
      descEn: 'Read 10 Berserk chapters at night',
      secret: true,
      hintRu: 'Меч, который не прощает.',
      hintEn: 'A sword that does not forgive.',
      extra: () => snap.nightReads.toInt(),
    ),
    titleCard(
      id: 'title_vagabond',
      titleRu: 'Путь меча',
      titleEn: 'Way of the Sword',
      needles: ['vagabond', 'бродяга'],
      chapters: 20,
      tier: AchievementTier.gold,
      icon: Icons.sports_martial_arts_rounded,
      descRu: 'Прочитайте 20 глав Vagabond',
      descEn: 'Read 20 chapters of Vagabond',
    ),
    titleCard(
      id: 'title_punpun',
      titleRu: 'Доброй ночи',
      titleEn: 'Good Night',
      needles: ['punpun', 'пунпун'],
      chapters: 5,
      tier: AchievementTier.gold,
      icon: Icons.nightlight_round,
      descRu: 'Прочитайте 5 глав Oyasumi Punpun после полуночи',
      descEn: 'Read 5 Punpun chapters after midnight',
      secret: true,
      hintRu: 'Некоторые истории лучше читать, когда все спят.',
      hintEn: 'Some stories are better read while everyone sleeps.',
      extra: () => snap.nightReads.toInt(),
    ),
    titleCard(
      id: 'title_chainsaw',
      titleRu: 'Рёв бензопилы',
      titleEn: 'Chainsaw Roar',
      needles: ['chainsaw', 'бензопил'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.content_cut_rounded,
      descRu: 'Прочитайте 10 глав Chainsaw Man',
      descEn: 'Read 10 chapters of Chainsaw Man',
    ),
    titleCard(
      id: 'title_jujutsu',
      titleRu: 'Проклятая энергия',
      titleEn: 'Cursed Energy',
      needles: ['jujutsu', 'магическая битва', 'дзюдзюцу'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.bolt_rounded,
      descRu: 'Прочитайте 10 глав Jujutsu Kaisen',
      descEn: 'Read 10 chapters of Jujutsu Kaisen',
    ),
    titleCard(
      id: 'title_aot',
      titleRu: 'За стеной',
      titleEn: 'Beyond the Wall',
      needles: ['attack-on-titan', 'attack on titan', 'shingeki', 'атака титанов'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.shield_rounded,
      descRu: 'Прочитайте 10 глав Attack on Titan',
      descEn: 'Read 10 chapters of Attack on Titan',
    ),
    titleCard(
      id: 'title_death_note',
      titleRu: 'Тетрадь',
      titleEn: 'The Notebook',
      needles: ['death-note', 'death note', 'тетрадь смерти'],
      chapters: 1,
      tier: AchievementTier.gold,
      icon: Icons.menu_book_rounded,
      descRu: 'Завершите Death Note',
      descEn: 'Finish Death Note',
      completeOnly: true,
    ),
    titleCard(
      id: 'title_fma',
      titleRu: 'Эквивалентный обмен',
      titleEn: 'Equivalent Exchange',
      needles: ['fullmetal', 'стальной алхимик'],
      chapters: 1,
      tier: AchievementTier.gold,
      icon: Icons.change_circle_rounded,
      descRu: 'Завершите Fullmetal Alchemist',
      descEn: 'Finish Fullmetal Alchemist',
      completeOnly: true,
    ),
    titleCard(
      id: 'title_tokyo_ghoul',
      titleRu: 'Получеловек',
      titleEn: 'Half-Human',
      needles: ['tokyo-ghoul', 'tokyo ghoul', 'токийский гуль'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.no_food_rounded,
      descRu: 'Прочитайте 10 глав Tokyo Ghoul',
      descEn: 'Read 10 chapters of Tokyo Ghoul',
    ),
    titleCard(
      id: 'title_vinland',
      titleRu: 'Без войны',
      titleEn: 'No War',
      needles: ['vinland', 'винланд'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.landscape_rounded,
      descRu: 'Прочитайте 10 глав Vinland Saga',
      descEn: 'Read 10 chapters of Vinland Saga',
    ),
    titleCard(
      id: 'title_solo_leveling',
      titleRu: 'Пробуждение',
      titleEn: 'Awakening',
      needles: ['solo-leveling', 'solo leveling', 'поднятие уровня'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.upgrade_rounded,
      descRu: 'Прочитайте 10 глав Solo Leveling',
      descEn: 'Read 10 chapters of Solo Leveling',
    ),
    titleCard(
      id: 'title_tower_of_god',
      titleRu: 'На вершину',
      titleEn: 'To the Top',
      needles: ['tower-of-god', 'tower of god', 'башня бога'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.stairs_rounded,
      descRu: 'Прочитайте 10 глав Tower of God',
      descEn: 'Read 10 chapters of Tower of God',
    ),
    titleCard(
      id: 'title_orv',
      titleRu: 'Всеведущий читатель',
      titleEn: 'Omniscient Reader',
      needles: ['omniscient', 'всеведущ'],
      chapters: 5,
      tier: AchievementTier.silver,
      icon: Icons.auto_stories_rounded,
      descRu: 'Прочитайте 5 глав Omniscient Reader',
      descEn: 'Read 5 chapters of Omniscient Reader',
    ),
    titleCard(
      id: 'title_frieren',
      titleRu: 'Провожающая',
      titleEn: 'The Journey',
      needles: ['frieren', 'фрирен', 'провожающая'],
      chapters: 5,
      tier: AchievementTier.silver,
      icon: Icons.forest_rounded,
      descRu: 'Прочитайте 5 глав Frieren',
      descEn: 'Read 5 chapters of Frieren',
    ),
    titleCard(
      id: 'title_kaguya',
      titleRu: 'Любовная война',
      titleEn: 'Love War',
      needles: ['kaguya', 'кагуя'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.favorite_border_rounded,
      descRu: 'Прочитайте 10 глав Kaguya-sama',
      descEn: 'Read 10 chapters of Kaguya-sama',
    ),
    titleCard(
      id: 'title_oshi_no_ko',
      titleRu: 'Звезда',
      titleEn: 'The Star',
      needles: ['oshi-no-ko', 'oshi no ko', 'звезда'],
      chapters: 5,
      tier: AchievementTier.silver,
      icon: Icons.star_rounded,
      descRu: 'Прочитайте 5 глав Oshi no Ko',
      descEn: 'Read 5 chapters of Oshi no Ko',
    ),
    titleCard(
      id: 'title_blue_lock',
      titleRu: 'Эго',
      titleEn: 'Ego',
      needles: ['blue-lock', 'blue lock', 'синяя тюрьма'],
      chapters: 10,
      tier: AchievementTier.silver,
      icon: Icons.sports_soccer_rounded,
      descRu: 'Прочитайте 10 глав Blue Lock',
      descEn: 'Read 10 chapters of Blue Lock',
    ),

    // ---------------- Library ----------------
    _make(
      id: 'extra_all_categories',
      category: AchievementCategory.library,
      tier: AchievementTier.silver,
      titleRu: 'Все категории',
      titleEn: 'Every Shelf',
      descRu: 'Используйте все 6 статусов библиотеки',
      descEn: 'Use all 6 library statuses',
      icon: Icons.category_rounded,
      max: 6,
      current: {for (final entry in library) entry.listType}.length,
    ),
    _make(
      id: 'extra_favorites_5',
      category: AchievementCategory.library,
      tier: AchievementTier.silver,
      titleRu: 'Избранное',
      titleEn: 'Favourites',
      descRu: 'Добавьте 5 тайтлов в избранное',
      descEn: 'Add 5 titles to favourites',
      icon: Icons.favorite_rounded,
      max: 5,
      current: d.favorites,
    ),
    _make(
      id: 'extra_planned_10',
      category: AchievementCategory.library,
      tier: AchievementTier.bronze,
      titleRu: 'Планы',
      titleEn: 'Plan Ahead',
      descRu: 'Добавьте 10 тайтлов в «Планирую»',
      descEn: 'Add 10 titles to Plan to Read',
      icon: Icons.bookmark_add_outlined,
      max: 10,
      current: d.planned,
    ),
    _make(
      id: 'extra_brave',
      category: AchievementCategory.library,
      tier: AchievementTier.silver,
      titleRu: 'Смельчак',
      titleEn: 'Brave One',
      descRu: 'Добавьте тайтл с рейтингом ниже 6',
      descEn: 'Add a title rated below 6',
      icon: Icons.sports_kabaddi_rounded,
      current: hasLowRated ? 1 : 0,
    ),
    _make(
      id: 'extra_masterpiece',
      category: AchievementCategory.library,
      tier: AchievementTier.gold,
      titleRu: 'Шедевр',
      titleEn: 'Masterpiece',
      descRu: 'Завершите тайтл с рейтингом 9+',
      descEn: 'Finish a title rated 9+',
      icon: Icons.workspace_premium_rounded,
      current: hasMasterpiece ? 1 : 0,
    ),
    _make(
      id: 'extra_return_dropped',
      category: AchievementCategory.library,
      tier: AchievementTier.silver,
      titleRu: 'Возвращение блудного',
      titleEn: 'The Prodigal Reader',
      descRu: 'Прочитайте главу тайтла из «Брошено»',
      descEn: 'Read a chapter of a dropped title',
      icon: Icons.replay_circle_filled_rounded,
      current: library.any(
        (entry) => entry.listType == ListType.dropped && entry.readChapters > 0,
      )
          ? 1
          : 0,
    ),
    _make(
      id: 'extra_genre_specialist',
      category: AchievementCategory.library,
      tier: AchievementTier.gold,
      titleRu: 'Жанровый специалист',
      titleEn: 'Genre Specialist',
      descRu: 'Завершите 5 тайтлов одного жанра',
      descEn: 'Finish 5 titles from one genre',
      icon: Icons.workspaces_rounded,
      max: 5,
      current: completedInSameGenre(),
    ),

    // ---------------- Downloads and offline ----------------
    _make(
      id: 'extra_archive_100',
      category: AchievementCategory.downloads,
      tier: AchievementTier.silver,
      titleRu: 'Архив',
      titleEn: 'The Archive',
      descRu: 'Скачайте 100 глав',
      descEn: 'Download 100 chapters',
      icon: Icons.folder_zip_rounded,
      max: 100,
      current: d.downloads,
    ),
    _make(
      id: 'extra_gigabyte',
      category: AchievementCategory.downloads,
      tier: AchievementTier.gold,
      titleRu: 'Гигабайт',
      titleEn: 'One Gigabyte',
      descRu: 'Скачайте 1 ГБ глав',
      descEn: 'Download 1 GB of chapters',
      icon: Icons.sd_storage_rounded,
      max: 1073741824,
      current: d.downloadBytes,
    ),
    _make(
      id: 'extra_offline',
      category: AchievementCategory.downloads,
      tier: AchievementTier.silver,
      titleRu: 'Офлайн-выживание',
      titleEn: 'Offline Survivor',
      descRu: 'Прочитайте скачанную главу без сети',
      descEn: 'Read a downloaded chapter offline',
      icon: Icons.wifi_off_rounded,
      current: offlineRead ? 1 : 0,
    ),
    _make(
      id: 'extra_night_download',
      category: AchievementCategory.downloads,
      tier: AchievementTier.silver,
      titleRu: 'Ночной загрузчик',
      titleEn: 'Night Downloader',
      descRu: 'Скачайте главу в ночном окне',
      descEn: 'Download a chapter during the night window',
      icon: Icons.bedtime_rounded,
      current: nightDownload ? 1 : 0,
    ),
    _make(
      id: 'extra_scheduler',
      category: AchievementCategory.downloads,
      tier: AchievementTier.bronze,
      titleRu: 'Планировщик',
      titleEn: 'Scheduler',
      descRu: 'Настройте расписание загрузок',
      descEn: 'Set up a download schedule',
      icon: Icons.schedule_rounded,
      current: usedSchedule ? 1 : 0,
    ),
    _make(
      id: 'extra_storage_economist',
      category: AchievementCategory.downloads,
      tier: AchievementTier.bronze,
      titleRu: 'Экономист',
      titleEn: 'Space Saver',
      descRu: 'Установите лимит хранилища',
      descEn: 'Set a storage limit',
      icon: Icons.storage_rounded,
      current: usedStorageLimit ? 1 : 0,
    ),
    _make(
      id: 'extra_wifi_only',
      category: AchievementCategory.downloads,
      tier: AchievementTier.bronze,
      titleRu: 'Только Wi-Fi',
      titleEn: 'Wi-Fi Only',
      descRu: 'Включите загрузку только по Wi-Fi',
      descEn: 'Enable Wi-Fi only downloads',
      icon: Icons.wifi_rounded,
      current: usedWifiOnly ? 1 : 0,
    ),
    _make(
      id: 'extra_prefetch',
      category: AchievementCategory.downloads,
      tier: AchievementTier.bronze,
      titleRu: 'Заранее готов',
      titleEn: 'Always Ready',
      descRu: 'Включите подготовку соседних глав',
      descEn: 'Enable neighbour chapter prefetch',
      icon: Icons.fast_forward_rounded,
      current: prefetchOn ? 1 : 0,
    ),

    // ---------------- Comments ----------------
    _make(
      id: 'extra_first_vote',
      category: AchievementCategory.special,
      tier: AchievementTier.bronze,
      titleRu: 'Первый голос',
      titleEn: 'First Vote',
      descRu: 'Проголосуйте за комментарий',
      descEn: 'Vote on a comment',
      icon: Icons.thumb_up_alt_outlined,
      current: votesCast ? 1 : 0,
    ),
    _make(
      id: 'extra_first_comment',
      category: AchievementCategory.special,
      tier: AchievementTier.bronze,
      titleRu: 'Первый комментарий',
      titleEn: 'First Comment',
      descRu: 'Отправьте комментарий',
      descEn: 'Post a comment',
      icon: Icons.chat_bubble_outline_rounded,
      current: commentsPosted ? 1 : 0,
    ),
    _make(
      id: 'extra_ten_comments',
      category: AchievementCategory.special,
      tier: AchievementTier.silver,
      titleRu: 'Десятка',
      titleEn: 'Ten Comments',
      descRu: 'Отправьте 10 комментариев',
      descEn: 'Post 10 comments',
      icon: Icons.forum_rounded,
      max: 10,
      current: events['comments_posted'],
    ),
    _make(
      id: 'extra_replier',
      category: AchievementCategory.special,
      tier: AchievementTier.silver,
      titleRu: 'Ответчик',
      titleEn: 'The Replier',
      descRu: 'Ответьте на чужой комментарий',
      descEn: 'Reply to someone else',
      icon: Icons.reply_rounded,
      current: replyPosted ? 1 : 0,
    ),
    _make(
      id: 'extra_tribune',
      category: AchievementCategory.special,
      tier: AchievementTier.gold,
      titleRu: 'Трибуна',
      titleEn: 'The Tribune',
      descRu: 'Прокомментируйте 5 разных тайтлов',
      descEn: 'Comment on 5 different titles',
      icon: Icons.campaign_rounded,
      max: 5,
      current: events.setOf('comment_titles').length,
    ),
    _make(
      id: 'extra_silent_reader',
      category: AchievementCategory.secrets,
      tier: AchievementTier.gold,
      titleRu: 'Молчаливый наблюдатель',
      titleEn: 'Silent Watcher',
      descRu: 'Прочитайте 100 глав, не проголосовав ни разу',
      descEn: 'Read 100 chapters without voting once',
      icon: Icons.visibility_rounded,
      secret: true,
      hintRu: 'Иногда лучше просто читать.',
      hintEn: 'Sometimes it is better to just read.',
      current: silentReader ? 1 : 0,
    ),

    // ---------------- Secrets and interface ----------------
    _make(
      id: 'extra_night_manual',
      category: AchievementCategory.secrets,
      tier: AchievementTier.gold,
      titleRu: 'Полночный страж',
      titleEn: 'Midnight Guardian',
      descRu: 'Откройте главу в 03:33',
      descEn: 'Open a chapter at 03:33',
      icon: Icons.nights_stay_rounded,
      secret: true,
      hintRu: 'Ровно в 03:33. Ни минутой позже.',
      hintEn: 'Exactly at 03:33. Not a minute later.',
      current: snap.readAt333.toInt() > 0 ? 1 : 0,
    ),
    _make(
      id: 'extra_friday_13',
      category: AchievementCategory.secrets,
      tier: AchievementTier.gold,
      titleRu: 'Пятница 13-го',
      titleEn: 'Friday the 13th',
      descRu: 'Читайте в пятницу 13-го',
      descEn: 'Read on Friday the 13th',
      icon: Icons.calendar_today_rounded,
      secret: true,
      hintRu: 'Не самый удачный день для прогулок.',
      hintEn: 'Not the best day for a walk.',
      current: snap.friday13Reads.toInt() > 0 ? 1 : 0,
    ),
    _make(
      id: 'extra_halloween',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Хэллоуин',
      titleEn: 'Halloween',
      descRu: 'Читайте 31 октября',
      descEn: 'Read on October 31',
      icon: Icons.masks_rounded,
      secret: true,
      hintRu: 'Сладости или гадости?',
      hintEn: 'Trick or treat?',
      current: snap.halloweenReads.toInt() > 0 ? 1 : 0,
    ),
    _make(
      id: 'extra_new_year',
      category: AchievementCategory.secrets,
      tier: AchievementTier.gold,
      titleRu: 'Новогодняя ночь',
      titleEn: 'New Year Night',
      descRu: 'Читайте 1 января с 00:00 до 03:00',
      descEn: 'Read on January 1 between 00:00 and 03:00',
      icon: Icons.celebration_rounded,
      secret: true,
      hintRu: 'Первый день года, первые три часа.',
      hintEn: 'The first day of the year, the first three hours.',
      current: snap.newYearReads.toInt() > 0 ? 1 : 0,
    ),
    _make(
      id: 'extra_sunday_lonely',
      category: AchievementCategory.secrets,
      tier: AchievementTier.gold,
      titleRu: 'Одиночество',
      titleEn: 'Loneliness',
      descRu: 'Читайте в воскресенье в 04:00',
      descEn: 'Read on Sunday at 04:00',
      icon: Icons.person_off_rounded,
      secret: true,
      hintRu: 'Когда город ещё спит.',
      hintEn: 'When the city is still asleep.',
      current: snap.sundayNightReads.toInt() > 0 ? 1 : 0,
    ),
    _make(
      id: 'extra_spoiler',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Спойлер',
      titleEn: 'Spoiler',
      descRu: 'Откройте последнюю главу тайтла до первой',
      descEn: 'Open the last chapter before the first',
      icon: Icons.skip_next_rounded,
      secret: true,
      hintRu: 'Некоторые начинают с конца.',
      hintEn: 'Some people start from the end.',
      current: events['spoiler_reads'] >= 1 ? 1 : 0,
    ),
    _make(
      id: 'extra_savior',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Синдром спасателя',
      titleEn: 'Saviour Syndrome',
      descRu: 'Добавьте 50 тайтлов в «Планирую» и не прочитайте ни одной главы',
      descEn: 'Add 50 titles to Plan to Read and read nothing',
      icon: Icons.inventory_2_rounded,
      secret: true,
      hintRu: 'Список желаний растёт быстрее, чем время.',
      hintEn: 'The wish list grows faster than time.',
      current: unreadPlanned ? 1 : 0,
    ),
    _make(
      id: 'extra_graveyard',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Кладбище надежд',
      titleEn: 'Graveyard of Hopes',
      descRu: 'Бросьте 10 тайтлов',
      descEn: 'Drop 10 titles',
      icon: Icons.landscape_rounded,
      secret: true,
      hintRu: 'Не всё выдерживает проверку временем.',
      hintEn: 'Not everything stands the test of time.',
      max: 10,
      current: d.dropped,
    ),
    _make(
      id: 'extra_404',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: '404-путешественник',
      titleEn: '404 Traveller',
      descRu: 'Откройте удалённый тайтл и увидьте экран ошибки',
      descEn: 'Open a dead title and see the error screen',
      icon: Icons.travel_explore_rounded,
      secret: true,
      hintRu: 'Некоторые двери ведут в пустоту.',
      hintEn: 'Some doors lead nowhere.',
      current: hasDeadLink ? 1 : 0,
    ),
    _make(
      id: 'extra_bug_reporter',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Багрепортер',
      titleEn: 'Bug Reporter',
      descRu: 'Скопируйте лог ошибки',
      descEn: 'Copy an error log',
      icon: Icons.bug_report_rounded,
      secret: true,
      hintRu: 'Иногда лучший отзыв — это лог.',
      hintEn: 'Sometimes the best feedback is a log.',
      current: hasCopiedLog ? 1 : 0,
    ),
    _make(
      id: 'extra_contemplator',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Созерцатель',
      titleEn: 'Contemplator',
      descRu: 'Проведите минуту на экране достижений',
      descEn: 'Spend a minute on the achievements screen',
      icon: Icons.self_improvement_rounded,
      secret: true,
      hintRu: 'Остановитесь и посмотрите на полку.',
      hintEn: 'Stop and look at the shelf.',
      current: minutesOnAchievements ? 1 : 0,
    ),
    _make(
      id: 'extra_logo_fan',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Логотип-фанат',
      titleEn: 'Logo Fan',
      descRu: 'Нажмите на логотип 10 раз',
      descEn: 'Tap the logo 10 times',
      icon: Icons.touch_app_rounded,
      secret: true,
      hintRu: 'Логотип тоже хочет внимания.',
      hintEn: 'The logo wants attention too.',
      max: 10,
      current: events['logo_taps'],
    ),
    _make(
      id: 'extra_start_path',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Начало пути',
      titleEn: 'The Beginning',
      descRu: 'Откройте достижения до первой главы',
      descEn: 'Open achievements before the first chapter',
      icon: Icons.flag_rounded,
      secret: true,
      hintRu: 'Куда идти, если ещё не начал?',
      hintEn: 'Where to go before you start?',
      current: events['start_of_path'] >= 1 ? 1 : 0,
    ),
    _make(
      id: 'extra_404_pages',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Страница не найдена',
      titleEn: 'Page Not Found',
      descRu: 'Прочитайте 404 страницы',
      descEn: 'Read 404 pages',
      icon: Icons.find_in_page_rounded,
      secret: true,
      hintRu: 'Четыре-ноль-четыре.',
      hintEn: 'Four-zero-four.',
      max: 404,
      current: snap.totalPagesRead.toInt(),
    ),
    _make(
      id: 'extra_666',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Дьявольская страница',
      titleEn: 'The Devil\'s Page',
      descRu: 'Прочитайте 666 страниц',
      descEn: 'Read 666 pages',
      icon: Icons.local_fire_department_rounded,
      secret: true,
      hintRu: 'Число, которое лучше не произносить.',
      hintEn: 'A number better left unspoken.',
      max: 666,
      current: snap.totalPagesRead.toInt(),
    ),
    _make(
      id: 'extra_1337',
      category: AchievementCategory.secrets,
      tier: AchievementTier.gold,
      titleRu: 'Элита',
      titleEn: 'Elite',
      descRu: 'Прочитайте 1337 страниц',
      descEn: 'Read 1337 pages',
      icon: Icons.terminal_rounded,
      secret: true,
      hintRu: 'Одна тысяча триста тридцать семь.',
      hintEn: 'One thousand three hundred thirty-seven.',
      max: 1337,
      current: snap.totalPagesRead.toInt(),
    ),
    _make(
      id: 'extra_presets',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Конфигуратор',
      titleEn: 'Configurator',
      descRu: 'Примените все пресеты читалки',
      descEn: 'Apply every reader preset',
      icon: Icons.tune_rounded,
      secret: true,
      hintRu: 'Идеальные настройки существуют.',
      hintEn: 'The perfect settings exist.',
      max: 3,
      current: events.setOf('reader_presets').length,
    ),
    _make(
      id: 'extra_autoscroll',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Бесконечная лента',
      titleEn: 'Endless Feed',
      descRu: 'Прочитайте 10 страниц с автопрокруткой',
      descEn: 'Read 10 pages with auto-scroll',
      icon: Icons.slow_motion_video_rounded,
      secret: true,
      hintRu: 'Отпустите палец и просто читайте.',
      hintEn: 'Let go and just read.',
      max: 10,
      current: events['autoscroll_pages'],
    ),
    _make(
      id: 'extra_bookmarks',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Закладкодержатель',
      titleEn: 'Bookmark Keeper',
      descRu: 'Поставьте 10 закладок',
      descEn: 'Place 10 bookmarks',
      icon: Icons.bookmarks_rounded,
      secret: true,
      hintRu: 'Иногда хочется вернуться.',
      hintEn: 'Sometimes you want to return.',
      max: 10,
      current: events['bookmarks_added'],
    ),
    _make(
      id: 'extra_jump_end',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Сразу к финалу',
      titleEn: 'Straight to the End',
      descRu: 'Прыгните на последнюю страницу через ползунок',
      descEn: 'Jump to the last page with the slider',
      icon: Icons.skip_next_rounded,
      secret: true,
      hintRu: 'Кто читает предисловия?',
      hintEn: 'Who reads forewords?',
      current: jumpedToEnd ? 1 : 0,
    ),
    _make(
      id: 'extra_three_modes',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Три ипостаси',
      titleEn: 'Three Forms',
      descRu: 'Прочитайте в RTL, LTR и вебтуне',
      descEn: 'Read in RTL, LTR and webtoon mode',
      icon: Icons.swap_horiz_rounded,
      secret: true,
      hintRu: 'Одна история — три способа.',
      hintEn: 'One story, three ways.',
      current: hasRtl && hasLtr && hasVertical ? 1 : 0,
    ),
    _make(
      id: 'extra_double_modes',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Амбидекстр',
      titleEn: 'Ambidextrous',
      descRu: 'Прочитайте RTL и LTR в один день',
      descEn: 'Read RTL and LTR on the same day',
      icon: Icons.compare_arrows_rounded,
      secret: true,
      hintRu: 'Обе стороны — это тоже сторона.',
      hintEn: 'Both sides count.',
      current: bothModesSameDay ? 1 : 0,
    ),
    _make(
      id: 'extra_polyglot',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Полиглот',
      titleEn: 'Polyglot',
      descRu: 'Смените язык приложения и прочитайте главу',
      descEn: 'Switch the app language and read a chapter',
      icon: Icons.translate_rounded,
      secret: true,
      hintRu: 'Язык — тоже настройка.',
      hintEn: 'Language is a setting too.',
      current: languageSwitched && d.totalChapters > 0 ? 1 : 0,
    ),
    _make(
      id: 'extra_start_path_missing',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Ночной библиотекарь',
      titleEn: 'Night Librarian',
      descRu: 'Добавьте 5 тайтлов после полуночи',
      descEn: 'Add 5 titles after midnight',
      icon: Icons.library_add_rounded,
      secret: true,
      hintRu: 'Полка пополняется, пока все спят.',
      hintEn: 'The shelf grows while everyone sleeps.',
      max: 5,
      current: library
          .where((entry) {
            final added = DateTime.tryParse(entry.addedAt);
            return added != null && added.hour < 6;
          })
          .length,
    ),
    _make(
      id: 'extra_chameleon',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Хамелеон',
      titleEn: 'Chameleon',
      descRu: 'Смените тему 5 раз',
      descEn: 'Switch the theme 5 times',
      icon: Icons.palette_rounded,
      secret: true,
      hintRu: 'Тёмное или светлое?',
      hintEn: 'Dark or light?',
      max: 5,
      current: events['theme_switches'],
    ),
    _make(
      id: 'extra_amoled_secret',
      category: AchievementCategory.secrets,
      tier: AchievementTier.bronze,
      titleRu: 'Абсолютный чёрный',
      titleEn: 'Absolute Black',
      descRu: 'Включите AMOLED-тему',
      descEn: 'Enable the AMOLED theme',
      icon: Icons.contrast_rounded,
      secret: true,
      hintRu: 'Чёрный может быть ещё чернее.',
      hintEn: 'Black can be blacker.',
      current: d.amoled ? 1 : 0,
    ),
    _make(
      id: 'extra_explorer_50',
      category: AchievementCategory.secrets,
      tier: AchievementTier.silver,
      titleRu: 'Исследователь',
      titleEn: 'Explorer',
      descRu: 'Откройте 50 разных тайтлов',
      descEn: 'Open 50 different titles',
      icon: Icons.explore_rounded,
      secret: true,
      hintRu: 'Каждый тайтл — новая дверь.',
      hintEn: 'Every title is a new door.',
      max: 50,
      current: math.max(d.libraryCount, snap.distinctTitles.toInt()),
    ),
    _make(
      id: 'extra_cartographer',
      category: AchievementCategory.secrets,
      tier: AchievementTier.gold,
      titleRu: 'Картограф',
      titleEn: 'Cartographer',
      descRu: 'Откройте 100 разных тайтлов',
      descEn: 'Open 100 different titles',
      icon: Icons.map_rounded,
      secret: true,
      hintRu: 'Составьте карту прочитанного.',
      hintEn: 'Map everything you have read.',
      max: 100,
      current: math.max(d.libraryCount, snap.distinctTitles.toInt()),
    ),
    _make(
      id: 'extra_collector',
      category: AchievementCategory.secrets,
      tier: AchievementTier.legendary,
      titleRu: 'Коллекционер',
      titleEn: 'The Collector',
      descRu: 'Соберите 90 достижений',
      descEn: 'Collect 90 achievements',
      icon: Icons.military_tech_rounded,
      secret: true,
      hintRu: 'Полка почти заполнена.',
      hintEn: 'The shelf is almost full.',
      max: 90,
      current: 0, // Filled after the whole list is built.
    ),
  ];

  return list;
}

Achievement _make({
  required String id,
  required AchievementCategory category,
  required AchievementTier tier,
  required String titleRu,
  required String titleEn,
  required String descRu,
  required String descEn,
  required IconData icon,
  int max = 1,
  int current = 0,
  bool secret = false,
  String hintRu = '',
  String hintEn = '',
  Color? color,
  String? titleSlug,
  String? titleCoverUrl,
}) {
  final clamped = max > 0 ? current.clamp(0, max) : (current > 0 ? 1 : 0);
  return Achievement(
    id: id,
    category: category,
    titleRu: titleRu,
    titleEn: titleEn,
    descRu: descRu,
    descEn: descEn,
    icon: icon,
    iconColor: color ?? _tierColor(tier),
    tier: tier,
    xp: _tierXp(tier),
    maxProgress: max,
    currentProgress: clamped,
    isUnlocked: current >= max,
    isSecret: secret,
    hintRu: hintRu,
    hintEn: hintEn,
    titleSlug: titleSlug,
    titleCoverUrl: titleCoverUrl,
  );
}

Color _tierColor(AchievementTier tier) {
  switch (tier) {
    case AchievementTier.bronze:
      return const Color(0xFFCD7F32);
    case AchievementTier.silver:
      return const Color(0xFFC0C0C0);
    case AchievementTier.gold:
      return const Color(0xFFFFD700);
    case AchievementTier.platinum:
      return const Color(0xFFE5E4E2);
    case AchievementTier.legendary:
      return const Color(0xFFFF3D00);
  }
}

int _tierXp(AchievementTier tier) {
  switch (tier) {
    case AchievementTier.bronze:
      return 15;
    case AchievementTier.silver:
      return 30;
    case AchievementTier.gold:
      return 60;
    case AchievementTier.platinum:
      return 120;
    case AchievementTier.legendary:
      return 250;
  }
}
