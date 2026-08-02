import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/tracking/data/anilist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/data/myanimelist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final trackingHomeProvider = FutureProvider<TrackingHomeData>((ref) async {
  final tokenService = ref.watch(trackingTokenServiceProvider);
  const homeStatuses = [
    TrackingListStatus.watching,
    TrackingListStatus.planToWatch,
    TrackingListStatus.completed,
  ];
  final all = <TrackingListStatus, List<HomeTrackedAnime>>{
    for (final status in homeStatuses) status: [],
  };

  for (final provider in TrackingProvider.values) {
    String? token;
    try {
      token = await tokenService.accessToken(provider);
    } catch (_) {
      // One expired or temporarily unreachable provider must not prevent the
      // other linked tracker from populating the home screen.
      continue;
    }
    if (token == null || token.isEmpty) continue;
    final repository = switch (provider) {
      TrackingProvider.anilist => AniListTrackingRepository(accessToken: token),
      TrackingProvider.myAnimeList => MyAnimeListTrackingRepository(
        accessToken: token,
      ),
    };
    for (final status in homeStatuses) {
      try {
        final list = await repository.list(status);
        for (final tracked in list.take(20)) {
          int? anilistId;
          if (provider == TrackingProvider.anilist) {
            anilistId = tracked.mediaId;
          }
          all[status]!.add(
            HomeTrackedAnime(
              tracked: tracked,
              provider: provider,
              anilistId: anilistId,
              coverImageUrl: tracked.coverImageUrl,
            ),
          );
        }
      } catch (e) {
        // Ignore failures for individual lists so the rest of the home screen can load
      }
    }
  }

  return TrackingHomeData(
    watching: _deduplicate(all[TrackingListStatus.watching]!),
    planToWatch: _deduplicate(all[TrackingListStatus.planToWatch]!),
    completed: _deduplicate(all[TrackingListStatus.completed]!),
  );
});

class TrackingHomeData {
  const TrackingHomeData({
    required this.watching,
    required this.planToWatch,
    required this.completed,
  });

  final List<HomeTrackedAnime> watching;
  final List<HomeTrackedAnime> planToWatch;
  final List<HomeTrackedAnime> completed;
}

class HomeTrackedAnime {
  const HomeTrackedAnime({
    required this.tracked,
    required this.provider,
    required this.anilistId,
    required this.coverImageUrl,
  });

  final TrackedAnime tracked;
  final TrackingProvider provider;
  final int? anilistId;
  final String? coverImageUrl;
}

List<HomeTrackedAnime> _deduplicate(List<HomeTrackedAnime> items) {
  final unique = <String, HomeTrackedAnime>{};
  for (final item in items) {
    final key =
        item.anilistId?.toString() ?? item.tracked.title.toLowerCase().trim();
    unique.putIfAbsent(key, () => item);
  }
  return unique.values.toList(growable: false);
}
