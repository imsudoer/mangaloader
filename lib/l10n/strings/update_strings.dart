import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class UpdateStrings extends AppStrings {
  const UpdateStrings(super.isRu);

  factory UpdateStrings.of(BuildContext context) =>
      UpdateStrings(AppStrings.isRussian(context));

  String get updateAvailable =>
      isRu ? 'Доступно обновление' : 'Update Available';
  String get close => isRu ? 'Закрыть' : 'Close';
  String get whatsNew => isRu ? 'Список изменений:' : "What's new:";
  String get downloading => isRu ? 'Загрузка обновления...' : 'Downloading update...';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get downloaded => isRu
      ? 'Файл обновления успешно загружен'
      : 'Update file downloaded successfully';
  String get installFailed => isRu
      ? 'Не удалось запустить установщик'
      : 'Failed to launch installer';
  String get installUpdate => isRu ? 'Установить обновление' : 'Install Update';
  String downloadFailed(String error) =>
      isRu ? 'Ошибка загрузки: $error' : 'Download failed: $error';
  String get retryDownload => isRu ? 'Повторить загрузку' : 'Retry Download';
  String downloadAndInstall(String sizeLabel) => isRu
      ? 'Скачать и установить$sizeLabel'
      : 'Download and Install$sizeLabel';
  String get githubRelease => isRu ? 'GitHub релиз' : 'GitHub Release';
  String get later => isRu ? 'Позже' : 'Later';
}