import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloader/services/content_filter.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/src/rust/api/models.dart';

const List<String> _blockedTitles = <String>[
  'Токийский гуль',
  'Tokyo Ghoul',
  'Тетрадь смерти',
  'Death Note',
];

const List<String> _allowedTitles = <String>['Берсерк', 'Berserk', 'Ван-Пис'];

const String _ruStoreSkipReason =
    'RUSTORE_BUILD is defined, so content filtering is always active';

MangaSearchResult _searchResult({
  int id = 1,
  String name = 'Берсерк',
  String rusName = 'Берсерк',
  String engName = 'Berserk',
  String slug = 'berserk',
  String slugUrl = '5678--berserk',
}) {
  return MangaSearchResult(
    id: id,
    name: name,
    rusName: rusName,
    engName: engName,
    slug: slug,
    slugUrl: slugUrl,
    coverUrl: '',
    coverThumbUrl: '',
    mangaType: 'manga',
    typeId: 1,
    status: 'ongoing',
    statusId: 1,
    ageRestriction: '16+',
    ratingAverage: '9.0',
    ratingVotes: '1000',
  );
}

MangaDetails _details({
  int id = 1,
  String name = 'Берсерк',
  String rusName = 'Берсерк',
  String engName = 'Berserk',
  String slug = 'berserk',
  String slugUrl = '5678--berserk',
}) {
  return MangaDetails(
    id: id,
    name: name,
    rusName: rusName,
    engName: engName,
    slug: slug,
    slugUrl: slugUrl,
    coverUrl: '',
    coverThumbUrl: '',
    mangaType: 'manga',
    typeId: 1,
    status: 'ongoing',
    statusId: 1,
    ageRestriction: '16+',
    ratingAverage: '9.0',
    ratingVotes: '1000',
    summary: 'Тёмное фэнтези о мече и судьбе.',
    genres: const <Genre>[],
    tags: const <Tag>[],
    authors: const <Person>[],
    artists: const <Person>[],
    viewsTotal: '100000',
    viewsFormatted: '100K',
    chaptersCount: 380,
    formatLabels: const <String>['Манга'],
  );
}

LibraryEntry _libraryEntry({
  int mangaId = 1,
  String name = 'Берсерк',
  String rusName = 'Берсерк',
  String slugUrl = '5678--berserk',
  ListType listType = ListType.reading,
}) {
  return LibraryEntry(
    mangaId: mangaId,
    slugUrl: slugUrl,
    name: name,
    rusName: rusName,
    coverUrl: '',
    listType: listType,
    addedAt: '2026-01-01T00:00:00Z',
    unreadCount: 0,
    ratingAverage: '9.0',
    totalChapters: 380,
    readChapters: 0,
  );
}

ContinueReadingItem _continueReadingItem({
  int mangaId = 1,
  String name = 'Берсерк',
  String rusName = 'Берсерк',
  String slugUrl = '5678--berserk',
}) {
  return ContinueReadingItem(
    mangaId: mangaId,
    slugUrl: slugUrl,
    name: name,
    rusName: rusName,
    coverUrl: '',
    lastReadVolume: '1',
    lastReadChapter: '3',
    lastReadAt: '2026-01-01T00:00:00Z',
    totalChapters: 380,
    readChapters: 3,
    unreadCount: 377,
    hasNewChapters: false,
    newChaptersCount: 0,
  );
}

DownloadedMangaGroup _downloadGroup({
  int mangaId = 1,
  String name = 'Берсерк',
  String rusName = 'Берсерк',
  String slugUrl = '5678--berserk',
  List<DownloadedChapterInfo> chapters = const <DownloadedChapterInfo>[
    DownloadedChapterInfo(
      id: 1,
      mangaId: 1,
      volume: '1',
      number: '1',
      pageCount: 24,
      downloadPath: '/downloads/berserk/1',
      downloadedAt: '2026-01-01T00:00:00Z',
    ),
  ],
}) {
  return DownloadedMangaGroup(
    mangaId: mangaId,
    slugUrl: slugUrl,
    name: name,
    rusName: rusName,
    coverUrl: '',
    chapters: chapters,
    totalSizeBytes: 1048576,
  );
}

RecapMangaItem _recapItem({
  int mangaId = 1,
  String name = 'Берсерк',
  String rusName = 'Берсерк',
}) {
  return RecapMangaItem(
    mangaId: mangaId,
    name: name,
    rusName: rusName,
    coverUrl: '',
    chaptersRead: 12,
  );
}

