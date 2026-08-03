import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/data/anilist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/data/myanimelist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum MyListSort { title, score, lastUpdated, startDate }

extension MyListSortLabel on MyListSort {
  String get displayName => switch (this) {
    MyListSort.title => 'Title',
    MyListSort.score => 'Score',
    MyListSort.lastUpdated => 'Last updated',
    MyListSort.startDate => 'Start date',
  };
}

final myListSortProvider =
    StateNotifierProvider<MyListSortController, MyListSort>((ref) {
      final controller = MyListSortController(ref.watch(secureStorageProvider));
      Future.microtask(controller.load);
      return controller;
    });

class MyListSortController extends StateNotifier<MyListSort> {
  MyListSortController(this._storage) : super(MyListSort.title);

  static const _key = 'my_list_sort';
  final FlutterSecureStorage _storage;

  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _key);
      state = MyListSort.values.firstWhere(
        (value) => value.name == saved,
        orElse: () => MyListSort.title,
      );
    } catch (_) {
      // Title ordering remains a safe default.
    }
  }

  Future<void> setSort(MyListSort value) async {
    state = value;
    try {
      await _storage.write(key: _key, value: value.name);
    } catch (_) {
      // Keep the current session preference if storage is unavailable.
    }
  }
}

List<HomeTrackedAnime> sortMyListItems(
  Iterable<HomeTrackedAnime> source,
  MyListSort sort,
) {
  final items = source.toList(growable: false);
  int compareNullable(Comparable<dynamic>? left, Comparable<dynamic>? right) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  }

  items.sort((left, right) {
    final result = switch (sort) {
      MyListSort.title => left.tracked.title.toLowerCase().compareTo(
        right.tracked.title.toLowerCase(),
      ),
      MyListSort.score => compareNullable(
        left.tracked.score,
        right.tracked.score,
      ),
      MyListSort.lastUpdated => compareNullable(
        left.tracked.updatedAt,
        right.tracked.updatedAt,
      ),
      MyListSort.startDate => compareNullable(
        left.tracked.startDate,
        right.tracked.startDate,
      ),
    };
    if (result != 0) return result;
    return left.tracked.title.toLowerCase().compareTo(
      right.tracked.title.toLowerCase(),
    );
  });
  return items;
}

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
