import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class ErrorStrings extends AppStrings {
  const ErrorStrings(super.isRu);

  factory ErrorStrings.of(BuildContext context) =>
      ErrorStrings(AppStrings.isRussian(context));

  String get unavailableTitle => isRu ? 'Тайтл недоступен' : 'Title unavailable';
  String get unavailableBody => isRu
      ? 'MangaLib больше не отдаёт данные этой страницы. Тайтл могли удалить из каталога или скрыть — ссылка на сайте может открываться, но приложению он уже недоступен.'
      : 'MangaLib no longer serves this page. The title may have been removed from the catalog or hidden; the website link can still open, but the app cannot load it.';

  String get loadFailedTitle => isRu ? 'Не удалось загрузить' : 'Could not load';
  String get loadFailedBody => isRu
      ? 'Проверьте подключение к интернету и попробуйте ещё раз. Если ошибка повторяется, скопируйте лог и пришлите его в поддержку.'
      : 'Check your internet connection and try again. If it keeps failing, copy the log and send it to support.';

  String get chapterUnavailableTitle =>
      isRu ? 'Глава недоступна' : 'Chapter unavailable';
  String get chapterFailedTitle =>
      isRu ? 'Не удалось открыть главу' : 'Could not open chapter';

  String get copyLog => isRu ? 'Скопировать лог' : 'Copy log';
  String get retry => isRu ? 'Повторить' : 'Retry';
  String get logCopied => isRu ? 'Лог ошибки скопирован' : 'Error log copied';
  String get openOnMangaLib =>
      isRu ? 'Открыть на MangaLib' : 'Open on MangaLib';
  String get backToManga => isRu ? 'Вернуться к манге' : 'Back to manga';
}