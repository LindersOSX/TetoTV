import 'package:anime_tv/app/app.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses denser canvases as physical TV resolution increases', () {
    expect(tvCanvasWidthForPhysicalPixels(1920), 960);
    expect(tvCanvasWidthForPhysicalPixels(2560), 1280);
    expect(tvCanvasWidthForPhysicalPixels(3840), 1600);
  });

  testWidgets('renders the TV home shell', (tester) async {
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
    expect(find.text('Recently released'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Continue watching')).dy,
      lessThan(tester.getTopLeft(find.text('Recently released')).dy),
    );
    expect(find.text('Watch now'), findsOneWidget);
    expect(find.text('My List'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
