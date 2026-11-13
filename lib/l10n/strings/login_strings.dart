import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class LoginStrings extends AppStrings {
  const LoginStrings(super.isRu);

  factory LoginStrings.of(BuildContext context) =>
      LoginStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'Вход в MangaLib' : 'MangaLib Login';
  String get pasteCookieTooltip =>
      isRu ? 'Вставить Cookie вручную' : 'Paste Cookie manually';
  String get loginSuccess => isRu
      ? 'Успешный вход в аккаунт MangaLib!'
      : 'MangaLib login successful!';
  String get authorization =>
      isRu ? 'Авторизация MangaLib' : 'MangaLib Authorization';
  String get desktopInstructions => isRu
      ? 'Для входа на десктопе откройте страницу авторизации в браузере, пройдите капчу и вставьте сюда Cookie-строку (mangalib_session=...; XSRF-TOKEN=...) или JSON-экспорт cookie:'
      : 'Open login in browser, solve captcha, then paste the Cookie header or the JSON cookie export below:';
  String get openInBrowser => isRu
      ? 'Открыть mangalib.org/ru/front/auth'
      : 'Open in Browser';
  String get saveAndLogin => isRu ? 'Сохранить и войти' : 'Save & Login';
  String get pasteCookie => isRu ? 'Вставить Cookie' : 'Paste Cookie';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get apply => isRu ? 'Применить' : 'Apply';
}