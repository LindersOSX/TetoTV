import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/airing_calendar_screen.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('Calendar system Back returns Home without a header arrow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/calendar',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home destination')),
        ),
        GoRoute(
          path: '/calendar',
          builder: (_, _) => const AiringCalendarScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          airingWeekProvider.overrideWith((_) async => const []),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Home destination'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar only shows Watching and Planning titles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now().add(const Duration(hours: 4));
    const followed = AnimeSummary(
      id: 10,
      title: 'Followed anime',
      description: '',
      episodes: 12,
      score: 8,
    );
    const unrelated = AnimeSummary(
      id: 20,
      title: 'Unrelated anime',
      description: '',
      episodes: 12,
      score: 8,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          airingWeekProvider.overrideWith(
            (_) async => [
              AiringScheduleEntry(anime: followed, episode: 2, airingAt: now),
              AiringScheduleEntry(anime: unrelated, episode: 2, airingAt: now),
            ],
          ),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [
                HomeTrackedAnime(
                  tracked: TrackedAnime(
                    mediaId: 10,
                    title: 'Followed anime',
                    status: TrackingListStatus.watching,
                    progress: 1,
                  ),
                  provider: TrackingProvider.anilist,
                  anilistId: 10,
                  coverImageUrl: null,
                ),
              ],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(
          home: TvShortcuts(child: AiringCalendarScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('main-navigation'))).dy,
      0,
      reason: 'Primary navigation must not gain extra top padding',
    );
    expect(find.text('Followed anime'), findsOneWidget);
    expect(find.text('Unrelated anime'), findsNothing);
    final refreshDetector = find.descendant(
      of: find.ancestor(
        of: find.byIcon(Icons.refresh_rounded),
        matching: find.byType(TvFocusable),
      ),
      matching: find.byType(FocusableActionDetector),
    );
    expect(
      tester
          .widget<FocusableActionDetector>(refreshDetector)
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'top-level.active-navigation',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      tester
          .widget<FocusableActionDetector>(refreshDetector)
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