MangaCollectionItem _collectionItem({
  int id = 1,
  String name = 'Лучшее тёмное фэнтези',
  String description = 'Подборка про приключения и мечи.',
}) {
  return MangaCollectionItem(
    id: id,
    name: name,
    description: description,
    typeName: 'Коллекция',
    views: 100,
    favoritesCount: 10,
    itemsCount: 20,
    commentsCount: 2,
    votesUp: 30,
    votesDown: 1,
    userId: 7,
    username: 'reader',
    userAvatar: '',
    createdAt: '2026-01-01T00:00:00Z',
  );
}

void main() {
  group('ContentFilter typed matchers', () {
    group('isBlockedSearchResult', () {
      test('blocks a prohibited title in every identifying field', () {
        for (final title in _blockedTitles) {
          final variants = <String, MangaSearchResult>{
            'name': _searchResult(name: title),
            'rusName': _searchResult(rusName: title),
            'engName': _searchResult(engName: title),
            'slug': _searchResult(slug: title),
            'slugUrl': _searchResult(slugUrl: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedSearchResult(entry.value, forceCheck: true),
              isTrue,
              reason: 'search result field "${entry.key}" with "$title" must block',
            );
          }
        }
      });

      test('permits allowed titles in every identifying field', () {
        for (final title in _allowedTitles) {
          final variants = <String, MangaSearchResult>{
            'name': _searchResult(name: title),
            'rusName': _searchResult(rusName: title),
            'engName': _searchResult(engName: title),
            'slug': _searchResult(slug: title),
            'slugUrl': _searchResult(slugUrl: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedSearchResult(entry.value, forceCheck: true),
              isFalse,
              reason: 'search result field "${entry.key}" with "$title" must pass',
            );
          }
        }
      });
    });

    group('isBlockedDetails', () {
      test('blocks a prohibited title in every identifying field', () {
        for (final title in _blockedTitles) {
          final variants = <String, MangaDetails>{
            'name': _details(name: title),
            'rusName': _details(rusName: title),
            'engName': _details(engName: title),
            'slug': _details(slug: title),
            'slugUrl': _details(slugUrl: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedDetails(entry.value, forceCheck: true),
              isTrue,
              reason: 'details field "${entry.key}" with "$title" must block',
            );
          }
        }
      });

      test('permits allowed titles in every identifying field', () {
        for (final title in _allowedTitles) {
          final variants = <String, MangaDetails>{
            'name': _details(name: title),
            'rusName': _details(rusName: title),
            'engName': _details(engName: title),
            'slug': _details(slug: title),
            'slugUrl': _details(slugUrl: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedDetails(entry.value, forceCheck: true),
              isFalse,
              reason: 'details field "${entry.key}" with "$title" must pass',
            );
          }
        }
      });
    });

    group('isBlockedContinueReading', () {
      test('blocks a prohibited title in every identifying field', () {
        for (final title in _blockedTitles) {
          final variants = <String, ContinueReadingItem>{
            'name': _continueReadingItem(name: title),
            'rusName': _continueReadingItem(rusName: title),
            'slugUrl': _continueReadingItem(slugUrl: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedContinueReading(entry.value, forceCheck: true),
              isTrue,
              reason: 'continue reading field "${entry.key}" with "$title" must block',
            );
          }
        }
      });

      test('permits allowed titles in every identifying field', () {
        for (final title in _allowedTitles) {
          final variants = <String, ContinueReadingItem>{
            'name': _continueReadingItem(name: title),
            'rusName': _continueReadingItem(rusName: title),
            'slugUrl': _continueReadingItem(slugUrl: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedContinueReading(entry.value, forceCheck: true),
              isFalse,
              reason: 'continue reading field "${entry.key}" with "$title" must pass',
            );
          }
        }
      });
    });

    group('isBlockedDownloadGroup', () {
      test('blocks a prohibited title in every identifying field', () {
        for (final title in _blockedTitles) {
          final variants = <String, DownloadedMangaGroup>{
            'name': _downloadGroup(name: title),
            'rusName': _downloadGroup(rusName: title),
            'slugUrl': _downloadGroup(slugUrl: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedDownloadGroup(entry.value, forceCheck: true),
              isTrue,
              reason: 'download group field "${entry.key}" with "$title" must block',
            );
          }
        }
      });

      test('permits allowed titles in every identifying field', () {
        for (final title in _allowedTitles) {
          final variants = <String, DownloadedMangaGroup>{
            'name': _downloadGroup(name: title),
            'rusName': _downloadGroup(rusName: title),
            'slugUrl': _downloadGroup(slugUrl: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedDownloadGroup(entry.value, forceCheck: true),
              isFalse,
              reason: 'download group field "${entry.key}" with "$title" must pass',
            );
          }
        }
      });
    });

    group('isBlockedRecapItem', () {
      test('blocks a prohibited title in every identifying field', () {
        for (final title in _blockedTitles) {
          final variants = <String, RecapMangaItem>{
            'name': _recapItem(name: title),
            'rusName': _recapItem(rusName: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedRecapItem(entry.value, forceCheck: true),
              isTrue,
              reason: 'recap field "${entry.key}" with "$title" must block',
            );
          }
        }
      });

      test('permits allowed titles in every identifying field', () {
        for (final title in _allowedTitles) {
          final variants = <String, RecapMangaItem>{
            'name': _recapItem(name: title),
            'rusName': _recapItem(rusName: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedRecapItem(entry.value, forceCheck: true),
              isFalse,
              reason: 'recap field "${entry.key}" with "$title" must pass',
            );
          }
        }
      });
    });

    group('isBlockedCollection', () {
      test('blocks a prohibited title in every identifying field', () {
        for (final title in _blockedTitles) {
          final variants = <String, MangaCollectionItem>{
            'name': _collectionItem(name: title),
            'description': _collectionItem(description: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedCollection(entry.value, forceCheck: true),
              isTrue,
              reason: 'collection field "${entry.key}" with "$title" must block',
            );
          }
        }
      });

      test('permits allowed titles in every identifying field', () {
        for (final title in _allowedTitles) {
          final variants = <String, MangaCollectionItem>{
            'name': _collectionItem(name: title),
            'description': _collectionItem(description: title),
          };

          for (final entry in variants.entries) {
            expect(
              ContentFilter.isBlockedCollection(entry.value, forceCheck: true),
              isFalse,
              reason: 'collection field "${entry.key}" with "$title" must pass',
            );
          }
        }
      });
    });

    group('isBlockedAny', () {
      test('an empty field list is never blocked', () {
        expect(ContentFilter.isBlockedAny(const <String?>[]), isFalse);
        expect(ContentFilter.isBlockedAny(const <String?>[], forceCheck: true), isFalse);
      });

      test('null and empty fields are treated like a clean title', () {
        expect(ContentFilter.isBlockedText(null, forceCheck: true), isFalse);
        expect(ContentFilter.isBlockedText('', forceCheck: true), isFalse);
        expect(ContentFilter.isBlockedAny(const <String?>[null], forceCheck: true), isFalse);
        expect(
          ContentFilter.isBlockedAny(const <String?>[null, '', 'Berserk'], forceCheck: true),
          isFalse,
        );
        expect(
          ContentFilter.isBlockedAny(const <String?>[null, 'Tokyo Ghoul'], forceCheck: true),
          isTrue,
        );
      });

      test('forceCheck false leaves every matcher inert outside RuStore builds', () {
        expect(ContentFilter.isBlockedSearchResult(_searchResult(name: 'Tokyo Ghoul')), isFalse);
        expect(ContentFilter.isBlockedDetails(_details(rusName: 'Тетрадь смерти')), isFalse);
        expect(
          ContentFilter.isBlockedContinueReading(_continueReadingItem(name: 'Death Note')),
          isFalse,
        );
        expect(ContentFilter.isBlockedDownloadGroup(_downloadGroup(name: 'Tokyo Ghoul')), isFalse);
        expect(ContentFilter.isBlockedRecapItem(_recapItem(name: 'Death Note')), isFalse);
        expect(
          ContentFilter.isBlockedCollection(_collectionItem(description: 'Тетрадь смерти')),
          isFalse,
        );
      }, skip: isRuStoreBuild ? _ruStoreSkipReason : false);
    });
  });

  group('ContentFilter list filters', () {
    test('filterSearchResults drops blocked entries and keeps order', () {
      final input = <MangaSearchResult>[
        _searchResult(id: 1, name: 'Берсерк'),
        _searchResult(id: 2, name: 'Токийский гуль'),
        _searchResult(id: 3, name: 'Ван-Пис'),
        _searchResult(id: 4, name: 'Death Note'),
      ];

      final filtered = ContentFilter.filterSearchResults(input, forceCheck: true);

      expect(filtered.map((item) => item.id), <int>[1, 3]);
    });

    test('filterLibraryEntries drops blocked entries and keeps order', () {
      final input = <LibraryEntry>[
        _libraryEntry(mangaId: 1, name: 'Berserk'),
        _libraryEntry(mangaId: 2, name: 'Tokyo Ghoul'),
        _libraryEntry(mangaId: 3, name: 'Ван-Пис', listType: ListType.completed),
        _libraryEntry(mangaId: 4, name: 'Тетрадь смерти'),
      ];

      final filtered = ContentFilter.filterLibraryEntries(input, forceCheck: true);

      expect(filtered.map((entry) => entry.mangaId), <int>[1, 3]);
      expect(filtered.last.listType, ListType.completed);
    });

    test('filterContinueReading drops blocked entries and keeps order', () {
      final input = <ContinueReadingItem>[
        _continueReadingItem(mangaId: 1, name: 'Берсерк'),
        _continueReadingItem(mangaId: 2, name: 'Death Note'),
        _continueReadingItem(mangaId: 3, name: 'Berserk'),
        _continueReadingItem(mangaId: 4, name: 'Токийский гуль'),
      ];

      final filtered = ContentFilter.filterContinueReading(input, forceCheck: true);

      expect(filtered.map((item) => item.mangaId), <int>[1, 3]);
    });

    test('filterDownloadGroups drops blocked entries and keeps order', () {
      final input = <DownloadedMangaGroup>[
        _downloadGroup(mangaId: 1, name: 'Берсерк'),
        _downloadGroup(mangaId: 2, name: 'Tokyo Ghoul'),
        _downloadGroup(mangaId: 3, name: 'Ван-Пис'),
        _downloadGroup(mangaId: 4, name: 'Тетрадь смерти'),
      ];

      final filtered = ContentFilter.filterDownloadGroups(input, forceCheck: true);

      expect(filtered.map((group) => group.mangaId), <int>[1, 3]);
      expect(filtered.map((group) => group.name), <String>['Берсерк', 'Ван-Пис']);
      expect(filtered.first.chapters, hasLength(1));
    });

    test('filterRecapItems drops blocked entries and keeps order', () {
      final input = <RecapMangaItem>[
        _recapItem(mangaId: 1, name: 'Berserk'),
        _recapItem(mangaId: 2, name: 'Death Note'),
        _recapItem(mangaId: 3, name: 'Берсерк'),
        _recapItem(mangaId: 4, name: 'Токийский гуль'),
      ];

      final filtered = ContentFilter.filterRecapItems(input, forceCheck: true);

      expect(filtered.map((item) => item.mangaId), <int>[1, 3]);
    });

    test('filterCollections drops blocked entries and keeps order', () {
      final input = <MangaCollectionItem>[
        _collectionItem(id: 1, name: 'Лучшее фэнтези'),
        _collectionItem(id: 2, name: 'Tokyo Ghoul'),
        _collectionItem(id: 3, description: 'Про мечи и приключения'),
        _collectionItem(id: 4, name: 'Death Note'),
      ];

      final filtered = ContentFilter.filterCollections(input, forceCheck: true);

      expect(filtered.map((collection) => collection.id), <int>[1, 3]);
    });

    test('filters return the original list untouched when forceCheck is false', () {
      final searchInput = <MangaSearchResult>[_searchResult(name: 'Tokyo Ghoul')];
      final libraryInput = <LibraryEntry>[_libraryEntry(name: 'Tokyo Ghoul')];
      final readingInput = <ContinueReadingItem>[_continueReadingItem(name: 'Tokyo Ghoul')];
      final downloadInput = <DownloadedMangaGroup>[_downloadGroup(name: 'Tokyo Ghoul')];
      final recapInput = <RecapMangaItem>[_recapItem(name: 'Tokyo Ghoul')];
      final collectionInput = <MangaCollectionItem>[_collectionItem(name: 'Tokyo Ghoul')];

      expect(ContentFilter.filterSearchResults(searchInput), same(searchInput));
      expect(ContentFilter.filterLibraryEntries(libraryInput), same(libraryInput));
      expect(ContentFilter.filterContinueReading(readingInput), same(readingInput));
      expect(ContentFilter.filterDownloadGroups(downloadInput), same(downloadInput));
      expect(ContentFilter.filterRecapItems(recapInput), same(recapInput));
      expect(ContentFilter.filterCollections(collectionInput), same(collectionInput));
    }, skip: isRuStoreBuild ? _ruStoreSkipReason : false);
  });

  group('ContentFilter secondary field regression', () {
    test('a clean name with a banned rusName is still blocked', () {
      final item = _searchResult(name: 'Химера', rusName: 'Токийский гуль');
      expect(ContentFilter.isBlockedSearchResult(item, forceCheck: true), isTrue);

      final filtered = ContentFilter.filterSearchResults(
        <MangaSearchResult>[item],
        forceCheck: true,
      );
      expect(filtered, isEmpty);
    });

    test('a clean name with a banned engName is still blocked', () {
      final item = _details(name: 'Химера', engName: 'Death Note');
      expect(ContentFilter.isBlockedDetails(item, forceCheck: true), isTrue);
    });

    test('a clean name with a banned slug is still blocked', () {
      final item = _searchResult(name: 'Химера', slug: 'tokyo-ghoul-re');
      expect(ContentFilter.isBlockedSearchResult(item, forceCheck: true), isTrue);
    });

    test('a clean name with a banned slugUrl is still blocked in every list', () {
      final search = _searchResult(id: 1, name: 'Химера', slugUrl: '7580--tokyo-ghoul-re');
      final library = _libraryEntry(mangaId: 1, name: 'Химера', slugUrl: '1234--death-note');
      final reading = _continueReadingItem(mangaId: 1, name: 'Химера', slugUrl: 'death-note');
      final download = _downloadGroup(mangaId: 1, name: 'Химера', slugUrl: 'tokyo-ghoul');

      expect(ContentFilter.isBlockedSearchResult(search, forceCheck: true), isTrue);
      expect(ContentFilter.isBlockedText(library.slugUrl, forceCheck: true), isTrue);
      expect(ContentFilter.isBlockedContinueReading(reading, forceCheck: true), isTrue);
      expect(ContentFilter.isBlockedDownloadGroup(download, forceCheck: true), isTrue);

      expect(
        ContentFilter.filterSearchResults(<MangaSearchResult>[search], forceCheck: true),
        isEmpty,
      );
      expect(
        ContentFilter.filterLibraryEntries(<LibraryEntry>[library], forceCheck: true),
        isEmpty,
      );
      expect(
        ContentFilter.filterContinueReading(<ContinueReadingItem>[reading], forceCheck: true),
        isEmpty,
      );
      expect(
        ContentFilter.filterDownloadGroups(<DownloadedMangaGroup>[download], forceCheck: true),
        isEmpty,
      );
    });

    test('a clean name with a banned rusName is still blocked in recap and reading lists', () {
      final recap = _recapItem(mangaId: 1, name: 'Химера', rusName: 'Тетрадь смерти');
      final reading = _continueReadingItem(mangaId: 2, name: 'Химера', rusName: 'Tokyo Ghoul');

      expect(ContentFilter.isBlockedRecapItem(recap, forceCheck: true), isTrue);
      expect(ContentFilter.isBlockedContinueReading(reading, forceCheck: true), isTrue);
      expect(ContentFilter.filterRecapItems(<RecapMangaItem>[recap], forceCheck: true), isEmpty);
      expect(
        ContentFilter.filterContinueReading(<ContinueReadingItem>[reading], forceCheck: true),
        isEmpty,
      );
    });

    test('a collection whose only banned text lives in the description is blocked', () {
      final collection = _collectionItem(
        id: 9,
        name: 'Классика нулевых',
        description: 'Сюда вошла Тетрадь смерти и её продолжения.',
      );

      expect(ContentFilter.isBlockedCollection(collection, forceCheck: true), isTrue);
      expect(ContentFilter.filterCollections(<MangaCollectionItem>[collection], forceCheck: true),
          isEmpty);
    });

    test('mixed lists keep only the allowed items when blocks hide in secondary fields', () {
      final searchInput = <MangaSearchResult>[
        _searchResult(id: 1, name: 'Берсерк'),
        _searchResult(id: 2, name: 'Химера', rusName: 'Tokyo Ghoul'),
        _searchResult(id: 3, name: 'Ван-Пис'),
        _searchResult(id: 4, name: 'Химера', engName: 'Death Note'),
      ];
      final collectionInput = <MangaCollectionItem>[
        _collectionItem(id: 1, name: 'Лучшее фэнтези'),
        _collectionItem(id: 2, name: 'Химера', description: 'Включает Tokyo Ghoul'),
        _collectionItem(id: 3, name: 'Классика'),
        _collectionItem(id: 4, name: 'Химера', description: 'Включает Тетрадь смерти'),
      ];

      final filteredSearch = ContentFilter.filterSearchResults(searchInput, forceCheck: true);
      final filteredCollections =
          ContentFilter.filterCollections(collectionInput, forceCheck: true);

      expect(filteredSearch.map((item) => item.id), <int>[1, 3]);
      expect(filteredCollections.map((item) => item.id), <int>[1, 3]);
    });
  });
}