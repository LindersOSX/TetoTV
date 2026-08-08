import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';

final trackingAccountsControllerProvider =
    StateNotifierProvider<TrackingAccountsController, TrackingAccountsState>((
      ref,
    ) {
      final controller = TrackingAccountsController(
        ref,
        ref.watch(trackingTokenServiceProvider),
      );
      Future.microtask(controller.load);
      return controller;
    });

class TrackingAccountsState {
  const TrackingAccountsState({
    this.isLoading = false,
    this.usernames = const {},
    this.errors = const {},
  });

  final bool isLoading;
  final Map<TrackingProvider, String> usernames;
  final Map<TrackingProvider, String> errors;

  bool isConnected(TrackingProvider provider) =>
      usernames.containsKey(provider);
}

class TrackingAccountsController extends StateNotifier<TrackingAccountsState> {
  TrackingAccountsController(this._ref, this._tokenService, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ),
      super(const TrackingAccountsState());

  final Ref _ref;
  final TrackingTokenService _tokenService;
  final Dio _dio;
  int _loadGeneration = 0;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    state = TrackingAccountsState(
      isLoading: true,
      usernames: state.usernames,
      errors: state.errors,
    );
    final usernames = <TrackingProvider, String>{};
    final errors = <TrackingProvider, String>{};
    for (final provider in TrackingProvider.values) {
      try {
        final token = await _tokenService.accessToken(provider);
        if (token == null || token.isEmpty) continue;
        usernames[provider] = await _username(provider, token);
      } catch (error) {
        errors[provider] = error.toString();
      }
    }
    if (!mounted || generation != _loadGeneration) return;
    state = TrackingAccountsState(usernames: usernames, errors: errors);
  }

  Future<void> disconnect(TrackingProvider provider) async {
    await _tokenService.clear(provider);
    _ref.invalidate(trackingHomeProvider);
    await load();
  }

  Future<void> save(TrackingProvider provider, String token) async {
    await _tokenService.save(provider, token);
    _ref.invalidate(trackingHomeProvider);
    await load();
  }

  Future<String> _username(TrackingProvider provider, String token) async {
    return switch (provider) {
      TrackingProvider.anilist => _anilistUsername(token),
      TrackingProvider.myAnimeList => _malUsername(token),
    };
  }

  Future<String> _anilistUsername(String token) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'https://graphql.anilist.co',
      data: const {'query': 'query { Viewer { name } }'},
      options: Options(
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
    );
    final data = response.data?['data'] as Map<String, dynamic>?;
    final viewer = data?['Viewer'] as Map<String, dynamic>?;
    return viewer?['name'] as String? ??
        (throw StateError('AniList account could not be verified.'));
  }

  Future<String> _malUsername(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.myanimelist.net/v2/users/@me',
      options: Options(
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
    );
    return response.data?['name'] as String? ??
        (throw StateError('MyAnimeList account could not be verified.'));
  }
}
