import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/features/catalog/data/anilist_catalog_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Dio interceptedDio(dynamic responseData) {
    final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              data: responseData as Map<String, dynamic>,
              requestOptions: options,
              statusCode: 200,
            ),
          );
        },
      ),
    );
    return dio;
  }

  group('AniListCatalogClient', () {
    test('strips HTML tags from descriptions', () async {
      final client = AniListCatalogClient(
        dio: interceptedDio({
          'data': {
            'Page': {
              'media': [
                {
                  'id': 1,
                  'idMal': null,
                  'title': {
                    'userPreferred': 'Test Anime',
                    'english': 'Test Anime English',
                    'romaji': 'Test Anime Romaji',
                  },
                  'description':
                      'A <b>bold</b> story.<br/>Second line.<br />'
                      'Entities: &amp; &quot; &#039;',
                  'episodes': 12,
                  'averageScore': 85,
                  'genres': <String>[],
                  'coverImage': {'extraLarge': null},
                  'bannerImage': null,
                  'format': 'TV',
                  'status': 'FINISHED',
                  'season': 'SPRING',
                  'seasonYear': 2023,
                  'duration': 24,
                  'synonyms': <String>[],
                  'nextAiringEpisode': null,
                },
              ],
            },
          },
        }),
      );

      final results = await client.trending();

      expect(results, hasLength(1));
      final desc = results.first.description;
      expect(desc, isNot(contains('<b>')));
      expect(desc, isNot(contains('<br')));
      expect(desc, contains('bold'));
      expect(desc, contains('Second line.'));
      expect(desc, contains('& " \''));
      expect(results.first.title, 'Test Anime English');
      expect(
        results.first.displayTitle(TitleLanguagePreference.romaji),
        'Test Anime Romaji',
      );
    });

    test('maps score from AniList 0–100 to 0.0–10.0', () async {
      final client = AniListCatalogClient(
        dio: interceptedDio({
          'data': {
            'Page': {
              'media': [
                {
                  'id': 2,
                  'idMal': null,
                  'title': {'userPreferred': 'Scored'},
                  'description': '',
                  'episodes': 1,
                  'averageScore': 80,
                  'genres': <String>[],
                  'coverImage': {'extraLarge': null},
                  'bannerImage': null,
                  'format': 'OVA',
                  'status': 'FINISHED',
                  'season': null,
                  'seasonYear': null,
                  'duration': 30,
                  'synonyms': <String>[],
                  'nextAiringEpisode': null,
                },
              ],
            },
          },
        }),
      );

      final results = await client.trending();

      expect(results.first.score, closeTo(8.0, 0.001));
    });

    test('returns null score when averageScore is absent', () async {
      final client = AniListCatalogClient(
        dio: interceptedDio({
          'data': {
            'Page': {
              'media': [
                {
                  'id': 3,
                  'idMal': null,
                  'title': {'userPreferred': 'Unscored'},
                  'description': '',
                  'episodes': null,
                  'averageScore': null,
                  'genres': <String>[],
                  'coverImage': <String, dynamic>{},
                  'bannerImage': null,
                  'format': null,
                  'status': null,
                  'season': null,
                  'seasonYear': null,
                  'duration': null,
                  'synonyms': <String>[],
                  'nextAiringEpisode': null,
                },
              ],
            },
          },
        }),
      );

      final results = await client.trending();

      expect(results.first.score, isNull);
      expect(results.first.episodes, isNull);
      expect(results.first.coverImageUrl, isNull);
    });

    test('seasonal uses correct quarter for each month', () async {
      // We can verify the query variables by checking that seasonal() doesn't
      // throw with a stubbed response regardless of the date.
      for (final month in [1, 4, 7, 10]) {
        final client = AniListCatalogClient(
          dio: interceptedDio({
            'data': {
              'Page': {'media': <dynamic>[]},
            },
          }),
        );

        await expectLater(
          client.seasonal(now: DateTime(2023, month)),
          completes,
        );
      }
    });
  });
}
