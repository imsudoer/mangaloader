import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/services/content_filter.dart';

void main() {
  group('ContentFilter', () {
    test('blocks Tokyo Ghoul variations', () {
      final variations = [
        'Токийский гуль',
        'токийский гуль',
        'ТОКИЙСКИЙ ГУЛЬ',
        'Токийский Гуль: Перерождение',
        'Токийский гуль:re',
        'Tokyo Ghoul',
        'tokyo ghoul',
        'TOKYO GHOUL',
        'tokyo-ghoul',
        'tokyoghoul',
        '7580--tokyo-ghoul-re',
        'tokiyskiy-gul',
      ];

      for (final text in variations) {
        expect(
          ContentFilter.isBlockedText(text, forceCheck: true),
          isTrue,
          reason: 'Failed to block "$text"',
        );
      }
    });

    test('blocks Death Note variations', () {
      final variations = [
        'Тетрадь смерти',
        'тетрадь смерти',
        'ТЕТРАДЬ СМЕРТИ',
        'Тетрадь смерти: Истории',
        'Death Note',
        'death note',
        'DEATH NOTE',
        'death-note',
        'deathnote',
        '1234--death-note-short-stories',
        'tetrad-smerti',
      ];

      for (final text in variations) {
        expect(
          ContentFilter.isBlockedText(text, forceCheck: true),
          isTrue,
          reason: 'Failed to block "$text"',
        );
      }
    });

    test('blocks Elfen Lied, Inuyashiki, Interspecies Reviewers', () {
      final variations = [
        'Эльфийская песнь',
        'elfen lied',
        'elfen-lied',
        'Инуяшики',
        'inuyashiki',
        'Межвидовые рецензенты',
        'ishuzoku reviewers',
      ];

      for (final text in variations) {
        expect(
          ContentFilter.isBlockedText(text, forceCheck: true),
          isTrue,
          reason: 'Failed to block "$text"',
        );
      }
    });

    test('does NOT block permitted popular manga', () {
      final permitted = [
        'Берсерк',
        'Berserk',
        'Solo Leveling',
        'Поднятие уровня в одиночку',
        'Ван Пис',
        'One Piece',
        'Наруто',
        'Naruto',
        'Блич',
        'Bleach',
        'Человек-бензопила',
        'Chainsaw Man',
        'Магическая битва',
        'Jujutsu Kaisen',
        'Атака титанов',
        'Attack on Titan',
      ];

      for (final text in permitted) {
        expect(
          ContentFilter.isBlockedText(text, forceCheck: true),
          isFalse,
          reason: 'Incorrectly blocked "$text"',
        );
      }
    });

    test('does NOT block anything when not in RuStore build (forceCheck false)', () {
      expect(ContentFilter.isBlockedText('Токийский гуль'), isFalse);
      expect(ContentFilter.isBlockedText('Death Note'), isFalse);
      expect(ContentFilter.isBlockedText('Тетрадь смерти'), isFalse);
      expect(ContentFilter.isBlockedText('Tokyo Ghoul'), isFalse);
    });
  });
}
