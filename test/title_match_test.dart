import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/utils/title_match.dart';

void main() {
  group('editionKindOf', () {
    test('detects novels', () {
      expect(editionKindOf('Ранобэ'), EditionKind.novel);
      expect(editionKindOf('Ранобэ (Novel)'), EditionKind.novel);
      expect(editionKindOf('Light Novel'), EditionKind.novel);
      expect(editionKindOf('новелла'), EditionKind.novel);
    });

    test('detects comics', () {
      expect(editionKindOf('Манга'), EditionKind.manga);
      expect(editionKindOf('Манхва'), EditionKind.manga);
      expect(editionKindOf('Маньхуа'), EditionKind.manga);
      expect(editionKindOf('Руманга'), EditionKind.manga);
      expect(editionKindOf('Comic'), EditionKind.manga);
    });

    test('everything else stays unknown', () {
      expect(editionKindOf('Сингл'), EditionKind.other);
      expect(editionKindOf(''), EditionKind.other);
      expect(editionKindOf('Дорама'), EditionKind.other);
    });
  });

  group('normalizeTitle', () {
    test('lowercases and strips punctuation', () {
      expect(normalizeTitle('  Берсерк: Золотой век! '), 'берсерк золотой век');
      expect(normalizeTitle('Solo Leveling'), 'solo leveling');
    });

    test('keeps letters of any alphabet and digits', () {
      expect(normalizeTitle('Наруто 2'), 'наруто 2');
      expect(normalizeTitle('進撃の巨人'), '進撃の巨人');
    });
  });

  group('titleBase', () {
    test('cuts the subtitle after a colon', () {
      expect(titleBase('Токийский гуль: re'), 'токийский гуль');
      expect(titleBase('Berserk: The Golden Age'), 'berserk');
    });

    test('cuts the parenthesised part', () {
      expect(titleBase('Берсерк (ранобэ)'), 'берсерк');
    });

    test('keeps short separators inside the title', () {
      expect(titleBase('Re:Zero'), 're zero');
    });
  });

  group('isSameStoryTitles', () {
    test('matches a title and its sequel suffix', () {
      expect(isSameStoryTitles('Токийский гуль', 'Токийский гуль: re'), isTrue);
      expect(isSameStoryTitles('Берсерк', 'Берсерк (новелла)'), isTrue);
    });

    test('matches a long title with a short suffix', () {
      expect(isSameStoryTitles('Реинкарнация', 'Реинкарнация том 2'), isTrue);
    });

    test('rejects different stories', () {
      expect(isSameStoryTitles('Берсерк', 'Блич'), isFalse);
      expect(isSameStoryTitles('Наруто', 'Наруто Сипуден Долгое Название'), isFalse);
    });

    test('rejects titles that are too short to compare', () {
      expect(isSameStoryTitles('Я', 'Я'), isFalse);
      expect(isSameStoryTitles('', 'Берсерк'), isFalse);
    });
  });

  group('primaryTitle', () {
    test('prefers the russian title', () {
      expect(
        primaryTitle(name: 'Berserk', rusName: 'Берсерк', engName: 'Berserk'),
        'Берсерк',
      );
    });

    test('falls back to the original name and then english', () {
      expect(
        primaryTitle(name: 'Berserk', rusName: '  ', engName: 'Berserk EN'),
        'Berserk',
      );
      expect(
        primaryTitle(name: '  ', rusName: '', engName: 'Berserk EN'),
        'Berserk EN',
      );
    });
  });
}