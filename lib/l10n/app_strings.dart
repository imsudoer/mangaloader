import 'package:flutter/widgets.dart';

/// Locale-aware text for one screen. Both languages sit next to each other so a
/// new string cannot ship without the other one.
abstract class AppStrings {
  const AppStrings(this.isRu);

  final bool isRu;

  static bool isRussian(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ru';
}