import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum HomeShelf { history, tracking, trending, planned, airing, completed }

const _storageKey = 'home_shelves_v1';

final homeShelfPreferencesProvider =
    StateNotifierProvider<HomeShelfPreferencesController, Set<HomeShelf>>((
      ref,
    ) {
      final controller = HomeShelfPreferencesController(
        ref.watch(secureStorageProvider),
      );
      Future.microtask(controller.load);
      return controller;
    });

class HomeShelfPreferencesController extends StateNotifier<Set<HomeShelf>> {
  HomeShelfPreferencesController(this._storage)
    : super(Set.unmodifiable(HomeShelf.values));

  final FlutterSecureStorage _storage;

  Future<void> load() async {
    try {
      final value = await _storage.read(key: _storageKey);
      if (value == null || value.isEmpty) return;
      final names = value.split(',').toSet();
      state = Set.unmodifiable(
        HomeShelf.values.where((shelf) => names.contains(shelf.name)),
      );
    } catch (_) {
      // All shelves remain enabled when device storage is unavailable.
    }
  }

  Future<void> toggle(HomeShelf shelf) async {
    final next = {...state};
    next.contains(shelf) ? next.remove(shelf) : next.add(shelf);
    state = Set.unmodifiable(next);
    try {
      await _storage.write(
        key: _storageKey,
        value: next.map((item) => item.name).join(','),
      );
    } catch (_) {
      // The in-memory choice is still useful for this session.
    }
  }
}
