import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/home/presentation/home_screen.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('normalized 1080p TV canvas keeps fallback hero in bounds', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(960, 540);
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
          recentPlaybackProvider.overrideWith((_) async => const []),
          dismissedContinueWatchingProvider.overrideWith(
            (_) async => const <int>{},
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('home-hero')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('medium Home canvas keeps the hero within its bounds', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith(
            (_) async => const [
              AnimeSummary(
                id: 1,
                title: 'A deliberately long featured title for medium screens',
                description:
                    'A longer description verifies the hero remains clipped and '
                    'laid out correctly on the default widget-test canvas.',
                episodes: 24,
                score: 8.6,
                season: 'SPRING',
                seasonYear: 2026,
                format: 'TV',
                status: 'RELEASING',
              ),
            ],
          ),
          seasonalAnimeProvider.overrideWith((_) async => const []),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
          recentPlaybackProvider.overrideWith((_) async => const []),
          dismissedContinueWatchingProvider.overrideWith(
            (_) async => const <int>{},
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('home-hero')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TV home uses explicit shelf movement and restores the selected card',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        initialSetupCompletedStorageKey: 'true',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime(2026, 8, 20);
      final checkpoints = [
        PlaybackCheckpoint(
          anilistMediaId: 101,
          episode: 3,
          title: 'First show',
          position: const Duration(minutes: 4),
          duration: const Duration(minutes: 24),
          updatedAt: now,
        ),
        PlaybackCheckpoint(
          anilistMediaId: 202,
          episode: 7,
          title: 'Second show',
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 24),
          updatedAt: now.subtract(const Duration(minutes: 1)),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trendingAnimeProvider.overrideWith(
              (_) async => const [
                AnimeSummary(
                  id: 1,
                  title: 'Featured',
                  description: 'Featured description',
                  episodes: 12,
                  score: 8.4,
                ),
              ],
            ),
            seasonalAnimeProvider.overrideWith((_) async => const []),
            trackingHomeProvider.overrideWith(
              (_) async => const TrackingHomeData(
                watching: [],
                planToWatch: [],
                completed: [],
              ),
            ),
            recentPlaybackProvider.overrideWith((_) async => checkpoints),
            dismissedContinueWatchingProvider.overrideWith(
              (_) async => const <int>{},
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'home.watch-now');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.shelf.Continue watching.item.0',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.shelf.Continue watching.item.1',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.shelf.Watch history.item.1',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.shelf.Continue watching.item.1',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.navigation.home',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.shelf.Continue watching.item.0',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden hero and Home icon focus the nearest visible rail action',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        initialSetupCompletedStorageKey: 'true',
        'home_show_featured_hero': 'false',
        'navigation_show_home': 'false',
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
            recentPlaybackProvider.overrideWith(
              (_) async => [
                PlaybackCheckpoint(
                  anilistMediaId: 909,
                  episode: 2,
                  title: 'Rail focus fixture',
                  position: const Duration(minutes: 5),
                  duration: const Duration(minutes: 24),
                  updatedAt: DateTime(2026, 8, 20),
                ),
              ],
            ),
            dismissedContinueWatchingProvider.overrideWith(
              (_) async => const <int>{},
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(const ValueKey('main-nav-home')), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.navigation.home',
      );
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.shelf.Continue watching.item.0',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.navigation.home',
      );
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.navigation.home',
      );
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an empty customized rail returns shelf focus to the profile menu',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        initialSetupCompletedStorageKey: 'true',
        'home_show_featured_hero': 'false',
        'navigation_show_home': 'false',
        'navigation_show_search': 'false',
        'navigation_show_my_list': 'false',
        'navigation_show_discover': 'false',
        'navigation_show_calendar': 'false',
        'navigation_settings_entry_placement': 'profileMenu',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackingAccountsControllerProvider.overrideWith(
              (_) => _StaticTrackingAccountsController(
                const TrackingAccountsState(
                  profiles: {
                    TrackingProvider.anilist: TrackingAccountProfile(
                      provider: TrackingProvider.anilist,
                      username: 'TetoFan',
                    ),
                  },
                ),
              ),
            ),
            trendingAnimeProvider.overrideWith((_) async => const []),
            seasonalAnimeProvider.overrideWith((_) async => const []),
            trackingHomeProvider.overrideWith(
              (_) async => const TrackingHomeData(
                watching: [],
                planToWatch: [],
                completed: [],
              ),
            ),
            recentPlaybackProvider.overrideWith(
              (_) async => [
                PlaybackCheckpoint(
                  anilistMediaId: 910,
                  episode: 2,
                  title: 'Empty rail fixture',
                  position: const Duration(minutes: 5),
                  duration: const Duration(minutes: 24),
                  updatedAt: DateTime(2026, 8, 20),
                ),
              ],
            ),
            dismissedContinueWatchingProvider.overrideWith(
              (_) async => const <int>{},
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      for (final key in const [
        'main-nav-home',
        'main-nav-search',
        'main-nav-my-list',
        'main-nav-discover',
        'main-nav-calendar',
        'main-nav-settings',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.shelf.Continue watching.item.0',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'home.profile-switcher',
      );
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
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
