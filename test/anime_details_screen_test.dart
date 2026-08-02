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
    expect(find.text('Episode 1 / 24'), findsOneWidget);
    expect(find.text('RELATED'), findsOneWidget);
    expect(find.text('The Example Hero Season 2'), findsOneWidget);
    expect(find.text('Episodes'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
