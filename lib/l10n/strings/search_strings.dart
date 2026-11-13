import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class SearchStrings extends AppStrings {
  const SearchStrings(super.isRu);

  factory SearchStrings.of(BuildContext context) =>
      SearchStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'Каталог и поиск' : 'Catalog & Search';
  String get searchOnlineCatalog =>
      isRu ? 'Искать в каталоге онлайн' : 'Search the online catalog';
  String get searchSavedOnly =>
      isRu ? 'Искать только сохранённое' : 'Search saved titles only';
  String get pasteLink => isRu ? 'Вставить ссылку' : 'Paste Link';
  String get catalog => isRu ? 'Каталог' : 'Catalog';
  String get collections => isRu ? 'Коллекции' : 'Collections';
  String get searchHint =>
      isRu ? 'Поиск по названию или автору...' : 'Search by title or author...';
  String get advancedFilters =>
      isRu ? 'Расширенные фильтры' : 'Advanced Filters';
  String get clearHistory => isRu ? 'Очистить историю' : 'Clear history';
  String get offlineSearch => isRu ? 'Оффлайн-поиск' : 'Offline search';
  String get sort => isRu ? 'Сортировка' : 'Sort';

  String get sortPopularity => isRu ? 'Популярность' : 'Popularity';
  String get sortRating => isRu ? 'Рейтинг' : 'Rating';
  String get sortNewest => isRu ? 'Новинки' : 'Newest';
  String get sortChapters => isRu ? 'По главам' : 'Chapters';
  String get sortReleaseYear => isRu ? 'По году' : 'Release Year';
  String get sortAlphabetical => isRu ? 'По имени (А-Я)' : 'Alphabetical';

  String get typeAll => isRu ? 'Все' : 'All';
  String get typeManga => isRu ? 'Манга' : 'Manga';
  String get typeManhwa => isRu ? 'Манхва' : 'Manhwa';
  String get typeManhua => isRu ? 'Маньхуа' : 'Manhua';
  String get typeRumanga => isRu ? 'Руманга' : 'Rumanga';
  String get typeComic => isRu ? 'Комикс' : 'Comic';
  String get typeSingle => isRu ? 'Сингл' : 'Single';

  String get statusAll => isRu ? 'Все' : 'All';
  String get statusOngoing => isRu ? 'Онгоинг' : 'Ongoing';
  String get statusCompleted => isRu ? 'Завершён' : 'Completed';
  String get statusAnnounced => isRu ? 'Анонс' : 'Announced';
  String get statusOnHold => isRu ? 'Приостановлен' : 'On Hold';

  String get emptyTitle => isRu ? 'Ничего не найдено' : 'No manga found';
  String get emptySubtitle => isRu
      ? 'Попробуйте изменить поисковый запрос или фильтры'
      : 'Try adjusting your search query or filters';
  String get resetFilters => isRu ? 'Сбросить все фильтры' : 'Reset all filters';
  String get retry => isRu ? 'Повторить' : 'Retry';
  String loadingError(String error) =>
      isRu ? 'Ошибка загрузки: $error' : 'Loading error: $error';
  String collectionsError(String error) => isRu
      ? 'Ошибка загрузки коллекций: $error'
      : 'Error loading collections: $error';
  String get noCollections => isRu ? 'Коллекции не найдены' : 'No collections found';
  String get invalidLink => isRu ? 'Неверная ссылка' : 'Invalid link';

  String get advancedFiltersTitle =>
      isRu ? 'Расширенный поиск' : 'Advanced Filters';
  String get reset => isRu ? 'Сбросить' : 'Reset';
  String get sortBy => isRu ? 'Сортировка' : 'Sort By';
  String get sortByPopularity => isRu ? 'По популярности' : 'Popularity';
  String get sortByRating => isRu ? 'По рейтингу' : 'Rating';
  String get sortByAlphabetical => isRu ? 'По алфавиту' : 'Alphabetical';
  String get mangaType => isRu ? 'Тип произведения' : 'Manga Type';
  String get titleStatus => isRu ? 'Статус тайтла' : 'Title Status';
  String get translationStatus =>
      isRu ? 'Статус перевода' : 'Translation Status';
  String get ageRating => isRu ? 'Возрастной рейтинг' : 'Age Rating';
  String get releaseFormat => isRu ? 'Формат выпуска' : 'Release Format';
  String includeGenres(String count) =>
      isRu ? 'Включить жанры ($count выбр.)' : 'Include Genres ($count sel.)';
  String excludeGenres(String count) =>
      isRu ? 'Исключить жанры ($count искл.)' : 'Exclude Genres ($count excl.)';
  String tags(String count) =>
      isRu ? 'Теги ($count выбр.)' : 'Tags ($count sel.)';
  String get searchGenresHint => isRu ? 'Поиск жанров...' : 'Search genres...';
  String get searchTagsHint => isRu ? 'Поиск тегов...' : 'Search tags...';
  String get applyFilters => isRu ? 'Применить фильтры' : 'Apply Filters';
}