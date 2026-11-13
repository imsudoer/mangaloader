import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class HomeStrings extends AppStrings {
  const HomeStrings(super.isRu);

  factory HomeStrings.of(BuildContext context) =>
      HomeStrings(AppStrings.isRussian(context));

  String get readingHistory => isRu ? 'История чтения' : 'Reading History';
  String get catalogAndSearch => isRu ? 'Каталог и поиск' : 'Catalog & Search';
  String get pasteLink => isRu ? 'Вставить ссылку' : 'Paste Link';
  String get invalidLink => isRu ? 'Неверная ссылка' : 'Invalid link';

  String get popular => isRu ? 'Популярное' : 'Popular';
  String get popularSubtitle => isRu ? 'Самые читаемые тайтлы' : 'Most read titles';
  String get latestUpdates => isRu ? 'Свежие обновления' : 'Latest Updates';
  String get latestUpdatesSubtitle =>
      isRu ? 'Недавно вышедшие главы' : 'Recently updated chapters';
  String get newReleases => isRu ? 'Новинки' : 'New Releases';
  String get newReleasesSubtitle =>
      isRu ? 'Недавно добавленные произведения' : 'Recently added manga';
  String get recommendations => isRu ? 'Рекомендации для вас' : 'Recommended For You';
  String get recommendationsSubtitle =>
      isRu ? 'На основе ваших вкусов' : 'Based on your reading preferences';

  String get topViews => isRu ? 'Топ по просмотрам' : 'Top Views';
  String get topViewsSubtitle =>
      isRu ? 'Самые просматриваемые' : 'Most viewed titles';
  String get periodDay => isRu ? 'День' : 'Day';
  String get periodWeek => isRu ? 'Неделя' : 'Week';
  String get periodMonth => isRu ? 'Месяц' : 'Month';

  String get seeAll => isRu ? 'Все' : 'See all';
  String get loadFailed => isRu
      ? 'Не удалось загрузить рекомендации'
      : 'Failed to load recommendations';
  String get retry => isRu ? 'Повторить' : 'Retry';

  String get newUpdate => isRu ? 'Новое обновление' : 'New Update';
  String get newUpdateSubtitle =>
      isRu ? 'Нажмите, чтобы открыть список изменений' : 'Tap to see changelog & install';
  String get update => isRu ? 'Обновить' : 'Update';
  String get dismiss => isRu ? 'Скрыть' : 'Dismiss';
}