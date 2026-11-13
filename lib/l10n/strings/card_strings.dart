import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class CardStrings extends AppStrings {
  const CardStrings(super.isRu);

  factory CardStrings.of(BuildContext context) =>
      CardStrings(AppStrings.isRussian(context));

  String get reading => isRu ? 'Читаю' : 'Reading';
  String get planToRead => isRu ? 'В планах' : 'Plan to Read';
  String get completed => isRu ? 'Прочитано' : 'Completed';
  String get favorites => isRu ? 'Любимое' : 'Favorites';
  String get dropped => isRu ? 'Брошено' : 'Dropped';
  String get onHold => isRu ? 'Отложено' : 'On Hold';
}