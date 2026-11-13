import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class CommentsStrings extends AppStrings {
  const CommentsStrings(super.isRu);

  factory CommentsStrings.of(BuildContext context) =>
      CommentsStrings(AppStrings.isRussian(context));

  String get signInToVote =>
      isRu ? 'Войдите в аккаунт, чтобы голосовать' : 'Sign in to vote';
  String get signInToPost => isRu
      ? 'Войдите в аккаунт, чтобы оставить комментарий'
      : 'Sign in to post comments';
  String get signIn => isRu ? 'Войти' : 'Sign In';
  String get commentPosted =>
      isRu ? 'Комментарий опубликован' : 'Comment posted';
  String sendFailed(String error) =>
      isRu ? 'Ошибка отправки: $error' : 'Failed to send comment: $error';

  String get title => isRu ? 'Комментарии' : 'Comments';
  String get sortTop => isRu ? 'Топ' : 'Top';
  String get sortNew => isRu ? 'Новые' : 'New';
  String get retry => isRu ? 'Повторить' : 'Retry';
  String get emptyTitle => isRu ? 'Комментариев пока нет' : 'No comments yet';
  String get emptySubtitle =>
      isRu ? 'Будьте первым, кто оставит комментарий!' : 'Be the first to comment!';

  String replyingTo(String username) =>
      isRu ? 'Ответ для @$username' : 'Replying to @$username';
  String replyHint(String username) =>
      isRu ? 'Ответить @$username...' : 'Reply to @$username...';
  String get writeComment => isRu ? 'Написать комментарий...' : 'Write a comment...';
  String page(String page) => isRu ? 'Стр. $page' : 'P. $page';
  String get reply => isRu ? 'Ответить' : 'Reply';

  String get justNow => isRu ? 'только что' : 'just now';
  String minutesAgo(String minutes) =>
      isRu ? '$minutes мин. назад' : '${minutes}m ago';
  String hoursAgo(String hours) => isRu ? '$hours ч. назад' : '${hours}h ago';
  String daysAgo(String days) => isRu ? '$days дн. назад' : '${days}d ago';
}