import 'package:anime_tv/app/app.dart';
import 'package:anime_tv/core/layout/interface_scaling.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/home/presentation/home_screen.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses denser canvases as physical TV resolution increases', () {
    expect(tvCanvasWidthForPhysicalPixels(1920), 960);
    expect(tvCanvasWidthForPhysicalPixels(2560), 1280);
    expect(tvCanvasWidthForPhysicalPixels(3840), 1600);
  });

  testWidgets('renders the TV home shell', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(3840, 2160);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          seasonalAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          trackingHomeProvider.overrideWith(
            (_) => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const TetoTvApp(),
      ),
    );
    await tester.pump();

    expect(find.text('TetoTV'), findsOneWidget);
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Watch now'), findsOneWidget);
    expect(find.text('My List'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('renders the home shell without overflow on a phone', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          seasonalAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          trackingHomeProvider.overrideWith(
            (_) => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Continue watching'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double activating the in-app Home action refreshes shelves', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) async => const []),
          seasonalAnimeProvider.overrideWith((_) async => const []),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump();

    expect(find.text('Refreshing Home…'), findsOneWidget);
  });

  testWidgets('featured carousel rotates the title and matching metadata', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const first = AnimeSummary(
      id: 1,
      title: 'First Trending Show',
      description: 'First description',
      episodes: 12,
      score: 7.1,
      seasonYear: 2025,
    );
    const second = AnimeSummary(
      id: 2,
      title: 'Second Trending Show',
      description: 'Second description',
      episodes: 24,
      score: 8.8,
      seasonYear: 2026,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) async => [first, second]),
          seasonalAnimeProvider.overrideWith((_) async => const []),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('First Trending Show'), findsOneWidget);
    expect(find.text('First description'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Second Trending Show'), findsWidgets);
    expect(find.text('Second description'), findsOneWidget);
    expect(find.text('First description'), findsNothing);
  });

  testWidgets('home artwork keeps a fixed height across title lengths', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const hero = AnimeSummary(
      id: 1,
      title: 'Hero',
      description: 'Hero',
      episodes: null,
      score: null,
    );
    const short = AnimeSummary(
      id: 2,
      title: 'Short',
      description: 'Short',
      episodes: null,
      score: null,
    );
    const long = AnimeSummary(
      id: 3,
      title: 'A much longer title that needs the reserved second line',
      description: 'Long',
      episodes: null,
      score: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith(
            (_) async => const [hero, short, long],
          ),
          seasonalAnimeProvider.overrideWith((_) async => const []),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final shortArtwork = find.byKey(const ValueKey('home-artwork-2'));
    final longArtwork = find.byKey(const ValueKey('home-artwork-3'));
    expect(shortArtwork, findsOneWidget);
    expect(longArtwork, findsOneWidget);
    expect(
      tester.getSize(shortArtwork).height,
      tester.getSize(longArtwork).height,
    );
  });

  testWidgets(
    'continue watching merges tracker titles with local resume precedence',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        initialSetupCompletedStorageKey: 'true',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final checkpoint = PlaybackCheckpoint(
        anilistMediaId: 101,
        malMediaId: 202,
        episode: 4,
        title: 'Local resume wins',
        position: const Duration(minutes: 8),
        duration: const Duration(minutes: 24),
        updatedAt: DateTime(2026, 8, 9),
      );
      const watching = [
        HomeTrackedAnime(
          tracked: TrackedAnime(
            mediaId: 101,
            title: 'AniList duplicate must be hidden',
            status: TrackingListStatus.watching,
            progress: 3,
          ),
          provider: TrackingProvider.anilist,
          anilistId: 101,
          coverImageUrl: null,
        ),
        HomeTrackedAnime(
          tracked: TrackedAnime(
            mediaId: 202,
            title: 'MAL duplicate must be hidden',
            status: TrackingListStatus.watching,
            progress: 3,
          ),
          provider: TrackingProvider.myAnimeList,
          anilistId: null,
          coverImageUrl: null,
        ),
        HomeTrackedAnime(
          tracked: TrackedAnime(
            mediaId: 303,
            title: 'Distinct AniList title remains',
            status: TrackingListStatus.watching,
            progress: 2,
          ),
          provider: TrackingProvider.anilist,
          anilistId: 303,
          coverImageUrl: null,
        ),
        HomeTrackedAnime(
          tracked: TrackedAnime(
            mediaId: 404,
            title: 'Distinct MAL title remains',
            status: TrackingListStatus.watching,
            progress: 1,
          ),
          provider: TrackingProvider.myAnimeList,
          anilistId: null,
          coverImageUrl: null,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trendingAnimeProvider.overrideWith((_) async => const []),
            seasonalAnimeProvider.overrideWith((_) async => const []),
            trackingHomeProvider.overrideWith(
              (_) async => const TrackingHomeData(
                watching: watching,
                planToWatch: [],
                completed: [],
              ),
            ),
            recentPlaybackProvider.overrideWith((_) async => [checkpoint]),
            dismissedContinueWatchingProvider.overrideWith(
              (_) async => const <int>{},
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Local resume wins'), findsWidgets);
      expect(find.text('AniList duplicate must be hidden'), findsNothing);
      expect(find.text('MAL duplicate must be hidden'), findsNothing);
      expect(find.text('Distinct AniList title remains'), findsOneWidget);
      expect(find.text('Distinct MAL title remains'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fresh installs open setup and can skip it', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          seasonalAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          trackingHomeProvider.overrideWith(
            (_) => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const TetoTvApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up TetoTV'), findsOneWidget);
    expect(find.text('Skip setup'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Set up TetoTV'), findsNothing);
    expect(find.text('TetoTV'), findsOneWidget);
  });
}
