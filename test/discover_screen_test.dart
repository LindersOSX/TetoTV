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
}

class _FakeCatalog extends AniListCatalogClient {
  @override
  Future<List<AnimeSummary>> discover(
    CatalogFilters filters, {
    int page = 1,
  }) async => const [];
}
