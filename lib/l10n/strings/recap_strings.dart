import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class RecapStrings extends AppStrings {
  const RecapStrings(super.isRu);

  factory RecapStrings.of(BuildContext context) =>
      RecapStrings(AppStrings.isRussian(context));

  String get shareText => isRu
      ? 'Мои итоги чтения в MangaLoader!'
      : 'My Reading Recap in MangaLoader!';
  String exportFailed(String error) =>
      isRu ? 'Ошибка экспорта карточки: $error' : 'Failed to export card: $error';
  String get title =>
      isRu ? 'Manga Recap / Итоги чтения' : 'Manga Reading Recap';
  String get loadFailed =>
      isRu ? 'Ошибка загрузки статистики' : 'Failed to load recap data';
  String get summaryFallback => isRu ? 'Итоги чтения' : 'Recap Summary';

  String get chaptersReadTitle =>
      isRu ? 'Глав прочитано' : 'Chapters Read';
  String get pagesReadTitle => isRu ? 'Страниц' : 'Pages Read';
  String hours(String value) => isRu ? '$value ч' : '$value h';
  String get hoursTitle => isRu ? 'Часов чтения' : 'Hours Read';
  String streakDays(String value) => isRu ? '$value дн.' : '$value days';
  String get maxStreakTitle => isRu ? 'Лучший стрик' : 'Max Streak';

  String get favoriteGenres => isRu ? 'Любимые жанры' : 'Favorite Genres';
  String get topReadManga => isRu ? 'Топ прочитанных тайтлов' : 'Top Read Manga';
  String chapters(String value) => isRu ? '$value гл.' : '$value ch.';
  String get shareCard =>
      isRu ? 'Поделиться карточкой итогов' : 'Share Recap Card';

  String get styleLabel => isRu ? 'Стиль' : 'Style';
  String get layoutLabel => isRu ? 'Вид' : 'Layout';
  String get styleNight => isRu ? 'Ночь' : 'Night';
  String get stylePaper => isRu ? 'Бумага' : 'Paper';
  String get styleNeon => isRu ? 'Неон' : 'Neon';
  String get styleKimono => isRu ? 'Кимоно' : 'Kimono';
  String get layoutPoster => isRu ? 'Постер' : 'Poster';
  String get layoutDossier => isRu ? 'Досье' : 'Dossier';
  String get layoutTimeline => isRu ? 'Таймлайн' : 'Timeline';
  String get activeDaysTitle => isRu ? 'Активных дней' : 'Active Days';
  String get timeOfDayTitle => isRu ? 'Когда я читаю' : 'When I Read';
  String get nightLabel => isRu ? 'Ночь' : 'Night';
  String get morningLabel => isRu ? 'Утро' : 'Morning';
  String get dayLabel => isRu ? 'День' : 'Day';
  String get eveningLabel => isRu ? 'Вечер' : 'Evening';
}