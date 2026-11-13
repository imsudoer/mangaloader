import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class DownloadButtonStrings extends AppStrings {
  const DownloadButtonStrings(super.isRu);

  factory DownloadButtonStrings.of(BuildContext context) =>
      DownloadButtonStrings(AppStrings.isRussian(context));

  String get retry => isRu ? 'Повтор' : 'Retry';
  String get waiting => isRu ? 'Ожидание' : 'Wait...';
  String get download => isRu ? 'Скачать' : 'Load';
}