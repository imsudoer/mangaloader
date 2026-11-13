import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class HistoryStrings extends AppStrings {
  const HistoryStrings(super.isRu);

  factory HistoryStrings.of(BuildContext context) =>
      HistoryStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'История чтения' : 'Reading History';
  String get clearHistory => isRu ? 'Очистить историю' : 'Clear history';
  String get clearHistoryTitle =>
      isRu ? 'Очистить историю?' : 'Clear history?';
  String get clearHistoryMessage => isRu
      ? 'Вся история прочитанных глав будет удалена. Прогресс в библиотеке сохранится.'
      : 'All reading history will be deleted. Library progress will remain.';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get clear => isRu ? 'Очистить' : 'Clear';
  String get historyCleared => isRu ? 'История очищена' : 'History cleared';

  String get emptyTitle =>
      isRu ? 'История чтения пуста' : 'Reading history is empty';
  String get emptySubtitle =>
      isRu ? 'Здесь появятся прочитанные главы' : 'Read chapters will appear here';

  String get today => isRu ? 'Сегодня' : 'Today';
  String get yesterday => isRu ? 'Вчера' : 'Yesterday';
  String get thisWeek => isRu ? 'На этой неделе' : 'This week';
  String get thisMonth => isRu ? 'В этом месяце' : 'This month';
  String get earlier => isRu ? 'Ранее' : 'Earlier';

  String todayAt(String time) => isRu ? 'Сегодня, $time' : 'Today, $time';
  String yesterdayAt(String time) => isRu ? 'Вчера, $time' : 'Yesterday, $time';
  String daysAgo(String days) =>
      isRu ? '$days дн. назад' : '$days days ago';

  String chapterLabel(String volume, String number) =>
      isRu ? 'Том $volume Глава $number' : 'Vol. $volume Ch. $number';
  String get completed => isRu ? 'Прочитано' : 'Completed';
  String page(String pageAndTotal) =>
      isRu ? 'Стр. $pageAndTotal' : 'Page $pageAndTotal';
  String errorLoading(String error) => isRu
      ? 'Ошибка загрузки истории: $error'
      : 'Error loading history: $error';
}