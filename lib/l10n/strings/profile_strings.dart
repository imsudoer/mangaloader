import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class ProfileStrings extends AppStrings {
  const ProfileStrings(super.isRu);

  factory ProfileStrings.of(BuildContext context) =>
      ProfileStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'Профиль' : 'Profile';
  String get searchUsers => isRu ? 'Поиск пользователей' : 'Search Users';
  String get notifications => isRu ? 'Уведомления' : 'Notifications';
  String notificationCount(String count) =>
      isRu ? 'Уведомлений: $count' : 'Notifications: $count';
  String get settings => isRu ? 'Настройки' : 'Settings';

  String get dataAndExport => isRu ? 'Данные и экспорт' : 'Data & Export';
  String get importFromUrl => isRu ? 'Импорт из ссылки' : 'Import from URL';
  String get importFromUrlSubtitle => isRu
      ? 'Загрузить XML-экспорт MyAnimeList по прямой ссылке'
      : 'Load a MyAnimeList XML export from a direct link';

  String get accountManagement =>
      isRu ? 'Управление аккаунтом MangaLib' : 'MangaLib Account Management';
  String get editProfile =>
      isRu ? 'Редактировать профиль' : 'Edit Profile';
  String get editProfileSubtitle =>
      isRu ? 'Изменить никнейм, пол и описание' : 'Change username, gender & bio';
  String get privacyTitle =>
      isRu ? 'Приватность профиля' : 'Privacy Settings';
  String get privacySubtitle => isRu
      ? 'Настройка видимости профиля и статистики'
      : 'Configure visibility of profile & stats';
  String get syncBookmarks =>
      isRu ? 'Синхронизировать закладки' : 'Sync MangaLib Bookmarks';
  String get syncBookmarksSubtitle => isRu
      ? 'Импортировать все списки закладок в библиотеку'
      : 'Import all bookmark lists into library';

  String get guestMode => isRu ? 'Гостевой режим' : 'Guest Mode';
  String get guestSubtitle =>
      isRu ? 'Войдите для синхронизации с MangaLib' : 'Sign in to sync with MangaLib';
  String get signIn =>
      isRu ? 'Войти в аккаунт MangaLib' : 'Sign in to MangaLib';
  String get edit => isRu ? 'Редактировать' : 'Edit';
  String get logout => isRu ? 'Выйти' : 'Logout';

  String get recapTitle =>
      isRu ? 'Manga Recap / Итоги чтения' : 'Manga Recap Summary';
  String get recapSubtitle =>
      isRu ? 'Годовая сводка, рекорды и экспорт карточки' : 'Annual summary, tops & card export';
  String get view => isRu ? 'Открыть' : 'View';
  String get history => isRu ? 'История' : 'History';
  String get historySubtitle => isRu ? 'Прочитанное' : 'Recent reads';
  String get awardsTitle => isRu ? 'Достижения' : 'Awards';
  String get awardsSubtitle => isRu ? 'Награды' : 'Levels & XP';
  String get statistics => isRu ? 'Статистика' : 'Statistics';
  String get statisticsSubtitle => isRu ? 'Аналитика' : 'Analytics';

  String get usernameLabel => isRu ? 'Никнейм' : 'Username';
  String get gender => isRu ? 'Пол' : 'Gender';
  String get genderNone => isRu ? 'Не указан' : 'None';
  String get genderMale => isRu ? 'Мужской' : 'Male';
  String get genderFemale => isRu ? 'Женский' : 'Female';
  String get bioLabel => isRu ? 'О себе' : 'Bio / About';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get save => isRu ? 'Сохранить' : 'Save';
  String get profileUpdated =>
      isRu ? 'Профиль успешно обновлен' : 'Profile updated successfully';
  String profileUpdateFailed(String error) =>
      isRu ? 'Ошибка обновления профиля: $error' : 'Failed to update profile: $error';

  String get privacySettings =>
      isRu ? 'Настройки приватности' : 'Privacy Settings';
  String get profileVisibility =>
      isRu ? 'Видимость профиля' : 'Profile Visibility';
  String get visibilityEveryone =>
      isRu ? 'Виден всем' : 'Public to everyone';
  String get visibilityFriends => isRu ? 'Только друзьям' : 'Friends only';
  String get visibilityHidden =>
      isRu ? 'Скрытый профиль' : 'Hidden / Private';
  String get statisticsVisibility =>
      isRu ? 'Видимость статистики' : 'Statistics Visibility';
  String get statsHidden => isRu ? 'Скрыта' : 'Hidden';
  String get statsPublic => isRu ? 'Видна всем' : 'Public to all';
  String get privacyUpdated =>
      isRu ? 'Настройки приватности обновлены' : 'Privacy settings updated';
  String privacyUpdateFailed(String error) =>
      isRu ? 'Ошибка обновления приватности: $error' : 'Failed to update privacy: $error';

  String syncedTitles(String count) => isRu
      ? 'Синхронизировано $count тайтлов из MangaLib'
      : 'Synced $count titles from MangaLib';
  String syncError(String error) =>
      isRu ? 'Ошибка синхронизации: $error' : 'Sync error: $error';

  String get pasteLinkError =>
      isRu ? 'Вставьте ссылку на XML-экспорт' : 'Paste a link to the XML export';
  String addedTitles(String count) => isRu ? 'добавлено $count' : '$count added';
  String updatedTitles(String count) =>
      isRu ? 'обновлено $count' : '$count updated';
  String failedTitles(String count) =>
      isRu ? 'с ошибками $count' : '$count failed';
  String malUrlImport(String summary) =>
      isRu ? 'Импорт MAL по ссылке: $summary' : 'MAL URL import: $summary';
  String get importFailed =>
      isRu ? 'Не удалось импортировать файл' : 'Import failed';
  String get importDialogDescription => isRu
      ? 'Прямая ссылка на XML-экспорт MyAnimeList. Размер файла до 5 МБ.'
      : 'Direct link to a MyAnimeList XML export. Files up to 5 MB.';
  String get importInProgress =>
      isRu ? 'Загружаем и импортируем...' : 'Downloading and importing...';
  String get importAction => isRu ? 'Импортировать' : 'Import';
  String get errorInvalidUrl => isRu
      ? 'Нужна ссылка, начинающаяся с http:// или https://'
      : 'The link must start with http:// or https://';
  String get errorTimeout => isRu
      ? 'Сервер не ответил за 15 секунд'
      : 'The server did not respond within 15 seconds';
  String get errorTooLarge =>
      isRu ? 'Файл больше 5 МБ' : 'The file is larger than 5 MB';
  String get errorHttpStatus => isRu
      ? 'Сервер вернул ошибку — проверьте ссылку'
      : 'The server returned an error — check the link';
  String get errorNetwork =>
      isRu ? 'Нет соединения с сервером' : 'Cannot reach the server';
  String get errorNotMalExport => isRu
      ? 'Файл не похож на экспорт MyAnimeList'
      : 'The file does not look like a MyAnimeList export';
}