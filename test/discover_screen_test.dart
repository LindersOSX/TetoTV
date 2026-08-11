import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/data/anilist_catalog_client.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/discover_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

    expect(find.text('Discover filters'), findsOneWidget);
    expect(find.text('Genre'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    expect(find.text('Format'), findsOneWidget);
    expect(find.text('Season'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Minimum score'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -360));
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
}

class _FakeCatalog extends AniListCatalogClient {
  final requests = <CatalogFilters>[];

  @override
  Future<List<AnimeSummary>> discover(
    CatalogFilters filters, {
    int page = 1,
  }) async {
    requests.add(filters);
    return const [];
  }
}
