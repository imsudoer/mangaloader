import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class ShareStrings extends AppStrings {
  const ShareStrings(super.isRu);

  factory ShareStrings.of(BuildContext context) =>
      ShareStrings(AppStrings.isRussian(context));

  String get shareTitle => isRu ? 'Поделиться тайтлом' : 'Share Title Card';
  String get shareText =>
      isRu ? 'Читайте в MangaLoader!' : 'Read on MangaLoader!';
  String createFailed(String error) =>
      isRu ? 'Ошибка создания карточки: $error' : 'Failed to create card: $error';
  String chaptersCount(String count) =>
      isRu ? '$count глав' : '$count chapters';
  String get linkOnly => isRu ? 'Только ссылка' : 'Link only';
  String get shareCard => isRu ? 'Поделиться карточкой' : 'Share Card';
}