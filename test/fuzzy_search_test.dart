import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/utils/fuzzy_search.dart';

void main() {
  group('normalizeForSearch', () {
    test('folds case, ё and punctuation', () {
      expect(normalizeForSearch('  Ёжик — в тумане! '), 'ежик в тумане');
    });

    test('keeps numbers and collapses spaces', () {
      expect(normalizeForSearch('Глава   12.5'), 'глава 12 5');
    });
  });

  group('fuzzyScore', () {
    test('exact and prefix matches rank highest', () {
      expect(fuzzyScore('Токийский гуль', 'токийский гуль'), 100);
      expect(fuzzyScore('Токийский гуль', 'токий'), 90);
      expect(fuzzyScore('Токийский гуль: re', 'гуль'), 80);
    });

    test('matches tokens in any order', () {
      expect(fuzzyScore('Эта фарфоровая кукла влюбилась', 'кукла фарфоровая'), 60);
    });

    test('tolerates a typo in a long word', () {
      expect(
        fuzzyScore('Эта фарфоровая кукла влюбилась', 'фарфоравая кукла'),
        greaterThan(0),
      );
    });

    test('accepts a Latin transliteration of a Cyrillic title', () {
      expect(fuzzyScore('Токийский гуль', 'tokijskij gul'), greaterThan(0));
      expect(fuzzyScore('Токийский гуль', 'tokijskii'), greaterThan(0));
    });

    test('does not match an unrelated word', () {
      expect(fuzzyScore('Токийский гуль', 'наруто'), 0);
      expect(fuzzyScore('Кукла', 'фарфоровая'), 0);
    });

    test('empty query is not a match', () {
      expect(fuzzyScore('Токийский гуль', '   '), 0);
      expect(fuzzyScore('', 'гуль'), 0);
    });
  });

  group('fuzzyFilter', () {
    test('drops non-matches and sorts the strongest first', () {
      final titles = [
        'Токийский гуль: re',
        'Наруто',
        'Токийский гуль',
      ];
      final result = fuzzyFilter(titles, 'токийский гуль', (t) => t);
      expect(result, ['Токийский гуль', 'Токийский гуль: re']);
    });

    test('returns the original list for an empty query', () {
      final titles = ['Наруто'];
      expect(identical(fuzzyFilter(titles, '  ', (t) => t), titles), isTrue);
    });
  });
}