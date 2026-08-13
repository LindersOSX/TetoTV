import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/tracking/application/my_list_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:anime_tv/features/tracking/presentation/my_list_screen.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sorts tracker data consistently for every supported field', () {
    final older = DateTime(2024, 1, 1);
    final newer = DateTime(2025, 1, 1);
    final items = [
      HomeTrackedAnime(
        tracked: TrackedAnime(
          mediaId: 1,
          title: 'Beta',
          status: TrackingListStatus.watching,
          progress: 1,
          score: 7,
          updatedAt: older,
          startDate: newer,
        ),
        provider: TrackingProvider.anilist,
        anilistId: 1,
        coverImageUrl: null,
      ),
      HomeTrackedAnime(
        tracked: TrackedAnime(
          mediaId: 2,
          title: 'Alpha',
          status: TrackingListStatus.watching,
          progress: 1,
          score: 9,
          updatedAt: newer,
          startDate: older,
        ),
        provider: TrackingProvider.myAnimeList,
        anilistId: null,
        coverImageUrl: null,
      ),
    ];

    expect(
      sortMyListItems(items, MyListSort.title).first.tracked.title,
      'Alpha',
    );
    expect(sortMyListItems(items, MyListSort.score).first.tracked.score, 9);
    expect(
      sortMyListItems(items, MyListSort.lastUpdated).first.tracked.updatedAt,
      newer,
    );
    expect(
      sortMyListItems(items, MyListSort.startDate).first.tracked.startDate,
      newer,
    );
  });

  testWidgets('shows all tracker status tabs', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(
            TrackingListStatus.watching,
          ).overrideWith((_) async => const TrackingListResult(items: [])),
        ],
        child: const MaterialApp(home: TvShortcuts(child: MyListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    for (final status in TrackingListStatus.values) {
      expect(find.text(status.displayName), findsWidgets);
    }
    expect(find.text('Watching is empty'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Discover'), findsNothing);
    expect(find.text('Calendar'), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.explore_rounded), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    final activeMyList = find.ancestor(
      of: find.byIcon(Icons.video_library_rounded),
      matching: find.byType(TvFocusable),
    );
    final detector = find.descendant(
      of: activeMyList,
      matching: find.byType(FocusableActionDetector),
    );
    expect(
      tester.widget<FocusableActionDetector>(detector).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('shows linked tracker profile, avatar, and basic statistics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profile = TrackingAccountProfile(
      provider: TrackingProvider.anilist,
      username: 'TetoFan',
      avatarUrl: 'https://img.anili.st/avatar.png',
      animeCount: 120,
      episodesWatched: 2400,
      minutesWatched: 48000,
      meanScore: 82.4,
    );
    const malProfile = TrackingAccountProfile(
      provider: TrackingProvider.myAnimeList,
      username: 'MALFan',
      meanScore: 8.1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(
            TrackingListStatus.watching,
          ).overrideWith((_) async => const TrackingListResult(items: [])),
          trackingAccountsControllerProvider.overrideWith(
            (_) => _StaticTrackingAccountsController(
              const TrackingAccountsState(
                usernames: {
                  TrackingProvider.anilist: 'TetoFan',
                  TrackingProvider.myAnimeList: 'MALFan',
                },
                profiles: {
                  TrackingProvider.anilist: profile,
                  TrackingProvider.myAnimeList: malProfile,
                },
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pump();

    final card = find.byKey(const ValueKey('my-list-profile-anilist'));
    expect(card, findsOneWidget);
    expect(find.text('TetoFan'), findsOneWidget);
    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('120 titles'), findsOneWidget);
    expect(find.text('2400 episodes'), findsOneWidget);
    expect(find.text('800h watched'), findsOneWidget);
    expect(find.text('Mean 82.4/100'), findsOneWidget);
    expect(find.text('Mean 8.1/10'), findsOneWidget);
    final artwork = tester.widget<NetworkArtwork>(
      find.descendant(of: card, matching: find.byType(NetworkArtwork)),
    );
    expect(artwork.url, 'https://img.anili.st/avatar.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh reloads the active list and home tracking shelves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var listLoads = 0;
    var homeLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(TrackingListStatus.watching).overrideWith((
            _,
          ) async {
            listLoads++;
            return const TrackingListResult(items: []);
          }),
          trackingHomeProvider.overrideWith((_) async {
            homeLoads++;
            return const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            );
          }),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(listLoads, 1);
    expect(homeLoads, 0);

    await tester.tap(find.byKey(const Key('my-list-refresh')));
    await tester.pumpAndSettle();

    expect(listLoads, 2);
    expect(homeLoads, 1);
    expect(
      find.text('Refresh complete. Showing available connected tracker data.'),
      findsOneWidget,
    );
  });

  test('tracking result distinguishes partial and complete failures', () {
    final partial = TrackingListResult(
      items: const [],
      attempted: const {TrackingProvider.anilist, TrackingProvider.myAnimeList},
      failures: {TrackingProvider.myAnimeList: StateError('offline')},
    );
    final failed = TrackingListResult(
      items: const [],
      attempted: const {TrackingProvider.anilist, TrackingProvider.myAnimeList},
      failures: {
        TrackingProvider.anilist: StateError('offline'),
        TrackingProvider.myAnimeList: StateError('offline'),
      },
    );

    expect(partial.hasFailures, isTrue);
    expect(partial.allAttemptedFailed, isFalse);
    expect(failed.allAttemptedFailed, isTrue);
  });

  testWidgets('keeps partial tracker results visible with a warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = HomeTrackedAnime(
      tracked: const TrackedAnime(
        mediaId: 7,
        title: 'Available show',
        status: TrackingListStatus.watching,
        progress: 3,
      ),
      provider: TrackingProvider.anilist,
      anilistId: 7,
      coverImageUrl: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(TrackingListStatus.watching).overrideWith(
            (_) async => TrackingListResult(
              items: [item],
              attempted: const {
                TrackingProvider.anilist,
                TrackingProvider.myAnimeList,
              },
              failures: {TrackingProvider.myAnimeList: StateError('offline')},
            ),
          ),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available show'), findsOneWidget);
    expect(find.textContaining('MAL could not be refreshed'), findsOneWidget);
    expect(find.text('Watching is empty'), findsNothing);
  });

  testWidgets('failed refresh keeps the previous tracker cards visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loads = 0;
    final item = HomeTrackedAnime(
      tracked: const TrackedAnime(
        mediaId: 9,
        title: 'Previously loaded show',
        status: TrackingListStatus.watching,
        progress: 4,
      ),
      provider: TrackingProvider.anilist,
      anilistId: 9,
      coverImageUrl: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(TrackingListStatus.watching).overrideWith((
            _,
          ) async {
            loads++;
            if (loads == 1) {
              return TrackingListResult(
                items: [item],
                attempted: const {TrackingProvider.anilist},
              );
            }
            return TrackingListResult(
              items: const [],
              attempted: const {TrackingProvider.anilist},
              failures: {TrackingProvider.anilist: StateError('offline')},
            );
          }),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Previously loaded show'), findsOneWidget);

    await tester.tap(find.byKey(const Key('my-list-refresh')));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('Previously loaded show'), findsOneWidget);
    expect(find.textContaining('Showing the previous results'), findsOneWidget);
    expect(find.textContaining('Could not refresh AniList'), findsOneWidget);
  });

  testWidgets('a planned title can be removed instead of marked Dropped', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      TrackingProvider.anilist.tokenStorageKey: 'anilist-token',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _RemovingRepository();
    const planned = HomeTrackedAnime(
      tracked: TrackedAnime(
        mediaId: 77,
        title: 'Maybe Later',
        status: TrackingListStatus.planToWatch,
        progress: 0,
      ),
      provider: TrackingProvider.anilist,
      anilistId: 77,
      coverImageUrl: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(
            TrackingListStatus.watching,
          ).overrideWith((_) async => const TrackingListResult(items: [])),
          trackingListProvider(TrackingListStatus.planToWatch).overrideWith(
            (_) async => const TrackingListResult(items: [planned]),
          ),
          trackingRepositoryFactoryProvider.overrideWithValue(
            (_, _) => repository,
          ),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Planning').first);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Maybe Later'));
    await tester.pumpAndSettle();

    expect(find.text('Remove from Planning'), findsOneWidget);
    expect(find.text('Dropped'), findsWidgets);
    await tester.tap(find.text('Remove from Planning'));
    await tester.pumpAndSettle();

    expect(repository.removals, [77]);
    expect(find.textContaining('removed from AniList'), findsOneWidget);
  });
}

class _RemovingRepository implements TrackingRepository {
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
  }) async {}
}

class _StaticTrackingAccountsController extends TrackingAccountsController {
  _StaticTrackingAccountsController(TrackingAccountsState initial)
    : super(
        _TrackingAccountsRef(),
        TrackingTokenService(const FlutterSecureStorage()),
      ) {
    state = initial;
  }

  @override
  Future<void> load() async {}
}

class _TrackingAccountsRef extends Fake implements Ref {}
