import 'package:anime_tv/features/tracking/data/anilist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/data/myanimelist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps all tracker list states to AniList values', () {
    expect(anilistStatus(TrackingListStatus.watching), 'CURRENT');
    expect(anilistStatus(TrackingListStatus.planToWatch), 'PLANNING');
    expect(anilistStatus(TrackingListStatus.completed), 'COMPLETED');
    expect(anilistStatus(TrackingListStatus.dropped), 'DROPPED');
    expect(anilistStatus(TrackingListStatus.onHold), 'PAUSED');
  });

  test('maps all tracker list states to MyAnimeList values', () {
    expect(myAnimeListStatus(TrackingListStatus.watching), 'watching');
    expect(myAnimeListStatus(TrackingListStatus.planToWatch), 'plan_to_watch');
    expect(myAnimeListStatus(TrackingListStatus.completed), 'completed');
    expect(myAnimeListStatus(TrackingListStatus.dropped), 'dropped');
    expect(myAnimeListStatus(TrackingListStatus.onHold), 'on_hold');
  });
}
