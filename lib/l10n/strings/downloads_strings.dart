import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class DownloadsStrings extends AppStrings {
  const DownloadsStrings(super.isRu);

  factory DownloadsStrings.of(BuildContext context) =>
      DownloadsStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'Загрузки и файлы' : 'Downloads & Files';
  String get openLocalFile =>
      isRu ? 'Открыть локальный файл CBZ / ZIP' : 'Open local CBZ / ZIP';
  String get retryAllFailed =>
      isRu ? 'Повторить все ошибки' : 'Retry all failed';
  String get pause => isRu ? 'Пауза' : 'Pause';
  String get resume => isRu ? 'Продолжить' : 'Resume';
  String get cancel => isRu ? 'Отмена' : 'Cancel';

  String get storage => isRu ? 'Хранилище' : 'Storage';
  String get noLimit => isRu ? 'без лимита' : 'no limit';
  String get freeUpSpace => isRu ? 'Освободить место' : 'Free up space';
  String get freeUpSpaceTitle =>
      isRu ? 'Освободить место?' : 'Free up space?';
  String get freeUpSpaceMessage => isRu
      ? 'Будут удалены скачанные главы, отмеченные как прочитанные.'
      : 'Downloaded chapters marked as read will be deleted.';
  String get cleanUp => isRu ? 'Очистить' : 'Clean up';
  String get noReadChapters =>
      isRu ? 'Прочитанных глав для удаления нет' : 'No read chapters to delete';
  String deletedChapters(String count, String size) =>
      isRu ? 'Удалено глав: $count · $size' : 'Deleted $count chapters · $size';

  String get downloadQueue =>
      isRu ? 'Очередь загрузок' : 'Download queue';
  String get clearFinished => isRu ? 'Очистить готовые' : 'Clear finished';
  String get pauseQueue => isRu ? 'Приостановить очередь' : 'Pause queue';
  String get resumeQueue => isRu ? 'Возобновить очередь' : 'Resume queue';
  String get queuePaused => isRu ? 'Очередь на паузе' : 'Queue paused';
  String get queuePausedHint => isRu
      ? 'Текущая глава доскачается, следующие ждут продолжения'
      : 'The running chapter finishes, the rest waits for you';
  String get queueScheduledHint =>
      isRu ? 'Загрузки возобновятся в' : 'Downloads resume at';
  String get queueWaitingWifi => isRu
      ? 'Очередь ждёт Wi-Fi'
      : 'Queue is waiting for Wi-Fi';
  String queueProgress(String done, String total) =>
      isRu ? 'Готово $done из $total' : '$done of $total done';
  String get statusPaused => isRu ? 'На паузе' : 'Paused';
  String get volumeShort => isRu ? 'Том' : 'Vol';
  String get chapterShort => isRu ? 'Гл' : 'Ch';
  String get retry => isRu ? 'Повторить' : 'Retry';
  String get removeFromQueue =>
      isRu ? 'Убрать из очереди' : 'Remove from queue';
  String attempt(String count) =>
      isRu ? ' · попытка $count' : ' · attempt $count';
  String get statusQueued => isRu ? 'В очереди' : 'Queued';
  String get statusDownloading => isRu ? 'Загружается' : 'Downloading';
  String get statusWaitingForWifi =>
      isRu ? 'Ожидает Wi-Fi' : 'Waiting for Wi-Fi';
  String get statusFailed => isRu ? 'Ошибка загрузки' : 'Download failed';
  String failedWithError(String error) =>
      isRu ? 'Ошибка: $error' : 'Failed: $error';
  String get statusDone => isRu ? 'Готово' : 'Done';

  String get stateQueued => isRu ? 'в очереди' : 'queued';
  String get stateDownloading => isRu ? 'загрузка' : 'downloading';
  String get stateWaitingForNetwork =>
      isRu ? 'ожидание сети' : 'waiting for network';
  String get statePaused => isRu ? 'пауза' : 'paused';
  String get stateCompleted => isRu ? 'готово' : 'done';
  String get stateFailed => isRu ? 'ошибка' : 'failed';

  String get activeDownloads =>
      isRu ? 'Активные загрузки' : 'Active Downloads';
  String get pageShort => isRu ? 'стр.' : 'p.';
  String get downloadedManga =>
      isRu ? 'Скачанная манга (CBZ)' : 'Downloaded Manga (CBZ)';
  String get openFile => isRu ? 'Открыть файл' : 'Open file';
  String get searchHint =>
      isRu ? 'Поиск в скачанных...' : 'Search downloads...';
  String get sort => isRu ? 'Сортировка' : 'Sort';
  String get sortByTitle => isRu ? 'По названию (А-Я)' : 'By Title (A-Z)';
  String get sortByChapters => isRu ? 'По числу глав' : 'Most Chapters';
  String get sortBySize => isRu ? 'По размеру файлов' : 'Largest Size';
  String get sortByRecent =>
      isRu ? 'Недавно скачанные' : 'Recently Downloaded';
  String get noDownloads => isRu ? 'Нет скачанных глав' : 'No downloaded chapters';
  String get noDownloadsSubtitle => isRu
      ? 'Скачайте главы со страницы тайтла или откройте локальный .cbz файл'
      : 'Download chapters from manga page or open a local .cbz file';
  String noMatches(String query) => isRu
      ? 'Ничего не найдено по запросу "$query"'
      : 'No matches for "$query"';
  String get chapterCountShort => isRu ? 'гл.' : 'ch.';
  String get deleteAllChapters =>
      isRu ? 'Удалить все главы' : 'Delete all chapters';
  String get openDetails =>
      isRu ? 'Открыть страницу тайтла' : 'Open details';
  String get chaptersInOrder => isRu ? 'Главы по порядку:' : 'Chapters in order:';
  String get ascending =>
      isRu ? 'С первых глав' : 'Ascending (1.0 ->)';
  String get descending => isRu ? 'С последних глав' : 'Descending';
  String get read => isRu ? 'Читать' : 'Read';
  String get deleteChapter => isRu ? 'Удалить главу' : 'Delete chapter';

  String get deleteChapterTitle => isRu ? 'Удалить главу?' : 'Delete chapter?';
  String deleteChapterMessage(String volume, String number) => isRu
      ? 'Удалить Том $volume Гл $number из памяти устройства?'
      : 'Delete Vol $volume Ch $number from storage?';
  String get delete => isRu ? 'Удалить' : 'Delete';
  String get deleteMangaTitle =>
      isRu ? 'Удалить всю мангу?' : 'Delete entire manga?';
  String deleteMangaMessage(String count, String title, String size) => isRu
      ? 'Удалить все $count скачанные главы "$title" ($size)?'
      : 'Delete all $count downloaded chapters of "$title"?';
  String get deleteAll => isRu ? 'Удалить всё' : 'Delete all';
}