import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/tracking/application/my_list_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:anime_tv/features/tracking/presentation/my_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          ).overrideWith((_) async => const []),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (final status in TrackingListStatus.values) {
      expect(find.text(status.displayName), findsWidgets);
    }
    expect(find.text('Watching is empty'), findsOneWidget);
  });
}
