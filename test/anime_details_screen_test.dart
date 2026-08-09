import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/anime_details_screen.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('episode action layout fits a 1080p TV canvas', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const anime = AnimeSummary(
      id: 1,
      title: 'The Example Hero and the Long Adventure Title',
      description:
          'A detailed synopsis that explains the story, its characters, and '
          'the challenges they face across a long television season.',
      episodes: 24,
      score: 8.4,
      genres: ['Action', 'Adventure', 'Fantasy'],
      format: 'TV',
      status: 'RELEASING',
      durationMinutes: 24,
      relatedAnime: [
        RelatedAnime(
          relationType: 'SEQUEL',
          anime: AnimeSummary(
            id: 2,
            title: 'The Example Hero Season 2',
            description: '',
            episodes: 12,
            score: 8.1,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animeDetailsProvider.overrideWith((_, _) async => anime),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: AnimeDetailsScreen(animeId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Play from beginning'), findsOneWidget);
    expect(find.text('Start watching'), findsOneWidget);
    expect(find.text('Episode 1 of 24'), findsOneWidget);
    expect(find.text('Related series'), findsOneWidget);
    expect(find.text('RELATED'), findsNothing);
    expect(find.text('The Example Hero Season 2'), findsNothing);
    expect(find.text('Episodes'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AspectRatio && (widget.aspectRatio - 2 / 3).abs() < .001,
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('episode action layout scales up on a full HD TV canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const anime = AnimeSummary(
      id: 1,
      title: 'Black Torch',
      description:
          'A detailed synopsis that remains readable beside the poster and '
          'playback controls on a full resolution television layout.',
      episodes: 24,
      score: 7.8,
      genres: ['Action', 'Adventure', 'Fantasy'],
      format: 'TV',
      status: 'RELEASING',
      durationMinutes: 24,
      seasonYear: 2026,
      staff: [AnimePerson(id: 10, name: 'Example Director')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animeDetailsProvider.overrideWith((_, _) async => anime),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: AnimeDetailsScreen(animeId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EPISODE 1 OF 24'), findsOneWidget);
    expect(find.text('Start watching'), findsOneWidget);
    expect(find.text('Play from beginning'), findsOneWidget);
    expect(find.text('Play selected'), findsOneWidget);
    expect(find.text('Cast & crew'), findsOneWidget);
    expect(find.text('2026'), findsWidgets);
    expect(find.text('24m'), findsWidgets);
    expect(find.text('7.8 / 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets(
      'episode action layout fits mobile ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const anime = AnimeSummary(
          id: 1,
          title: 'A Long Example Anime Title for a Small Mobile Screen',
          description:
              'A synopsis that remains readable while the compact page scrolls '
              'instead of forcing the television columns into a phone viewport.',
          episodes: 12,
          score: 8.2,
          genres: ['Action', 'Adventure', 'Fantasy'],
          format: 'TV',
          status: 'RELEASING',
          durationMinutes: 24,
          seasonYear: 2026,
          relatedAnime: [
            RelatedAnime(
              relationType: 'SEQUEL',
              anime: AnimeSummary(
                id: 2,
                title: 'Example Season Two',
                description: '',
                episodes: 12,
                score: 8,
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              animeDetailsProvider.overrideWith((_, _) async => anime),
              trackingHomeProvider.overrideWith(
                (_) async => const TrackingHomeData(
                  watching: [],
                  planToWatch: [],
                  completed: [],
                ),
              ),
            ],
            child: const MaterialApp(home: AnimeDetailsScreen(animeId: 1)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Start watching'), findsOneWidget);
        expect(find.text('Play from beginning'), findsOneWidget);
        expect(find.text('Play selected'), findsOneWidget);
        expect(find.text('Related series'), findsOneWidget);
        expect(find.text('EP 1 / 12'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
