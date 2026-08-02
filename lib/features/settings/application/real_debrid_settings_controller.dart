import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/auth/data/real_debrid_oauth_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const realDebridTokenStorageKey = 'real_debrid_access_token';
const realDebridRefreshTokenStorageKey = 'real_debrid_refresh_token';
const realDebridClientIdStorageKey = 'real_debrid_oauth_client_id';
const realDebridClientSecretStorageKey = 'real_debrid_oauth_client_secret';
const realDebridAccessExpiryStorageKey = 'real_debrid_access_expiry';

typedef RealDebridClientFactory = RealDebridClient Function(String token);

final realDebridClientFactoryProvider = Provider<RealDebridClientFactory>(
  (_) =>
      (token) => RealDebridClient(token: token),
);

final realDebridSettingsControllerProvider =
    StateNotifierProvider<
      RealDebridSettingsController,
      RealDebridSettingsState
    >((ref) {
      final controller = RealDebridSettingsController(
        ref.watch(secureStorageProvider),
        ref.watch(realDebridClientFactoryProvider),
      );
      Future.microtask(controller.load);
      return controller;
    });

class RealDebridSettingsState {
  const RealDebridSettingsState({
    this.isLoading = false,
    this.hasSavedToken = false,
    this.account,
    this.errorMessage,
  });

  final bool isLoading;
  final bool hasSavedToken;
  final RealDebridAccount? account;
  final String? errorMessage;

  RealDebridSettingsState copyWith({
    bool? isLoading,
    bool? hasSavedToken,
    RealDebridAccount? account,
    bool clearAccount = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RealDebridSettingsState(
      isLoading: isLoading ?? this.isLoading,
      hasSavedToken: hasSavedToken ?? this.hasSavedToken,
      account: clearAccount ? null : account ?? this.account,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class RealDebridSettingsController
    extends StateNotifier<RealDebridSettingsState> {
  RealDebridSettingsController(this._storage, this._clientFactory)
    : super(const RealDebridSettingsState());

  final FlutterSecureStorage _storage;
  final RealDebridClientFactory _clientFactory;

  Future<void> load() async {
    var token = await _storage.read(key: realDebridTokenStorageKey);
    if (token == null || token.isEmpty) {
      state = const RealDebridSettingsState();
      return;
    }
    state = state.copyWith(
      isLoading: true,
      hasSavedToken: true,
      clearError: true,
    );
    try {
      token = await _refreshIfNeeded(token);
      await _validate(token, persist: false);
    } catch (error) {
      state = RealDebridSettingsState(
        hasSavedToken: true,
        errorMessage: error.toString(),
      );
    }
  }

  Future<bool> saveAndValidate(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Enter your Real-Debrid API token first.',
      );
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    return _validate(normalized, persist: true);
  }

  Future<bool> _validate(String token, {required bool persist}) async {
    try {
      final account = await _clientFactory(token).account();
      if (persist) {
        // A token entered in Accounts is a standalone API token. Remove any
        // older device-flow metadata so a stale refresh token cannot later
        // overwrite the newly validated manual token.
        await Future.wait([
          _storage.write(key: realDebridTokenStorageKey, value: token),
          _storage.delete(key: realDebridRefreshTokenStorageKey),
          _storage.delete(key: realDebridClientIdStorageKey),
          _storage.delete(key: realDebridClientSecretStorageKey),
          _storage.delete(key: realDebridAccessExpiryStorageKey),
        ]);
      }
      state = RealDebridSettingsState(hasSavedToken: true, account: account);
      return true;
    } catch (error) {
      state = RealDebridSettingsState(
        hasSavedToken: !persist,
        errorMessage: error.toString(),
      );
      return false;
    }
  }

  Future<void> disconnect() async {
    await Future.wait([
      _storage.delete(key: realDebridTokenStorageKey),
      _storage.delete(key: realDebridRefreshTokenStorageKey),
      _storage.delete(key: realDebridClientIdStorageKey),
      _storage.delete(key: realDebridClientSecretStorageKey),
      _storage.delete(key: realDebridAccessExpiryStorageKey),
    ]);
    state = const RealDebridSettingsState();
  }

  Future<String> _refreshIfNeeded(String currentToken) async {
    final expiryValue = await _storage.read(
      key: realDebridAccessExpiryStorageKey,
    );
    final expiry = expiryValue == null ? null : DateTime.tryParse(expiryValue);
    if (expiry == null ||
        expiry.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return currentToken;
    }

    final values = await Future.wait([
      _storage.read(key: realDebridClientIdStorageKey),
      _storage.read(key: realDebridClientSecretStorageKey),
      _storage.read(key: realDebridRefreshTokenStorageKey),
    ]);
    if (values.any((value) => value == null || value.isEmpty)) {
      return currentToken;
    }

    final tokens = await RealDebridOAuthClient().refresh(
      clientId: values[0]!,
      clientSecret: values[1]!,
      refreshToken: values[2]!,
    );
    await Future.wait([
      _storage.write(key: realDebridTokenStorageKey, value: tokens.accessToken),
      _storage.write(
        key: realDebridRefreshTokenStorageKey,
        value: tokens.refreshToken,
      ),
      _storage.write(
        key: realDebridAccessExpiryStorageKey,
        value: tokens.expiresAt.toUtc().toIso8601String(),
      ),
    ]);
    return tokens.accessToken;
  }
}
