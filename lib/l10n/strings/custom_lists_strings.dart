import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class CustomListsStrings extends AppStrings {
  const CustomListsStrings(super.isRu);

  factory CustomListsStrings.of(BuildContext context) =>
      CustomListsStrings(AppStrings.isRussian(context));

  String get title =>
      isRu ? 'Пользовательские списки и теги' : 'Custom Lists & Tags';
  String get newList => isRu ? 'Новый список' : 'New List';
  String get createListTooltip => isRu ? 'Создать список' : 'New List';
  String get listNameHint =>
      isRu ? 'Название списка (напр. Шедевры)' : 'List name (e.g. Masterpieces)';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get create => isRu ? 'Создать' : 'Create';
  String get personalLists =>
      isRu ? 'Персональные списки:' : 'Personal Lists:';
  String get emptyLists => isRu
      ? 'Списков пока нет. Нажмите + чтобы создать!'
      : 'No custom lists yet. Tap + to create one!';
  String get personalTags => isRu ? 'Персональные теги:' : 'Personal Tags:';
  String get addTag => isRu ? '+ Добавить тег' : '+ Add tag';
}