import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/data/anilist_catalog_client.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/discover_screen.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:anime_tv/features/tracking/application/my_list_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('discover keeps advanced filters inside a compact dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogClientProvider.overrideWithValue(_FakeCatalog())],
        child: const MaterialApp(home: DiscoverScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'initial screen');

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'opened dialog');

    expect(find.text('Find your next anime'), findsOneWidget);
    expect(
      find.text('Choose only the filters you care about.'),
      findsOneWidget,
    );
    expect(find.text('Genre'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    expect(find.text('Format'), findsOneWidget);
    expect(find.text('Season'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Minimum score'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'scrolled dialog');
    expect(find.text('Include adult titles'), findsOneWidget);
  });

  testWidgets('applying a filter reloads Discover with the selected value', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = _FakeCatalog();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogClientProvider.overrideWithValue(catalog)],
        child: const MaterialApp(home: DiscoverScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All genres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fantasy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();

    expect(catalog.requests, hasLength(2));
    expect(catalog.requests.last.genre, 'Fantasy');
    expect(tester.takeException(), isNull);
  });

  testWidgets('illegal AniList combinations show a useful recovery state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogClientProvider.overrideWithValue(
            _FakeCatalog(
              error: StateError('Illegal operation and value combination'),
            ),
          ),
        ],
        child: const MaterialApp(home: DiscoverScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'AniList rejected that filter combination. Reset the filters or try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reset filters'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.textContaining('Illegal operation'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D-pad traverses filters, applies them, and opens a result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = _FakeCatalog(
      results: const [
        AnimeSummary(
          id: 77,
          title: 'Filtered Result',
          description: '',
          episodes: 12,
          score: 8,
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/discover',
      routes: [
        GoRoute(path: '/discover', builder: (_, _) => const DiscoverScreen()),
        GoRoute(
          path: '/anime/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogClientProvider.overrideWithValue(catalog)],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) => TvShortcuts(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'discover.filters');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'discover.filters.title',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'discover.filters.sort',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'discover.filters.genre',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fantasy').last);
    await tester.pumpAndSettle();

    for (var index = 0; index < 5; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 140));
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'discover.filters.apply',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(catalog.requests.last.genre, 'Fantasy');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'discover.result.first',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Opened 77'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header and first result row return predictably to Filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final results = List.generate(
      10,
      (index) => AnimeSummary(
        id: index + 1,
        title: index == 1
            ? 'A Very Long Anime Title That Must Stay Inside The Focus Ring'
            : 'Result ${index + 1}',
        description: '',
        episodes: 12,
        score: 8,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogClientProvider.overrideWithValue(
            _FakeCatalog(results: results),
          ),
        ],
        child: const MaterialApp(home: TvShortcuts(child: DiscoverScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'discover.filters');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'discover.back');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'discover.filters');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final title = find.text(
      'A Very Long Anime Title That Must Stay Inside The Focus Ring',
    );
    expect(title, findsOneWidget);
    final card = find.ancestor(of: title, matching: find.byType(TvFocusable));
    final cardRect = tester.getRect(card.first);
    final titleRect = tester.getRect(title);
    expect(titleRect.left, greaterThanOrEqualTo(cardRect.left + 7));
    expect(titleRect.right, lessThanOrEqualTo(cardRect.right - 7));
    expect(titleRect.bottom, lessThanOrEqualTo(cardRect.bottom - 7));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'discover.filters');
    expect(tester.takeException(), isNull);
  });

  testWidgets('holding a Discover result can add it to Planning', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      TrackingProvider.anilist.tokenStorageKey: 'anilist-token',
      TrackingProvider.myAnimeList.tokenStorageKey: 'mal-token',
    });
    final repositories = <TrackingProvider, _DiscoverRecordingRepository>{};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogClientProvider.overrideWithValue(
            _FakeCatalog(
              results: const [
                AnimeSummary(
                  id: 88,
                  idMal: 99,
                  title: 'Discover Planning Show',
                  description: '',
                  episodes: 12,
                  score: 8,
                ),
              ],
            ),
          ),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
          trackingRepositoryFactoryProvider.overrideWithValue((provider, _) {
            return repositories.putIfAbsent(
              provider,
              _DiscoverRecordingRepository.new,
            );
          }),
        ],
        child: const MaterialApp(home: DiscoverScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Discover Planning Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planning'));
    await tester.pumpAndSettle();

    expect(repositories[TrackingProvider.anilist]!.statusUpdates, [
      (mediaId: 88, status: TrackingListStatus.planToWatch),
    ]);
    expect(repositories[TrackingProvider.myAnimeList]!.statusUpdates, [
      (mediaId: 99, status: TrackingListStatus.planToWatch),
    ]);
  });

  testWidgets('holding a planned Discover result can remove it from lists', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      TrackingProvider.anilist.tokenStorageKey: 'anilist-token',
      TrackingProvider.myAnimeList.tokenStorageKey: 'mal-token',
    });
    final repositories = <TrackingProvider, _DiscoverRecordingRepository>{};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogClientProvider.overrideWithValue(
            _FakeCatalog(
              results: const [
                AnimeSummary(
                  id: 188,
                  idMal: 199,
                  title: 'Remove Planned Show',
                  description: '',
                  episodes: 12,
                  score: 8,
                ),
              ],
            ),
          ),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [
                HomeTrackedAnime(
                  tracked: TrackedAnime(
                    mediaId: 188,
                    title: 'Remove Planned Show',
                    status: TrackingListStatus.planToWatch,
                    progress: 0,
                  ),
                  provider: TrackingProvider.anilist,
                  anilistId: 188,
                  coverImageUrl: null,
                ),
              ],
              completed: [],
            ),
          ),
          trackingRepositoryFactoryProvider.overrideWithValue((provider, _) {
            return repositories.putIfAbsent(
              provider,
              _DiscoverRecordingRepository.new,
            );
          }),
        ],
        child: const MaterialApp(home: DiscoverScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Remove Planned Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from list'));
    await tester.pumpAndSettle();

    expect(repositories[TrackingProvider.anilist]!.removals, [188]);
    expect(repositories[TrackingProvider.myAnimeList]!.removals, [199]);
  });
}

class _FakeCatalog extends AniListCatalogClient {
  _FakeCatalog({this.results = const [], this.error});

  final List<AnimeSummary> results;
  final Object? error;
  final requests = <CatalogFilters>[];

  @override
  Future<List<AnimeSummary>> discover(
    CatalogFilters filters, {
    int page = 1,
  }) async {
    requests.add(filters);
    if (error != null) throw error!;
    return results;
  }
}

class _DiscoverRecordingRepository implements TrackingRepository {
  final statusUpdates = <({int mediaId, TrackingListStatus status})>[];
  final removals = <int>[];

  @override
  Future<int?> currentProgress(int mediaId) async => null;

  @override
  Future<List<TrackedAnime>> list(TrackingListStatus status) async => const [];

  @override
  Future<void> removeFromList({required int mediaId}) async {
    removals.add(mediaId);
  }

  @override
  Future<void> updateProgress({
    required int mediaId,
    required int completedEpisodes,
  }) async {}

  @override
  Future<void> updateStatus({
    required int mediaId,
    required TrackingListStatus status,
  }) async {
    statusUpdates.add((mediaId: mediaId, status: status));
  }
}
