import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class UserSearchStrings extends AppStrings {
  const UserSearchStrings(super.isRu);

  factory UserSearchStrings.of(BuildContext context) =>
      UserSearchStrings(AppStrings.isRussian(context));

  String get title =>
      isRu ? 'Поиск пользователей MangaLib' : 'Search MangaLib Users';
  String get searchHint => isRu ? 'Введите никнейм...' : 'Enter username...';
  String get emptyPrompt => isRu
      ? 'Введите никнейм для поиска пользователей'
      : 'Search for users by username';
  String joined(String date) => isRu ? 'Регистрация: $date' : 'Joined: $date';
  String loginStreak(String streak) =>
      isRu ? 'Стрик входа: $streak дн.' : 'Login Streak: $streak days';
  String get close => isRu ? 'Закрыть' : 'Close';
  String get bookmarks => isRu ? 'Закладки' : 'Bookmarks';
  String bookmarksOf(String username) =>
      isRu ? 'Закладки: $username' : 'Bookmarks: $username';
  String get noBookmarks => isRu
      ? 'Закладки пользователя скрыты или пусты'
      : 'No public bookmarks found';
}