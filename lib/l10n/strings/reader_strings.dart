import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class ReaderStrings extends AppStrings {
  const ReaderStrings(super.isRu);

  factory ReaderStrings.of(BuildContext context) =>
      ReaderStrings(AppStrings.isRussian(context));

  String get breakReminder => isRu
      ? 'Вы читаете уже 2 часа. Сделайте перерыв для отдыха глаз.'
      : 'You have been reading for 2 hours. Take a break to rest your eyes.';
  String get snooze => isRu ? 'Отложить' : 'Snooze';
  String chapterTitle(String volume, String number) =>
      isRu ? 'Том $volume Гл. $number' : 'Vol. $volume Ch. $number';
  String get contentBlocked => isRu
      ? 'Контент недоступен в соответствии с требованиями законодательства РФ'
      : 'Content is unavailable in compliance with local regulations';
  String get cbzReadFailed => isRu
      ? 'Не удалось прочитать страницы из локального CBZ файла'
      : 'Could not read pages from the local CBZ file';
  String nextChapterPrompt(String volume, String number) => isRu
      ? 'Перейти к следующей главе: Том $volume Гл. $number?'
      : 'Continue with volume $volume chapter $number?';
  String get read => isRu ? 'Читать' : 'Read';
  String get endOfChapter =>
      isRu ? 'Вы дочитали главу.' : 'You reached the end of this chapter.';
  String get autoScrollWebtoonOnly => isRu
      ? 'Автопрокрутка доступна только в режиме ленты'
      : 'Auto-scroll is available in webtoon mode only';
  String get cacheCleared => isRu
      ? 'Кэш изображений главы сброшен, перезагрузка...'
      : 'Chapter image cache cleared, reloading...';

  String get jumpToPage => isRu ? 'Перейти на страницу' : 'Jump to page';
  String get close => isRu ? 'Закрыть' : 'Close';
  String get loadingChapter => isRu ? 'Загрузка главы...' : 'Loading chapter...';
  String get loadingPages => isRu ? 'Загрузка страниц...' : 'Loading pages...';

  String get previousChapter =>
      isRu ? 'Предыдущая глава' : 'Previous Chapter';
  String get previousChapterInline =>
      isRu ? 'Предыдущая глава' : 'Previous chapter';
  String get nextChapter => isRu ? 'Следующая глава' : 'Next Chapter';
  String get nextChapterShort => isRu ? 'След. глава' : 'Next Ch.';
  String get chapterList => isRu ? 'Список глав' : 'Chapter list';
  String get chapterListCased => isRu ? 'Список глав' : 'Chapter List';
  String chapterListTitle(String count) =>
      isRu ? 'Список глав ($count)' : 'Chapters ($count)';
  String get pageGrid => isRu ? 'Сетка страниц' : 'Page Grid';
  String get stopAutoScroll =>
      isRu ? 'Остановить автопрокрутку (A)' : 'Stop autoscroll (A)';
  String get autoScroll => isRu ? 'Автопрокрутка (A)' : 'Autoscroll (A)';
  String get autoScrollLabel => isRu ? 'Автоскролл' : 'Auto-scroll';
  String get fullscreen =>
      isRu ? 'Полноэкранный режим (F11)' : 'Fullscreen (F11)';
  String get reloadChapter =>
      isRu ? 'Сбросить кэш и перезагрузить главу' : 'Reload chapter';
  String get chapterComments =>
      isRu ? 'Комментарии к главе' : 'Chapter comments';
  String commentsTitle(String slugUrl, String volume, String number) => isRu
      ? '$slugUrl - Том $volume Гл. $number'
      : '$slugUrl - Vol. $volume Ch. $number';
  String get settings => isRu ? 'Настройки' : 'Settings';
  String get zoomIn => isRu ? 'Приблизить (+)' : 'Zoom In (+)';
  String get zoomOut => isRu ? 'Отдалить (-)' : 'Zoom Out (-)';
  String pageIndicator(String page, String total) =>
      isRu ? '$page / $total стр.' : '$page / $total p.';
  String get selectChapter => isRu ? 'Выбрать главу' : 'Select chapter';
  String get noPages => isRu ? 'Страницы не найдены.' : 'No pages found.';
  String get goBack => isRu ? 'Назад' : 'Go Back';
  String get searchChapter => isRu ? 'Поиск главы...' : 'Search chapter...';
  String volumeChapter(String volume, String number) =>
      isRu ? 'Том $volume Глава $number' : 'Volume $volume Chapter $number';
  String get tapToRetry => isRu ? 'Нажмите для повтора' : 'Tap to retry';

  String get readerSettings =>
      isRu ? 'Настройки читалки' : 'Reader Settings';
  String get readingMode => isRu ? 'Режим чтения' : 'Reading Mode';
  String get modeWebtoon => isRu ? 'Лента' : 'Webtoon';
  String get modeLtr => isRu ? 'Слева' : 'LTR';
  String get modeRtl => isRu ? 'Справа (Манга)' : 'RTL (Manga)';
  String get pageLayout => isRu ? 'Отображение страниц' : 'Page Layout';
  String get layoutAuto => isRu ? 'Авто' : 'Auto';
  String get layoutSingle => isRu ? '1 страница' : '1 Page';
  String get layoutDual => isRu ? '2 страницы' : '2 Pages';
  String get pageScale =>
      isRu ? 'Масштабирование страниц' : 'Page Scale';
  String get scaleFitScreen => isRu ? 'По экрану' : 'Fit Screen';
  String get scaleFitWidth => isRu ? 'По ширине' : 'Fit Width';
  String get scaleCover => isRu ? 'Заполнить' : 'Cover';
  String get tapZones => isRu ? 'Зоны нажатия (тапы)' : 'Tap Zones';
  String get tapStandard => isRu ? 'Стандарт' : 'Standard';
  String get tapInverted => isRu ? 'Инверсия' : 'Inverted';
  String get tapEdges => isRu ? 'По краям' : 'Edges';
  String get backgroundColor => isRu ? 'Цвет фона' : 'Background Color';
  String get bgBlack => isRu ? 'Черный' : 'Black';
  String get bgGrey => isRu ? 'Серый' : 'Grey';
  String get bgWhite => isRu ? 'Белый' : 'White';
  String get colorFilter => isRu ? 'Цветовой фильтр' : 'Color Filter';
  String get filterNormal => isRu ? 'Обычный' : 'Normal';
  String get filterInvert => isRu ? 'Инверсия' : 'Invert';
  String get filterSepia => isRu ? 'Сепия' : 'Sepia';
  String get sharpeningFilter =>
      isRu ? 'Фильтр резкости' : 'Sharpening Filter';
  String get sharpeningOff => isRu ? 'Выкл' : 'Off';
  String get sharpeningSubtle => isRu ? 'Мягкий' : 'Subtle';
  String get sharpeningHigh => isRu ? 'Четкий' : 'High';
  String get cropBorders =>
      isRu ? 'Обрезка белых полей' : 'Crop White Borders';
  String get cropBordersSubtitle => isRu
      ? 'Автоматически увеличивает страницу для удаления пустых полей'
      : 'Automatically crops empty borders';
  String get cropMargin => isRu ? 'Степень обрезки' : 'Crop margin';
  String get pageBrightness => isRu ? 'Яркость страниц' : 'Page Brightness';
  String get pagePreload => isRu ? 'Предзагрузка страниц' : 'Page preload';
  String get resetTitleSettings =>
      isRu ? 'Сбросить настройки для этого тайтла' : 'Reset settings for this title';

  String get resetSettings => isRu ? 'Сбросить' : 'Reset';
  String get resetToGlobalSettings =>
      isRu ? 'Сбросить к общим' : 'Reset to global';
  String get titleOverrideNotice => isRu
      ? 'Для этого тайтла сохранены свои настройки'
      : 'This title has its own saved settings';
  String get sectionMode => isRu ? 'Режим' : 'Mode';
  String get sectionNavigation => isRu ? 'Навигация' : 'Navigation';
  String get sectionImage => isRu ? 'Изображение' : 'Image';
  String get sectionScrolling => isRu ? 'Прокрутка' : 'Scrolling';
  String get sectionTransitions => isRu ? 'Переходы' : 'Transitions';
  String get autoNextChapterTitle =>
      isRu ? 'Плавный переход к следующей главе' : 'Seamless next chapter';
  String get autoNextChapterSubtitle => isRu
      ? 'Следующая глава готовится заранее, пока вы читаете эту'
      : 'The next chapter is prepared in advance while you read';
  String nextChapterBanner(String number) =>
      isRu ? 'Далее: Глава $number' : 'Next: Ch. $number';
  String get nextChapterReady => isRu ? 'готово' : 'ready';
  String get youAreHere => isRu ? 'вы здесь' : 'you are here';
  String get presetWebtoon => isRu ? 'Вебтун' : 'Webtoon';
  String get presetMangaRtl => isRu ? 'Манга RTL' : 'Manga RTL';
  String get presetComicLtr => isRu ? 'Комикс LTR' : 'Comic LTR';
  String get autoScrollSpeed =>
      isRu ? 'Скорость автопрокрутки' : 'Autoscroll speed';
  String get menuAutoScroll => isRu ? 'Автопрокрутка' : 'Autoscroll';
  String get menuStopAutoScroll =>
      isRu ? 'Остановить автопрокрутку' : 'Stop autoscroll';
  String get exitFullscreen =>
      isRu ? 'Выйти из полноэкранного режима' : 'Exit fullscreen';
  String get moreActions => isRu ? 'Ещё' : 'More';

  String get latestChapterReached =>
      isRu ? 'Вы прочитали последнюю главу!' : 'You reached the latest chapter!';
  String get stayTuned => isRu
      ? 'Ожидайте выхода новых глав от переводчиков'
      : 'Stay tuned for upcoming releases';
  String previousWithNumber(String volume, String number) => isRu
      ? 'Предыдущая: Том $volume Гл. $number'
      : 'Previous Chapter';
  String get allChapters => isRu ? 'Список всех глав' : 'All Chapters';
  String nextChapterFound(String volume, String number) => isRu
      ? 'Найдена следующая глава: Том $volume Гл $number'
      : 'Next chapter found!';
  String get noNewChapters => isRu ? 'Новых глав пока нет' : 'No new chapters yet';
  String get checkNewChapters =>
      isRu ? 'Проверить новые главы' : 'Check for new chapters';

  String get chapterComplete => isRu ? 'Глава завершена' : 'Chapter Complete';
  String nextWithNumber(String volume, String number) => isRu
      ? 'Следующая: Том $volume Глава $number'
      : 'Next: Volume $volume Chapter $number';
  String get readNextChapter =>
      isRu ? 'Читать следующую главу' : 'Read Next Chapter';
}