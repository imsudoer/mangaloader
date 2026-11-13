import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class DetailsStrings extends AppStrings {
  const DetailsStrings(super.isRu);

  factory DetailsStrings.of(BuildContext context) =>
      DetailsStrings(AppStrings.isRussian(context));

  String get tabAbout => isRu ? 'О тайтле' : 'About';
  String get tabChapters => isRu ? 'Главы' : 'Chapters';
  String get comments => isRu ? 'Комментарии' : 'Comments';

  String get animeSection => isRu ? 'Экранизация' : 'Anime adaptation';
  String get animeSectionHint => isRu
      ? 'Аниме по этой истории — нажмите, чтобы открыть карточку'
      : 'Anime of this story — tap to open its page';
  String get animeNoneFound => isRu
      ? 'По названию ничего не нашлось, попробуйте поиск ниже'
      : 'Nothing matched by title, try the search below';
  String get animeLookupFailed => isRu
      ? 'Не удалось получить список, доступен только поиск'
      : 'Could not load the list, search is still available';
  String get animeSearchHint => isRu ? 'Искать в:' : 'Search in:';
  String animeMeta(String kind, String year, String episodes) {
    final parts = <String>[
      if (kind.isNotEmpty) kind,
      if (year.isNotEmpty) year,
      if (episodes.isNotEmpty) (isRu ? '$episodes эп.' : '$episodes ep.'),
    ];
    return parts.join(' · ');
  }

  String get contentUnavailable =>
      isRu ? 'Контент недоступен' : 'Content Unavailable';
  String get errorTitle => isRu ? 'Ошибка' : 'Error';
  String loadFailed(String error) =>
      isRu ? 'Не удалось загрузить информацию: $error' : 'Failed to load info: $error';
  String get retry => isRu ? 'Повторить' : 'Retry';

  String get back => isRu ? 'Назад' : 'Back';
  String get share => isRu ? 'Поделиться' : 'Share';
  String get openOnMangalib =>
      isRu ? 'Открыть на MangaLib' : 'Open on MangaLib';
  String chaptersCount(String count) =>
      isRu ? '$count глав' : '$count chapters';
  String continueReading(String volume, String number) => isRu
      ? 'Продолжить (Т.$volume Гл.$number)'
      : 'Continue (V.$volume C.$number)';
  String get startReading => isRu ? 'Начать чтение' : 'Start Reading';
  String get addedToLibrary =>
      isRu ? 'Добавлено в библиотеку (Читаю)' : 'Added to library (Reading)';
  String get inList => isRu ? 'В списке' : 'In list';
  String get bookmark => isRu ? 'В библиотеку' : 'Bookmark';

  String get licensed =>
      isRu ? 'Тайтл лицензирован правообладателем' : 'Title is officially licensed';
  String get emptyChapters =>
      isRu ? 'Список глав пуст' : 'No chapters available';
  String licensedDescription(String suffix) => isRu
      ? 'Главы удалены из открытого доступа MangaLib по требованию правообладателя$suffix.'
      : 'Chapters have been removed from MangaLib by the copyright holder$suffix.';
  String get noChaptersUploaded => isRu
      ? 'На сервере MangaLib пока нет загруженных глав для этого тайтла.'
      : 'No chapters uploaded on MangaLib yet.';
  String get refresh => isRu ? 'Обновить' : 'Refresh';

  String get chapterSearchHint =>
      isRu ? 'Номер тома или главы...' : 'Chapter number...';
  String get exitBatch => isRu ? 'Обычный режим' : 'Exit batch';
  String get batchSelect =>
      isRu ? 'Выбрать несколько глав' : 'Batch select';
  String get oldestFirst => isRu ? 'Сначала старые' : 'Oldest first';
  String get newestFirst => isRu ? 'Сначала новые' : 'Newest first';
  String allFilter(String count) => isRu ? 'Все ($count)' : 'All ($count)';
  String downloadedFilter(String count) =>
      isRu ? 'Скачанные ($count)' : 'Downloaded ($count)';
  String get unread => isRu ? 'Непрочитанные' : 'Unread';
  String get deselect => isRu ? 'Снять выбор' : 'Deselect';
  String queuedForDownload(String count) => isRu
      ? 'В очереди на загрузку: $count глав'
      : 'Queued $count chapters for download';
  String downloadCount(String count) =>
      isRu ? 'Скачать ($count)' : 'Download ($count)';

  String volumeChapter(String volume, String number) =>
      isRu ? 'Том $volume Глава $number' : 'Vol. $volume Ch. $number';
  String pages(String count) =>
      isRu ? '• $count стр.' : '• $count p.';
  String get locked => isRu ? 'Платно' : 'Locked';
  String get paidAccess => isRu ? 'Платный доступ' : 'Paid access';
  String get readOffline =>
      isRu ? 'Читать оффлайн (CBZ)' : 'Read offline (CBZ)';
  String get readOnline => isRu ? 'Читать онлайн' : 'Read online';
  String retryChapter(String volume, String number) => isRu
      ? 'Повторная попытка: Том $volume Гл $number'
      : 'Retrying Vol $volume Ch $number';
  String get alreadyDownloaded =>
      isRu ? 'Глава уже скачана' : 'Chapter is already downloaded';
  String queuedChapter(String volume, String number) => isRu
      ? 'В очереди: Том $volume Гл $number'
      : 'Queued Vol $volume Ch $number';
  String chaptersLoadFailed(String error) => isRu
      ? 'Не удалось загрузить список глав: $error'
      : 'Failed to load chapters: $error';
  String get retryAttempt => isRu ? 'Повторить попытку' : 'Retry';

  String get authors => isRu ? 'Автор(ы):' : 'Author(s):';
  String get artists => isRu ? 'Художник(и):' : 'Artist(s):';
  String get synopsis => isRu ? 'Описание' : 'Synopsis';
  String get noSynopsis =>
      isRu ? 'Описание отсутствует' : 'No synopsis available';
  String get genres => isRu ? 'Жанры' : 'Genres';
  String get tags => isRu ? 'Теги' : 'Tags';

  String get readingOrder => isRu ? 'Порядок чтения' : 'Reading order';
  String get readingOrderSubtitle => isRu
      ? 'Франшиза целиком: от первой части к последней.'
      : 'The whole franchise, from the first entry to the last.';
  String get youAreHere => isRu ? 'вы здесь' : 'you are here';

  String get anotherVersion =>
      isRu ? 'Другая версия этой истории' : 'Another version of this story';
  String availableAs(String formats) =>
      isRu ? 'Доступно в формате: $formats' : 'Available as: $formats';
  String get relations => isRu ? 'Связанное' : 'Relations';
  String get similar => isRu ? 'Похожие тайтлы' : 'Similar Manga';
  String get noComments => isRu ? 'Пока нет комментариев' : 'No comments yet';

  String get libraryCategory =>
      isRu ? 'Категория в библиотеке' : 'Library Category';
  String get categoryReading => isRu ? 'Читаю' : 'Reading';
  String get categoryPlanToRead => isRu ? 'В планах' : 'Plan to Read';
  String get categoryCompleted => isRu ? 'Прочитано' : 'Completed';
  String get categoryFavorites => isRu ? 'Любимое' : 'Favorites';
  String get categoryOnHold => isRu ? 'Отложено' : 'On Hold';
  String get categoryDropped => isRu ? 'Брошено' : 'Dropped';
  String movedTo(String name) =>
      isRu ? 'Перенесено в: $name' : 'Moved to: $name';
  String get removeFromLibrary =>
      isRu ? 'Удалить из библиотеки' : 'Remove from library';
  String get removedFromLibrary =>
      isRu ? 'Удалено из библиотеки' : 'Removed from library';
}