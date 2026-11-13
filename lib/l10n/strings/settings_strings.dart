import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class SettingsStrings extends AppStrings {
  const SettingsStrings(super.isRu);

  factory SettingsStrings.of(BuildContext context) =>
      SettingsStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'Настройки' : 'Settings';

  // Appearance & language
  String get appearanceAndLanguage =>
      isRu ? 'Оформление и язык' : 'Appearance & Language';
  String get themeMode => isRu ? 'Режим темы' : 'Theme Mode';
  String get themeSystem => isRu ? 'Система' : 'System';
  String get themeDark => isRu ? 'Тёмная' : 'Dark';
  String get themeLight => isRu ? 'Светлая' : 'Light';
  String get interfaceLanguage =>
      isRu ? 'Язык интерфейса' : 'Interface Language';
  String get languageAuto => isRu ? 'Авто' : 'Auto';
  String get amoledMode =>
      isRu ? 'Режим Pure AMOLED' : 'Pure AMOLED Black';
  String get amoledSubtitle => isRu
      ? 'Глубокий черный фон для OLED экранов'
      : 'Pitch black background for OLED screens';
  String get streakReminders =>
      isRu ? 'Напоминания об огоньке' : 'Daily Streak Reminders';
  String get streakRemindersSubtitle => isRu
      ? 'Ежедневное напоминание почитать главу и сохранить стрик'
      : 'Daily reminder to read a chapter and keep flame burning';
  String get mangaRecap =>
      isRu ? 'Manga Recap / Итоги чтения' : 'Manga Recap Summary';
  String get mangaRecapSubtitle => isRu
      ? 'Красивая карточка с вашей статистикой чтения и топами'
      : 'Beautiful summary card with reading stats & tops';
  String get achievements => isRu ? 'Достижения' : 'Achievements';
  String get achievementsSubtitle => isRu
      ? 'Просмотр всех наград, уровней и прогресса'
      : 'View all rewards, levels & progress';
  String get readingStatistics =>
      isRu ? 'Статистика чтения' : 'Reading Statistics';
  String get readingStatisticsSubtitle => isRu
      ? 'Аналитика жанров, времени активности и прогресса'
      : 'Analytics of genres, activity time & progress';
  String get chapterNotifications =>
      isRu ? 'Уведомления о новых главах' : 'New Chapters Notifications';
  String get chapterNotificationsSubtitle => isRu
      ? 'Отслеживание выхода свежих глав для тайтлов в библиотеке'
      : 'Track newly uploaded chapters for bookmarked titles';

  // Notifications & quiet hours
  String get notificationsAndQuietHours =>
      isRu ? 'Уведомления и тихие часы' : 'Notifications & Quiet Hours';
  String get quietHours => isRu ? 'Тихие часы' : 'Quiet Hours';
  String get quietHoursSubtitle => isRu
      ? 'Не присылать уведомления о главах ночью'
      : 'Hold chapter notifications during the night';
  String get quietHoursStart => isRu ? 'Начало' : 'Starts at';
  String get quietHoursEnd => isRu ? 'Конец' : 'Ends at';
  String get dailyDigest => isRu ? 'Один дайджест в день' : 'One Daily Digest';
  String get dailyDigestSubtitle => isRu
      ? 'Вместо уведомления на каждую главу — одна сводка «Новые главы: N»'
      : 'One summary («New chapters: N») instead of a ping per chapter';

  // Reader defaults
  String get readerDefaults =>
      isRu ? 'Читалка по умолчанию' : 'Reader Defaults';
  String get readingDirection =>
      isRu ? 'Направление чтения' : 'Reading Direction';
  String get readingDirectionVerticalWebtoon =>
      isRu ? 'Вертикальный вебтун (Сверху вниз)' : 'Vertical Webtoon';
  String get verticalWebtoon =>
      isRu ? 'Вертикальный вебтун' : 'Vertical Webtoon';
  String get readingDirectionRightToLeft =>
      isRu ? 'Справа налево (Манга)' : 'Right to Left';
  String get readingDirectionLeftToRight =>
      isRu ? 'Слева направо' : 'Left to Right';
  String get readerBackground => isRu ? 'Фон читалки' : 'Reader Background';
  String get readerBackgroundBlack => isRu ? 'Чёрный' : 'Black';
  String get readerBackgroundDarkGrey =>
      isRu ? 'Тёмно-серый' : 'Dark Grey';
  String get readerBackgroundWhite => isRu ? 'Белый' : 'White';
  String get sharpeningFilter =>
      isRu ? 'Фильтр резкости' : 'Sharpening Filter';
  String get sharpeningSubtle => isRu ? 'Мягкая резкость' : 'Subtle';
  String get sharpeningHigh => isRu ? 'Высокая резкость' : 'High';
  String get off => isRu ? 'Отключено' : 'Off';
  String get cropBorders =>
      isRu ? 'Обрезка белых полей' : 'Crop White Borders';
  String get cropBordersSubtitle =>
      isRu ? 'Автоматически удаляет белые поля' : 'Trim empty borders';
  String get smartStatusBar =>
      isRu ? 'Умный статус-бар' : 'Smart Status Bar';
  String get smartStatusBarSubtitle => isRu
      ? 'Отображение времени и заряда батареи'
      : 'Show clock and battery';

  // Download engine
  String get downloadEngine => isRu ? 'Движок загрузки' : 'Download Engine';
  String get concurrentImages =>
      isRu ? 'Параллельные потоки изображений:' : 'Concurrent images:';
  String get concurrentChapters =>
      isRu ? 'Параллельные главы:' : 'Concurrent chapters:';
  String get smartOffline => isRu ? 'Умный оффлайн' : 'Smart Offline';
  String get smartOfflineSubtitle => isRu
      ? 'Автоскачивание следующих глав во время чтения'
      : 'Auto-download next chapters while reading';
  String get disabled => isRu ? 'Отключено' : 'Disabled';
  String get smartOfflineOneChapter =>
      isRu ? '1 след. глава' : '1 next chapter';
  String get smartOfflineTwoChapters => isRu ? '2 главы' : '2 chapters';
  String get smartOfflineThreeChapters => isRu ? '3 главы' : '3 chapters';
  String get smartOfflineFiveChapters => isRu ? '5 глав' : '5 chapters';
  String get autoDeleteRead =>
      isRu ? 'Автоудаление прочитанного' : 'Auto-Delete Read Chapters';
  String get autoDeleteReadSubtitle => isRu
      ? 'Автоматически удалять скачанную главу с устройства после прочтения'
      : 'Automatically delete downloaded chapter file after finishing reading';

  // Backups & export
  String get backupsAndExport =>
      isRu ? 'Резервные копии и экспорт' : 'Backups & Export';
  String get automaticBackups =>
      isRu ? 'Автоматические копии' : 'Automatic Backups';
  String get backupsOff => isRu
      ? 'Копии отключены — создавайте вручную'
      : 'Backups off — create them manually';
  String backupEvery(String period) =>
      isRu ? 'Копия раз в $period' : 'Backup every $period';
  String get createBackupNow =>
      isRu ? 'Создать копию сейчас' : 'Create Backup Now';
  String get noBackupsYet => isRu ? 'Копий пока не было' : 'No backups yet';
  String lastBackup(String moment) =>
      isRu ? 'Последняя копия: $moment' : 'Last backup: $moment';
  String get create => isRu ? 'Создать' : 'Create';
  String get exportBackupJson =>
      isRu ? 'Экспорт базы данных (JSON)' : 'Export Backup (JSON)';
  String get exportBackupJsonSubtitle => isRu
      ? 'Сохраняет библиотеку, историю и закладки'
      : 'Save library, history & bookmarks';
  String get importBackupJson =>
      isRu ? 'Импорт базы данных (JSON)' : 'Import Backup (JSON)';
  String get importBackupJsonSubtitle => isRu
      ? 'Восстановить библиотеку из JSON-файла'
      : 'Restore library from JSON file';
  String get exportMal =>
      isRu ? 'Экспорт в MyAnimeList (XML)' : 'Export to MyAnimeList (XML)';
  String get exportMalSubtitle =>
      isRu ? 'Экспорт библиотеки в формат MAL' : 'Export library to MAL format';
  String get importMal =>
      isRu ? 'Импорт из MyAnimeList (XML)' : 'Import from MyAnimeList (XML)';
  String get importMalSubtitle => isRu
      ? 'Импорт манги из экспорта MyAnimeList'
      : 'Import manga from MyAnimeList export';
  String get importMalUrl =>
      isRu ? 'Импорт из MyAnimeList по ссылке' : 'Import from MyAnimeList (URL)';
  String get importMalUrlSubtitle => isRu
      ? 'Скачать XML-экспорт по прямой ссылке'
      : 'Download an XML export from a direct link';
  String get backupFailed =>
      isRu ? 'Не удалось создать резервную копию' : 'Could not create a backup';
  String backupSaved(String path) =>
      isRu ? 'Копия сохранена: $path' : 'Backup saved: $path';
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

  // Storage & cache
  String get storageAndCache => isRu ? 'Хранилище и кэш' : 'Storage & Cache';
  String get autoClearCache => isRu ? 'Автоочистка кэша' : 'Auto-Clear Cache';
  String get autoClearCacheSubtitle => isRu
      ? 'Удалять кэшированные страницы старше выбранного срока'
      : 'Remove cached pages older than selected period';
  String get cacheThreeDays => isRu ? '3 дня' : '3 days';
  String get cacheSevenDaysRecommended =>
      isRu ? '7 дней (рек.)' : '7 days (rec.)';
  String get cacheFourteenDays => isRu ? '14 дней' : '14 days';
  String get cacheThirtyDays => isRu ? '30 дней' : '30 days';
  String get clearCache =>
      isRu ? 'Очистить кэш приложения' : 'Clear Application Cache';
  String get clearCacheSubtitle => isRu
      ? 'Очищает сетевой дисковый кэш и оперативную память'
      : 'Clears disk network cache & RAM memory';
  String get clear => isRu ? 'Очистить' : 'Clear';
  String cacheCleared(String size) => isRu
      ? 'Кэш очищен ($size МБ освобождено)'
      : 'Cache cleared ($size MB freed)';

  // Updates
  String get updates => isRu ? 'Обновления' : 'Updates';
  String versionWithStore(String value) =>
      isRu ? 'Версия: v$value (RuStore)' : 'Version: v$value (RuStore)';
  String get storeUpdatesNote => isRu
      ? 'Обновления приложения управляются через магазин RuStore'
      : 'App updates are managed via RuStore';
  String versionLabel(String value) =>
      isRu ? 'Версия: v$value' : 'Version: v$value';
  String downloading(String percent) =>
      isRu ? 'Загрузка: $percent%' : 'Downloading: $percent%';
  String get updateReady =>
      isRu ? 'Обновление готово к установке' : 'Update ready to install';
  String get checkReleasesNote =>
      isRu ? 'Проверка новых релизов на GitHub' : 'Check for new releases on GitHub';
  String get install => isRu ? 'Установить' : 'Install';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get update => isRu ? 'Обновить' : 'Update';
  String get check => isRu ? 'Проверить' : 'Check';
  String get updateChannel => isRu ? 'Канал обновлений' : 'Update Channel';
  String get updateChannelSubtitle =>
      isRu ? 'Стабильные релизы или Dev/Beta' : 'Stable releases or Dev/Beta';
  String get checkOnLaunch =>
      isRu ? 'Проверять при запуске' : 'Check updates on launch';
  String get checkOnLaunchSubtitle => isRu
      ? 'Тихий поиск свежих версий на главной'
      : 'Silent background check on startup';
  String get updateCheckFailed => isRu
      ? 'Не удалось проверить обновления'
      : 'Failed to check for updates';
  String latestVersion(String value) => isRu
      ? 'У вас установлена последняя версия ($value)'
      : 'You have the latest version ($value)';

  // About
  String get aboutApp => isRu ? 'О приложении' : 'About App';
  String version(String value) => isRu ? 'Версия $value' : 'Version $value';
  String get aboutDescription => isRu
      ? 'Современный загрузчик и ридер манги с аппаратным декодированием, масштабированием, автоскроллом и оффлайн-режимом CBZ.'
      : 'Modern manga reader and downloader with hardware decoding, scaling, auto-scroll and offline CBZ mode.';
}