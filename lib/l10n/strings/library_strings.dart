import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class LibraryStrings extends AppStrings {
  const LibraryStrings(super.isRu);

  factory LibraryStrings.of(BuildContext context) =>
      LibraryStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'Моя библиотека' : 'My Library';
  String get exitSelection => isRu ? 'Выйти из выбора' : 'Exit selection';
  String selectedCount(String count) =>
      isRu ? 'Выбрано: $count' : 'Selected: $count';
  String get searchHint =>
      isRu ? 'Поиск в библиотеке...' : 'Search library...';
  String get syncWithMangalib =>
      isRu ? 'Синхронизировать с MangaLib' : 'Sync with MangaLib';
  String get search => isRu ? 'Поиск' : 'Search';
  String get viewList => isRu ? 'Список' : 'List';
  String get viewGrid => isRu ? 'Сетка' : 'Grid';
  String get sort => isRu ? 'Сортировка' : 'Sort';
  String get sortDateAdded =>
      isRu ? 'По дате добавления' : 'Date added';
  String get sortTitle => isRu ? 'По названию (А-Я)' : 'Title (A-Z)';
  String get sortRating => isRu ? 'По рейтингу' : 'Rating';
  String get sortProgress =>
      isRu ? 'По прогрессу чтения' : 'Reading progress';
  String get sortChapters =>
      isRu ? 'По количеству глав' : 'Total chapters';
  String get readingStatistics =>
      isRu ? 'Статистика чтения' : 'Reading Statistics';
  String get actions => isRu ? 'Действия' : 'Actions';
  String get newList => isRu ? 'Новый список' : 'New Custom List';
  String get exportBackup =>
      isRu ? 'Экспорт базы (JSON)' : 'Export Backup (JSON)';
  String get importBackup =>
      isRu ? 'Импорт базы (JSON)' : 'Import Backup (JSON)';
  String get exportMal =>
      isRu ? 'Экспорт в MyAnimeList' : 'Export to MyAnimeList';
  String get importMal =>
      isRu ? 'Импорт из MyAnimeList' : 'Import from MyAnimeList';
  String get openLocalFile =>
      isRu ? 'Локальный файл CBZ / ZIP' : 'Local CBZ / ZIP';

  String get all => isRu ? 'Все' : 'All';
  String get tabReading => isRu ? 'Читаю' : 'Reading';
  String get tabPlanToRead => isRu ? 'В планах' : 'Plan to Read';
  String get tabCompleted => isRu ? 'Прочитано' : 'Completed';
  String get tabFavorites => isRu ? 'Любимое' : 'Favorites';
  String get tabOnHold => isRu ? 'Отложено' : 'On Hold';
  String get tabDropped => isRu ? 'Брошено' : 'Dropped';

  String get listTypeReading => isRu ? 'Читаю' : 'Reading';
  String get listTypePlanToRead => isRu ? 'В планах' : 'Plan to read';
  String get listTypeCompleted => isRu ? 'Прочитано' : 'Completed';
  String get listTypeFavorites => isRu ? 'Любимое' : 'Favorites';
  String get listTypeOnHold => isRu ? 'Отложено' : 'On hold';
  String get listTypeDropped => isRu ? 'Брошено' : 'Dropped';

  String get emptyTitle => isRu ? 'Библиотека пуста' : 'Your library is empty';
  String get emptySubtitle => isRu
      ? 'Добавляйте тайтлы из каталога или поиска'
      : 'Add manga from catalog or search';
  String get browseCatalog => isRu ? 'Перейти в каталог' : 'Browse Catalog';
  String get emptyCategory =>
      isRu ? 'В этой категории пока ничего нет' : 'No items in this category';
  String unread(String chapters) =>
      isRu ? '$chapters не прочитано' : '$chapters unread';

  String get moveToList => isRu ? 'Переместить в список' : 'Move to list';
  String get deleteDownloads => isRu ? 'Удалить загрузки' : 'Delete downloads';
  String get removeFromLibrary =>
      isRu ? 'Убрать из библиотеки' : 'Remove from library';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get create => isRu ? 'Создать' : 'Create';
  String get listNameHint => isRu ? 'Название списка' : 'List name';

  String titlesMoved(String count) =>
      isRu ? 'Перемещено тайтлов: $count' : 'Titles moved: $count';
  String movedWithFailures(String moved, String failed) => isRu
      ? 'Перемещено: $moved, ошибок: $failed'
      : 'Moved: $moved, failed: $failed';

  String get deleteDownloadsTitle =>
      isRu ? 'Удалить загрузки?' : 'Delete downloads?';
  String deleteDownloadsMessage(String count) => isRu
      ? 'Скачанные главы выбранных тайтлов ($count) будут удалены с устройства.'
      : 'Downloaded chapters of the selected titles ($count) will be deleted from this device.';
  String get delete => isRu ? 'Удалить' : 'Delete';
  String downloadsDeletedFor(String count) => isRu
      ? 'Загрузки удалены у тайтлов: $count'
      : 'Downloads deleted for titles: $count';
  String deletedWithFailures(String deleted, String failed) => isRu
      ? 'Удалено: $deleted, ошибок: $failed'
      : 'Deleted: $deleted, failed: $failed';

  String get removeFromLibraryTitle =>
      isRu ? 'Убрать из библиотеки?' : 'Remove from library?';
  String removeFromLibraryMessage(String count) => isRu
      ? 'Выбранные тайтлы ($count) будут убраны из библиотеки. Скачанные главы останутся на устройстве.'
      : 'The selected titles ($count) will be removed from your library. Downloaded chapters stay on this device.';
  String get remove => isRu ? 'Убрать' : 'Remove';
  String removedFromLibrary(String count) =>
      isRu ? 'Убрано из библиотеки: $count' : 'Removed from library: $count';
  String removedWithFailures(String removed, String failed) => isRu
      ? 'Убрано: $removed, ошибок: $failed'
      : 'Removed: $removed, failed: $failed';

  String get viewDetails =>
      isRu ? 'Открыть страницу тайтла' : 'View manga details';
  String get changeCategory =>
      isRu ? 'Сменить категорию / статус' : 'Move to another category';
  String get deleteFromLibrary =>
      isRu ? 'Удалить из библиотеки' : 'Remove from library';
  String get titleRemoved =>
      isRu ? 'Тайтл удалён из библиотеки' : 'Removed from library';
  String get selectCategory => isRu ? 'Выберите категорию' : 'Select Category';

  String titlesSynced(String count) => isRu
      ? 'Синхронизировано $count тайтлов из MangaLib'
      : 'Synced $count titles from MangaLib';
  String get signInToSync => isRu
      ? 'Войдите в аккаунт MangaLib для синхронизации'
      : 'Sign in to MangaLib to sync';
  String get signIn => isRu ? 'Войти' : 'Sign In';
  String get backupShareText => isRu
      ? 'Резервная копия библиотеки MangaLoader'
      : 'MangaLoader Backup';
  String get backupRestored => isRu
      ? 'Резервная копия успешно восстановлена!'
      : 'Backup restored successfully!';
  String get malExportShareText =>
      isRu ? 'Экспорт библиотеки MyAnimeList (MAL)' : 'MyAnimeList Export (XML)';
  String malImportDone(String imported, String updated) => isRu
      ? 'Импорт MAL завершен: добавлено $imported, обновлено $updated'
      : 'MAL Import done: $imported added, $updated updated';
}