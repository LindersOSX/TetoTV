import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/catalog_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final items = [
    for (var index = 0; index < 5; index++)
      AnimeSummary(
        id: index + 1,
        title: 'Boundary result ${index + 1}',
        description: '',
        episodes: 12,
        score: 8,
      ),
  ];

  for (final testCase in const [
    (width: 168.0, expectedIndex: 1, expectedColumns: 1),
    (width: 169.0, expectedIndex: 2, expectedColumns: 2),
  ]) {
    testWidgets('D-pad rows match the max-extent sliver at '
        '${testCase.width}px (${testCase.expectedColumns} columns)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: testCase.width,
                height: 700,
                child: CatalogGrid(
                  items: items,
                  titlePreference: TitleLanguagePreference.romaji,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'catalog.result.0',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'catalog.result.${testCase.expectedIndex}',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('held horizontal input is throttled without leaking traversal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 700,
            child: CatalogGrid(
              items: [
                ...items,
                for (var index = 5; index < 12; index++)
                  AnimeSummary(
                    id: index + 1,
                    title: 'Repeat result ${index + 1}',
                    description: '',
                    episodes: 12,
                    score: 8,
                  ),
              ],
              titlePreference: TitleLanguagePreference.romaji,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog.result.1');

    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog.result.1');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog.result.2');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning from details restores the exact catalog card', (
    tester,
  ) async {
    late final GoRouter router;
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: SizedBox(
              width: 640,
              height: 700,
              child: CatalogGrid(
                items: items,
                titlePreference: TitleLanguagePreference.romaji,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/anime/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Details ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog.result.1');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Details 2'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'catalog.result.1');
    expect(tester.takeException(), isNull);
  });
}
