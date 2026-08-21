import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/data/anilist_catalog_client.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/discover_screen.dart';
import 'package:anime_tv/features/catalog/presentation/search_screen.dart';
import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/home/presentation/home_screen.dart';
import 'package:anime_tv/features/home/presentation/main_navigation_bar.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Modern Layout rail metrics scale on common TV canvases', () {
    const expectedWidths = <int, List<double>>{
      960: [48, 60, 72],
      1280: [48, 60, 72],
      1680: [48, 60, 72],
    };

    for (final MapEntry(key: viewport, value: widths)
        in expectedWidths.entries) {
      final metrics = [
        for (final size in NavigationChromeSize.values)
          homeNavigationRailMetrics(size),
      ];
      expect(metrics.map((value) => value.width), widths);
      expect([
        for (final size in NavigationChromeSize.values)
          homeNavigationRailWidth(viewport.toDouble(), size),
      ], widths);
      expect(metrics[0].logoSize, lessThan(metrics[1].logoSize));
      expect(metrics[1].logoSize, lessThan(metrics[2].logoSize));
      expect(metrics[0].actionWidth, lessThan(metrics[1].actionWidth));
      expect(metrics[1].actionWidth, lessThan(metrics[2].actionWidth));
      for (final value in metrics) {
        expect(value.width, greaterThan(value.logoSize));
        expect(value.logoSize, greaterThan(value.actionWidth));
        expect((value.width - value.logoSize) / 2, value.actionGap + 2);
      }
    }
  });

  testWidgets(
    'Home rail background, divider, and content inset follow chrome size',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        initialSetupCompletedStorageKey: 'true',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settings = _RailSettingsController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsPreferencesProvider.overrideWith((_) => settings),
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

      final measuredWidths = <double>[];
      for (final size in NavigationChromeSize.values) {
        await settings.setNavigationChromeSize(size);
        await tester.pump();

        final expected = homeNavigationRailMetrics(size);
        final railFinder = find.byKey(const ValueKey('main-navigation'));
        final rail = tester.widget<Container>(railFinder);
        final decoration = rail.decoration! as BoxDecoration;
        final border = decoration.border! as Border;
        final contentRegion = tester.widget<Positioned>(
          find.byKey(const ValueKey('home-tv-content-region')),
        );

        measuredWidths.add(tester.getSize(railFinder).width);
        expect(tester.getSize(railFinder).width, expected.width);
        expect(contentRegion.left, expected.width);
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('home-scroll-content')))
              .dx,
          expected.width,
        );
        expect(border.right.style, BorderStyle.solid);
        expect(border.right.width, greaterThan(0));
        expect(
          tester.getCenter(find.byKey(const ValueKey('main-nav-wordmark'))).dx,
          (expected.width - border.right.width) / 2,
        );
        expect(
          tester.getCenter(find.byKey(const ValueKey('main-nav-home'))).dx,
          (expected.width - border.right.width) / 2,
        );
      }

      expect(measuredWidths[0], lessThan(measuredWidths[1]));
      expect(measuredWidths[1], lessThan(measuredWidths[2]));
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('Home reveals a far remembered column before changing shelves', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 8, 20);
    final checkpoints = [
      for (var index = 0; index < 18; index++)
        PlaybackCheckpoint(
          anilistMediaId: 1000 + index,
          episode: index + 1,
          title: 'Far shelf show $index',
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 24),
          updatedAt: now.subtract(Duration(minutes: index)),
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
    await tester.pump(const Duration(milliseconds: 180));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'home.shelf.Continue watching.item.12',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'home.shelf.Watch history.item.12',
    );
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Modern profile stays at the top and disappears with Home content',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        initialSetupCompletedStorageKey: 'true',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime(2026, 8, 20);
      final settings = _RailSettingsController(
        const SettingsPreferences(
          interfaceMode: InterfaceMode.television,
          loaded: true,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsPreferencesProvider.overrideWith((_) => settings),
            trackingAccountsControllerProvider.overrideWith(
              (_) => _StaticTrackingAccountsController(
                const TrackingAccountsState(
                  profiles: {
                    TrackingProvider.anilist: TrackingAccountProfile(
                      provider: TrackingProvider.anilist,
                      username: 'Fixed profile',
                    ),
                  },
                ),
              ),
            ),
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
            recentPlaybackProvider.overrideWith(
              (_) async => [
                for (var index = 0; index < 5; index++)
                  PlaybackCheckpoint(
                    anilistMediaId: 100 + index,
                    episode: index + 1,
                    title: 'History show $index',
                    position: const Duration(minutes: 5),
                    duration: const Duration(minutes: 24),
                    updatedAt: now.subtract(Duration(minutes: index)),
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

      final scrollFinder = find.byKey(const ValueKey('home-scroll-content'));
      final scrollView = tester.widget<SingleChildScrollView>(scrollFinder);
      final controller = scrollView.controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0));

      final profileFinder = find.byKey(const ValueKey('home-fixed-profile'));
      final fixedProfileTop = tester.getTopLeft(profileFinder).dy;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(controller.offset, greaterThan(0));
      expect(profileFinder, findsNothing);

      await settings.setInterfaceMode(InterfaceMode.phone);
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      await tester.pump();
      expect(profileFinder, findsNothing);
      await settings.setInterfaceMode(InterfaceMode.television);
      await tester.pump();
      expect(controller.offset, closeTo(0, .5));
      expect(tester.getTopLeft(profileFinder).dy, fixedProfileTop);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Classic Layout restores the horizontal Home navigation', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = _RailSettingsController(
      const SettingsPreferences(
        interfaceMode: InterfaceMode.phone,
        showHero: false,
        loaded: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPreferencesProvider.overrideWith((_) => settings),
          trackingAccountsControllerProvider.overrideWith(
            (_) => _StaticTrackingAccountsController(
              const TrackingAccountsState(
                profiles: {
                  TrackingProvider.anilist: TrackingAccountProfile(
                    provider: TrackingProvider.anilist,
                    username: 'Classic profile',
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

    expect(find.byType(HomeSideNavigation), findsNothing);
    expect(find.byType(MainNavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('home-fixed-profile')), findsNothing);
    expect(
      find.byKey(const ValueKey('main-nav-profile-summary')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Modern Home, Search, and Discover share default poster size', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const anime = AnimeSummary(
      id: 404,
      title: 'Shared poster geometry',
      description: '',
      episodes: 12,
      score: 8,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPreferencesProvider.overrideWith(
            (_) => _RailSettingsController(),
          ),
          trendingAnimeProvider.overrideWith((_) async => const []),
          seasonalAnimeProvider.overrideWith((_) async => const [anime]),
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
    await tester.pump(const Duration(milliseconds: 150));
    final homeSize = tester.getSize(
      find.byKey(const ValueKey('home-poster-card-404')),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPreferencesProvider.overrideWith(
            (_) => _RailSettingsController(),
          ),
          catalogClientProvider.overrideWithValue(
            _ImmediateSearchCatalog(const [anime]),
          ),
        ],
        child: const MaterialApp(
          home: SearchScreen(initialQuery: 'shared poster'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final searchCard = find
        .ancestor(
          of: find.text('Shared poster geometry'),
          matching: find.byType(TvFocusable),
        )
        .first;
    final searchSize = tester.getSize(searchCard);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPreferencesProvider.overrideWith(
            (_) => _RailSettingsController(),
          ),
          catalogClientProvider.overrideWithValue(
            _ImmediateSearchCatalog(const [anime]),
          ),
        ],
        child: const MaterialApp(home: DiscoverScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final discoverCard = find
        .ancestor(
          of: find.text('Shared poster geometry'),
          matching: find.byType(TvFocusable),
        )
        .first;
    final discoverSize = tester.getSize(discoverCard);

    expect(homeSize.width, closeTo(searchSize.width, .01));
    expect(homeSize.height, closeTo(searchSize.height, .01));
    expect(homeSize.width, closeTo(discoverSize.width, .01));
    expect(homeSize.height, closeTo(discoverSize.height, .01));
    expect(tester.takeException(), isNull);
  });

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

class _RailSettingsController extends SettingsPreferencesController {
  _RailSettingsController([
    SettingsPreferences initial = const SettingsPreferences(
      showHero: false,
      loaded: true,
    ),
  ]) : super(const FlutterSecureStorage()) {
    state = initial;
  }

  @override
  Future<void> load() async {}
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

class _ImmediateSearchCatalog extends AniListCatalogClient {
  _ImmediateSearchCatalog(this.results);

  final List<AnimeSummary> results;

  @override
  Future<List<AnimeSummary>> search(String term, {int page = 1}) async =>
      results;

  @override
  Future<List<AnimeSummary>> discover(
    CatalogFilters filters, {
    int page = 1,
  }) async => results;
}

class _TrackingAccountsRef extends Fake implements Ref {}
