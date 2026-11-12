import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/utils/plural.dart';

String _ruDay(int count) => Plural.ru(count, one: 'день', few: 'дня', many: 'дней');

String _enDay(int count) => Plural.en(count, one: 'day', many: 'days');

void main() {
  group('Plural.ru', () {
    test('uses the singular form for 1 and for numbers ending in 1', () {
      expect(_ruDay(1), 'день');
      expect(_ruDay(21), 'день');
      expect(_ruDay(101), 'день');
      expect(_ruDay(1001), 'день');
    });

    test('uses the few form for 2, 3, 4 and numbers ending in them', () {
      expect(_ruDay(2), 'дня');
      expect(_ruDay(3), 'дня');
      expect(_ruDay(4), 'дня');
      expect(_ruDay(22), 'дня');
      expect(_ruDay(103), 'дня');
      expect(_ruDay(204), 'дня');
    });

    test('uses the many form for 5 through 20', () {
      for (var count = 5; count <= 20; count++) {
        expect(_ruDay(count), 'дней', reason: 'expected the many form for $count');
      }
    });

    test('keeps the 11 to 14 exception even though the number ends in 1 to 4', () {
      expect(_ruDay(11), 'дней');
      expect(_ruDay(12), 'дней');
      expect(_ruDay(13), 'дней');
      expect(_ruDay(14), 'дней');
      expect(_ruDay(111), 'дней');
      expect(_ruDay(112), 'дней');
      expect(_ruDay(1011), 'дней');
    });

    test('keys off the last two digits for hundreds', () {
      expect(_ruDay(100), 'дней');
      expect(_ruDay(121), 'день');
      expect(_ruDay(122), 'дня');
      expect(_ruDay(200), 'дней');
    });

    test('zero and negative counts never throw', () {
      expect(_ruDay(0), 'дней');
      expect(_ruDay(-1), 'день');
      expect(_ruDay(-2), 'дня');
      expect(_ruDay(-5), 'дней');
      expect(_ruDay(-11), 'дней');
      expect(_ruDay(-21), 'день');
    });
  });

  group('Plural.en', () {
    test('uses the singular form only for 1', () {
      expect(_enDay(1), 'day');
      expect(_enDay(-1), 'day');
    });

    test('uses the plural form for zero, two and larger counts', () {
      expect(_enDay(0), 'days');
      expect(_enDay(2), 'days');
      expect(_enDay(11), 'days');
      expect(_enDay(21), 'days');
      expect(_enDay(-2), 'days');
    });
  });

  group('Plural.days', () {
    test('Russian day forms', () {
      expect(Plural.days(1, 'ru'), '1 день');
      expect(Plural.days(2, 'ru'), '2 дня');
      expect(Plural.days(5, 'ru'), '5 дней');
      expect(Plural.days(11, 'ru'), '11 дней');
      expect(Plural.days(21, 'ru'), '21 день');
      expect(Plural.days(101, 'ru'), '101 день');
      expect(Plural.days(111, 'ru'), '111 дней');
    });

    test('English day forms', () {
      expect(Plural.days(1, 'en'), '1 day');
      expect(Plural.days(0, 'en'), '0 days');
      expect(Plural.days(2, 'en'), '2 days');
      expect(Plural.days(21, 'en'), '21 days');
    });

    test('a language code other than ru falls back to English forms', () {
      expect(Plural.days(1, 'de'), '1 day');
      expect(Plural.days(3, 'uk'), '3 days');
    });
  });

  group('Plural.chapters', () {
    test('Russian chapter forms', () {
      expect(Plural.chapters(1, 'ru'), '1 глава');
      expect(Plural.chapters(3, 'ru'), '3 главы');
      expect(Plural.chapters(5, 'ru'), '5 глав');
      expect(Plural.chapters(11, 'ru'), '11 глав');
      expect(Plural.chapters(21, 'ru'), '21 глава');
      expect(Plural.chapters(22, 'ru'), '22 главы');
      expect(Plural.chapters(101, 'ru'), '101 глава');
      expect(Plural.chapters(111, 'ru'), '111 глав');
    });

    test('English chapter forms', () {
      expect(Plural.chapters(1, 'en'), '1 chapter');
      expect(Plural.chapters(0, 'en'), '0 chapters');
      expect(Plural.chapters(2, 'en'), '2 chapters');
      expect(Plural.chapters(11, 'en'), '11 chapters');
      expect(Plural.chapters(21, 'en'), '21 chapters');
    });

    test('Russian chapter forms handle zero and negative counts', () {
      expect(Plural.chapters(0, 'ru'), '0 глав');
      expect(Plural.chapters(-1, 'ru'), '-1 глава');
      expect(Plural.chapters(-3, 'ru'), '-3 главы');
      expect(Plural.chapters(-5, 'ru'), '-5 глав');
    });
  });

  group('Plural.pages', () {
    test('Russian page forms', () {
      expect(Plural.pages(1, 'ru'), '1 страница');
      expect(Plural.pages(3, 'ru'), '3 страницы');
      expect(Plural.pages(5, 'ru'), '5 страниц');
      expect(Plural.pages(11, 'ru'), '11 страниц');
      expect(Plural.pages(21, 'ru'), '21 страница');
      expect(Plural.pages(22, 'ru'), '22 страницы');
      expect(Plural.pages(111, 'ru'), '111 страниц');
    });

    test('English page forms', () {
      expect(Plural.pages(1, 'en'), '1 page');
      expect(Plural.pages(0, 'en'), '0 pages');
      expect(Plural.pages(3, 'en'), '3 pages');
      expect(Plural.pages(11, 'en'), '11 pages');
      expect(Plural.pages(21, 'en'), '21 pages');
    });

    test('Russian page forms handle zero and negative counts', () {
      expect(Plural.pages(0, 'ru'), '0 страниц');
      expect(Plural.pages(-1, 'ru'), '-1 страница');
      expect(Plural.pages(-2, 'ru'), '-2 страницы');
      expect(Plural.pages(-12, 'ru'), '-12 страниц');
    });
  });

  group('Plural.hours and Plural.minutes', () {
    test('Russian hour forms', () {
      expect(Plural.hours(1, 'ru'), '1 час');
      expect(Plural.hours(3, 'ru'), '3 часа');
      expect(Plural.hours(5, 'ru'), '5 часов');
      expect(Plural.hours(11, 'ru'), '11 часов');
      expect(Plural.hours(21, 'ru'), '21 час');
    });

    test('Russian minute forms', () {
      expect(Plural.minutes(1, 'ru'), '1 минута');
      expect(Plural.minutes(3, 'ru'), '3 минуты');
      expect(Plural.minutes(5, 'ru'), '5 минут');
      expect(Plural.minutes(11, 'ru'), '11 минут');
      expect(Plural.minutes(21, 'ru'), '21 минута');
    });

    test('English hour and minute forms', () {
      expect(Plural.hours(1, 'en'), '1 hour');
      expect(Plural.hours(2, 'en'), '2 hours');
      expect(Plural.minutes(1, 'en'), '1 minute');
      expect(Plural.minutes(2, 'en'), '2 minutes');
    });
  });
}