import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

/// Strings of the desktop shell, table chrome and right-click menus.
class DesktopStrings extends AppStrings {
  const DesktopStrings(super.isRu);

  factory DesktopStrings.of(BuildContext context) =>
      DesktopStrings(AppStrings.isRussian(context));

  String get brand => 'Manga Loader';
  String get collapseRail => isRu ? 'Свернуть панель' : 'Collapse sidebar';
  String get expandRail => isRu ? 'Развернуть панель' : 'Expand sidebar';
  String get searchPlaceholder => isRu ? 'Поиск по каталогу' : 'Search catalog';
  String get searchTooltip => isRu
      ? 'Открыть каталог и перейти к поиску'
      : 'Open catalog and jump to search';
  String get refresh => isRu ? 'Обновить страницу' : 'Refresh page';

  String get shortcutSearch => isRu ? 'Поиск' : 'Search';
  String get shortcutBack => isRu ? 'Назад' : 'Back';
  String get shortcutRefresh => isRu ? 'Обновить' : 'Refresh';

  String get openDetails => isRu ? 'Открыть страницу тайтла' : 'Open details';
  String get startReading => isRu ? 'Начать чтение' : 'Start reading';
  String get continueReading => isRu ? 'Продолжить чтение' : 'Continue reading';
  String get openReader => isRu ? 'Открыть читалку' : 'Open reader';
  String get removeFromHistory =>
      isRu ? 'Удалить из истории' : 'Remove from history';

  String get columnTitle => isRu ? 'Название' : 'Title';
  String get columnChapters => isRu ? 'Главы' : 'Chapters';
  String get columnSize => isRu ? 'Размер' : 'Size';
  String get columnReadAt => isRu ? 'Прочитано' : 'Read at';
  String get columnProgress => isRu ? 'Прогресс' : 'Progress';
  String get columnChapter => isRu ? 'Глава' : 'Chapter';

  String get keyboardHint => isRu
      ? 'Клавиши: поиск, назад, обновление'
      : 'Keys: search, back, refresh';
}
