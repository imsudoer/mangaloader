import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class ContinueReadingStrings extends AppStrings {
  const ContinueReadingStrings(super.isRu);

  factory ContinueReadingStrings.of(BuildContext context) =>
      ContinueReadingStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'Продолжить чтение' : 'Continue Reading';
  String get subtitle =>
      isRu ? 'Ваш текущий прогресс' : 'Your recent reading progress';
  String get library => isRu ? 'Библиотека' : 'Library';
  String unread(String count) =>
      isRu ? '$count не прочит.' : '$count unread';
}