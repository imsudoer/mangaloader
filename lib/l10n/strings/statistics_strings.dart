import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class StatisticsStrings extends AppStrings {
  const StatisticsStrings(super.isRu);

  factory StatisticsStrings.of(BuildContext context) =>
      StatisticsStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'Статистика чтения' : 'Reading Statistics';
  String error(String error) => isRu ? 'Ошибка: $error' : 'Error: $error';

  String get overview => isRu ? 'Общие показатели' : 'Overview';
  String get chaptersRead => isRu ? 'Прочитано глав' : 'Chapters Read';
  String get pagesRead => isRu ? 'Страниц прочитано' : 'Pages Read';
  String get completedManga => isRu ? 'Завершено тайтлов' : 'Completed Manga';
  String get inProgress => isRu ? 'В процессе чтения' : 'In Progress';
  String get libraryTitles => isRu ? 'Всего в библиотеке' : 'Library Titles';
  String get downloadedChapters => isRu ? 'Скачано глав (CBZ)' : 'Downloaded (CBZ)';

  String get topGenres => isRu ? 'Любимые жанры' : 'Top Genres';
  String get noGenreData =>
      isRu ? 'Пока нет данных. Читайте больше глав!' : 'No data yet. Read more chapters!';

  String get activityTime =>
      isRu ? 'Время активности' : 'Reading Activity Time';
  String get night => isRu ? 'Ночь' : 'Night';
  String get morning => isRu ? 'Утро' : 'Morning';
  String get afternoon => isRu ? 'День' : 'Afternoon';
  String get evening => isRu ? 'Вечер' : 'Evening';

  String get streakHighlights => isRu ? 'Рекорды стрика' : 'Streak Highlights';
  String get currentStreak => isRu ? 'Текущий стрик' : 'Current Streak';
  String get bestRecord => isRu ? 'Лучший рекорд' : 'Best Record';
  String get activeDays => isRu ? 'Дней в приложении' : 'Active Days';

  String get readingTimeTracker =>
      isRu ? 'Время за чтением' : 'Reading Time Tracker';
  String get today => isRu ? 'Сегодня' : 'Today';
  String get lastSevenDays => isRu ? 'За 7 дней' : 'Last 7 Days';
  String get allTime => isRu ? 'Всего' : 'All Time';
  String get zeroMinutes => isRu ? '0м' : '0m';
  String durationHoursMinutes(String hours, String minutes) =>
      isRu ? '$hours ч $minutes м' : '${hours}h ${minutes}m';
  String durationMinutes(String minutes) =>
      isRu ? '$minutes м' : '${minutes}m';
}