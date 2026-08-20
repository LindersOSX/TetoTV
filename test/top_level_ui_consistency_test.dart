import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/teto_top_level_shell.dart';
import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/airing_calendar_screen.dart';
import 'package:anime_tv/features/home/presentation/main_navigation_bar.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('TV destinations share the cinematic rail, palette, and focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firstContentFocus = FocusNode(debugLabel: 'test.destination.first');
    addTearDown(firstContentFocus.dispose);
    final palette = AppThemePalette.fromSeeds(
      background: const Color(0xFF071019),
      surface: const Color(0xFF12202C),
      accent: const Color(0xFFFF2F67),
      primaryText: const Color(0xFFF8FAFF),
      mutedText: const Color(0xFFB6C1CC),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkFor(palette),
          home: TetoTopLevelShell(
            preferences: const SettingsPreferences(),
            activeDestination: TopNavigationDestination.discover,
            firstContentFocusNode: firstContentFocus,
            autofocusRail: true,
            builder: (context, layout) => Align(
              alignment: Alignment.topLeft,
              child: TvFocusable(
                focusNode: firstContentFocus,
                onPressed: () {},
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Destination content'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('teto-top-level-discover')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('main-navigation')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-nav-discover')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('main-navigation'))).width,
      60,
    );
    expect(
      tester.getTopLeft(find.text('Destination content')).dx,
      greaterThan(60),
    );

    final backdrop = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('teto-top-level-backdrop')),
    );
    final decoration = backdrop.decoration as BoxDecoration;
    expect(decoration.color, palette.background);
    expect(
      (decoration.gradient as LinearGradient).colors,
      contains(palette.background),
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'top-level.active-navigation',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(firstContentFocus));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'submenu rail surface, divider, and content offset share chrome metrics',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final contentFocusNodes = <FocusNode>[];

      for (final viewport in const [960.0, 1280.0, 1680.0]) {
        tester.view.physicalSize = Size(viewport, 720);
        final measuredWidths = <double>[];

        for (final size in NavigationChromeSize.values) {
          final firstContentFocus = FocusNode(
            debugLabel: 'test.$viewport.${size.name}.content',
          );
          contentFocusNodes.add(firstContentFocus);
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey('$viewport-${size.name}'),
              child: MaterialApp(
                theme: AppTheme.dark,
                home: TetoTopLevelShell(
                  preferences: SettingsPreferences(
                    navigationChromeSize: size,
                    loaded: true,
                  ),
                  activeDestination: TopNavigationDestination.discover,
                  firstContentFocusNode: firstContentFocus,
                  builder: (_, _) => const SizedBox.expand(
                    key: ValueKey('test-submenu-content'),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final expected = homeNavigationRailMetrics(size);
          final railFinder = find.byKey(const ValueKey('main-navigation'));
          final rail = tester.widget<Container>(railFinder);
          final decoration = rail.decoration! as BoxDecoration;
          final border = decoration.border! as Border;
          final contentRegion = tester.widget<Positioned>(
            find.byKey(const ValueKey('top-level-tv-content-region')),
          );

          measuredWidths.add(tester.getSize(railFinder).width);
          expect(tester.getSize(railFinder).width, expected.width);
          expect(contentRegion.left, expected.width);
          expect(
            tester
                .getTopLeft(find.byKey(const ValueKey('test-submenu-content')))
                .dx,
            expected.width + (viewport >= 1400 ? 34 : 28),
          );
          expect(border.right.style, BorderStyle.solid);
          expect(border.right.width, greaterThan(0));
          expect(
            tester
                .getCenter(find.byKey(const ValueKey('main-nav-wordmark')))
                .dx,
            (expected.width - border.right.width) / 2,
          );
          expect(
            tester
                .getCenter(find.byKey(const ValueKey('main-nav-discover')))
                .dx,
            (expected.width - border.right.width) / 2,
          );
        }

        expect(measuredWidths[0], lessThan(measuredWidths[1]));
        expect(measuredWidths[1], lessThan(measuredWidths[2]));
      }

      await tester.pumpWidget(const SizedBox());
      for (final node in contentFocusNodes) {
        node.dispose();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact destinations keep responsive insets without a TV rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firstContentFocus = FocusNode();
    addTearDown(firstContentFocus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: TetoTopLevelShell(
            preferences: const SettingsPreferences(),
            activeDestination: TopNavigationDestination.settings,
            firstContentFocusNode: firstContentFocus,
            builder: (_, layout) => Text(layout.usesTvRail ? 'TV' : 'Compact'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compact'), findsOneWidget);
    expect(find.byType(HomeSideNavigation), findsNothing);
    expect(
      tester.widget<SafeArea>(find.byType(SafeArea).first).minimum,
      const EdgeInsets.symmetric(horizontal: 16),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('relocated Settings stays hidden while LEFT reaches the rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final contentFocus = FocusNode(debugLabel: 'settings.test.content');
    addTearDown(contentFocus.dispose);

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
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: TetoTopLevelShell(
            preferences: const SettingsPreferences(
              settingsEntryPlacement: SettingsEntryPlacement.profileMenu,
            ),
            activeDestination: TopNavigationDestination.settings,
            firstContentFocusNode: contentFocus,
            builder: (_, layout) => Align(
              alignment: Alignment.topLeft,
              child: TvFocusable(
                focusNode: contentFocus,
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event.logicalKey != LogicalKeyboardKey.arrowLeft) {
                    return KeyEventResult.ignored;
                  }
                  if (event is KeyDownEvent || event is KeyRepeatEvent) {
                    layout.focusRail();
                  }
                  return KeyEventResult.handled;
                },
                onPressed: () {},
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Settings content'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('main-nav-settings')), findsNothing);
    expect(find.byKey(const ValueKey('main-nav-calendar')), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(contentFocus));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'top-level.active-navigation',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(contentFocus));
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar shelves move explicitly across cards and days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const first = AnimeSummary(
      id: 10,
      title: 'First followed anime',
      description: '',
      episodes: 12,
      score: 8,
    );
    const second = AnimeSummary(
      id: 20,
      title: 'Second followed anime',
      description: '',
      episodes: 12,
      score: 8,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          airingWeekProvider.overrideWith(
            (_) async => [
              AiringScheduleEntry(
                anime: first,
                episode: 2,
                airingAt: DateTime(2026, 8, 21, 20),
              ),
              AiringScheduleEntry(
                anime: second,
                episode: 3,
                airingAt: DateTime(2026, 8, 22, 20),
              ),
            ],
          ),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [
                HomeTrackedAnime(
                  tracked: TrackedAnime(
                    mediaId: 10,
                    title: 'First followed anime',
                    status: TrackingListStatus.watching,
                    progress: 1,
                  ),
                  provider: TrackingProvider.anilist,
                  anilistId: 10,
                  coverImageUrl: null,
                ),
                HomeTrackedAnime(
                  tracked: TrackedAnime(
                    mediaId: 20,
                    title: 'Second followed anime',
                    status: TrackingListStatus.watching,
                    progress: 1,
                  ),
                  provider: TrackingProvider.anilist,
                  anilistId: 20,
                  coverImageUrl: null,
                ),
              ],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const AiringCalendarScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'calendar.refresh');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('.item.0'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('.item.1'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      allOf(contains('2026-08-22'), contains('.item.1')),
    );
    expect(tester.takeException(), isNull);
  });
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
