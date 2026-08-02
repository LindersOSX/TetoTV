import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/data/anilist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/data/myanimelist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final trackingListProvider = FutureProvider.autoDispose
    .family<List<HomeTrackedAnime>, TrackingListStatus>((ref, status) async {
      final tokenService = ref.watch(trackingTokenServiceProvider);
      final items = <HomeTrackedAnime>[];
      for (final provider in TrackingProvider.values) {
        String? token;
        try {
          token = await tokenService.accessToken(provider);
        } catch (_) {
          // Keep the other tracker usable if this provider cannot refresh.
          continue;
        }
        if (token == null || token.isEmpty) continue;
        final repository = trackingRepository(provider, token);
        try {
          final entries = await repository.list(status);
          items.addAll(
            entries.map(
              (tracked) => HomeTrackedAnime(
                tracked: tracked,
                provider: provider,
                anilistId: provider == TrackingProvider.anilist
                    ? tracked.mediaId
                    : null,
                coverImageUrl: tracked.coverImageUrl,
              ),
            ),
          );
        } catch (_) {
          // One disconnected or temporarily unavailable tracker should not
          // hide the other tracker's list.
        }
      }
      items.sort(
        (left, right) => left.tracked.title.compareTo(right.tracked.title),
      );
      return items;
    });

final trackingStatusControllerProvider =
    StateNotifierProvider.autoDispose<
      TrackingStatusController,
      AsyncValue<void>
    >((ref) => TrackingStatusController(ref));

class TrackingStatusController extends StateNotifier<AsyncValue<void>> {
  TrackingStatusController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<void> update(HomeTrackedAnime item, TrackingListStatus status) async {
    if (status == item.tracked.status) return;
    state = const AsyncLoading();
    try {
      final token = await _ref
          .read(trackingTokenServiceProvider)
          .accessToken(item.provider);
      if (token == null || token.isEmpty) {
        throw StateError('${item.provider.displayName} is not connected.');
      }
      await trackingRepository(
        item.provider,
        token,
      ).updateStatus(mediaId: item.tracked.mediaId, status: status);
      _ref.invalidate(trackingListProvider(item.tracked.status));
      _ref.invalidate(trackingListProvider(status));
      _ref.invalidate(trackingHomeProvider);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

TrackingRepository trackingRepository(
  TrackingProvider provider,
  String accessToken,
) => switch (provider) {
  TrackingProvider.anilist => AniListTrackingRepository(
    accessToken: accessToken,
  ),
  TrackingProvider.myAnimeList => MyAnimeListTrackingRepository(
    accessToken: accessToken,
  ),
};
