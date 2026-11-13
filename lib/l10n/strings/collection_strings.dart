import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

/// Shared by the collection tile and the collection details sheet.
class CollectionStrings extends AppStrings {
  const CollectionStrings(super.isRu);

  factory CollectionStrings.of(BuildContext context) =>
      CollectionStrings(AppStrings.isRussian(context));

  String get retry => isRu ? 'Повторить' : 'Retry';
  String titles(String count) => isRu ? '$count тайтлов' : '$count titles';
  String get empty => isRu ? 'В коллекции нет тайтлов' : 'No titles in collection';
  String get user => isRu ? 'Пользователь' : 'User';
  String get view => isRu ? 'Открыть' : 'View';
}