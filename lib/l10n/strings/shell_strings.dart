import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

/// Strings of the persistent shell: bottom navigation and the offline banner.
class ShellStrings extends AppStrings {
  const ShellStrings(super.isRu);

  factory ShellStrings.of(BuildContext context) =>
      ShellStrings(AppStrings.isRussian(context));

  String get home => isRu ? 'Главная' : 'Home';
  String get catalog => isRu ? 'Каталог' : 'Catalog';
  String get library => isRu ? 'Библиотека' : 'Library';
  String get downloads => isRu ? 'Загрузки' : 'Downloads';
  String get profile => isRu ? 'Профиль' : 'Profile';
  String get offlineBanner => isRu
      ? 'Оффлайн-режим — доступны скачанные тайтлы и кэш'
      : 'Offline Mode — downloaded manga and cache available';
}