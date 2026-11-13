import 'package:mangaloader/l10n/app_strings.dart';

/// Notification copy. Services have no BuildContext, so the bundle is built from
/// the locale flag they already receive.
class NotificationStrings extends AppStrings {
  const NotificationStrings(super.isRu);

  String get streakTitle =>
      isRu ? 'Твой огонёк может погаснуть!' : 'Your reading flame might go out!';

  String streakBodyWithDays(String days) => isRu
      ? 'Сохрани свой стрик в $days — прочитай главу прямо сейчас.'
      : 'Keep your $days-day streak burning — read a chapter now.';

  String get streakBodyNoDays => isRu
      ? 'Зажги свой ежедневный огонёк чтения! Прочитай 1 главу.'
      : 'Ignite your daily reading flame! Read 1 chapter.';

  String get newChapterTitle =>
      isRu ? 'Вышла новая глава!' : 'New Chapter Released!';

  String digestMore(String remaining) =>
      isRu ? 'и ещё $remaining' : 'and $remaining more';

  String digestTitle(String total) =>
      isRu ? 'Новые главы: $total' : 'New chapters: $total';

  String get downloadChannelName =>
      isRu ? 'Загрузки манги' : 'Manga downloads';

  String get downloadChannelDescription =>
      isRu ? 'Прогресс скачивания глав манги' : 'Progress of chapter downloads';

  String get downloadTitle => isRu ? 'Загрузка глав' : 'Downloading chapters';

  String downloadBody(String volume, String number, int progress, int max) => isRu
      ? 'Том $volume Гл $number · стр. $progress из $max'
      : 'Vol $volume Ch $number · page $progress of $max';
}