import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tetoTvDatabaseProvider = Provider<TetoTvDatabase>(
  (_) => TetoTvDatabase.instance,
);

final recentPlaybackProvider = FutureProvider<List<PlaybackCheckpoint>>((ref) {
  return ref.watch(tetoTvDatabaseProvider).recentHistory();
});

final latestPlaybackProvider = FutureProvider.family<PlaybackCheckpoint?, int>((
  ref,
  mediaId,
) {
  return ref.watch(tetoTvDatabaseProvider).latestCheckpoint(mediaId);
});

final dismissedContinueWatchingProvider = FutureProvider<Set<int>>((ref) {
  return ref.watch(tetoTvDatabaseProvider).dismissedContinueWatchingIds();
});
