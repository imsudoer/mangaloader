/// Plural forms for the two supported languages.
///
/// Russian needs three forms (1 день / 2 дня / 5 дней), English needs two
/// (1 day / 2 days). Keeping the rules in one place stops the hand written
/// ternaries from drifting apart across screens.
class Plural {
  const Plural._();

  static bool isRu(String languageCode) => languageCode == 'ru';

  /// Picks the Russian form for [count].
  static String ru(
    int count, {
    required String one,
    required String few,
    required String many,
  }) {
    final mod100 = count.abs() % 100;
    if (mod100 >= 11 && mod100 <= 14) return many;
    switch (mod100 % 10) {
      case 1:
        return one;
      case 2:
      case 3:
      case 4:
        return few;
      default:
        return many;
    }
  }

  static String en(int count, {required String one, required String many}) =>
      count.abs() == 1 ? one : many;

  static String days(int count, String languageCode) {
    if (isRu(languageCode)) {
      return ru(count, one: '$count день', few: '$count дня', many: '$count дней');
    }
    return en(count, one: '$count day', many: '$count days');
  }

  static String hours(int count, String languageCode) {
    if (isRu(languageCode)) {
      return ru(count, one: '$count час', few: '$count часа', many: '$count часов');
    }
    return en(count, one: '$count hour', many: '$count hours');
  }

  static String minutes(int count, String languageCode) {
    if (isRu(languageCode)) {
      return ru(count, one: '$count минута', few: '$count минуты', many: '$count минут');
    }
    return en(count, one: '$count minute', many: '$count minutes');
  }

  static String chapters(int count, String languageCode) {
    if (isRu(languageCode)) {
      return ru(count, one: '$count глава', few: '$count главы', many: '$count глав');
    }
    return en(count, one: '$count chapter', many: '$count chapters');
  }

  static String pages(int count, String languageCode) {
    if (isRu(languageCode)) {
      return ru(count, one: '$count страница', few: '$count страницы', many: '$count страниц');
    }
    return en(count, one: '$count page', many: '$count pages');
  }
}