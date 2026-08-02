import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/auth/data/anilist_pairing_client.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final trackingTokenServiceProvider = Provider<TrackingTokenService>(
  (ref) => TrackingTokenService(ref.watch(secureStorageProvider)),
);

class TrackingTokenService {
  TrackingTokenService(this._storage);

  final FlutterSecureStorage _storage;

  Future<String?> accessToken(TrackingProvider provider) async {
    final accessToken = await _storage.read(key: provider.tokenStorageKey);
    if (accessToken == null || accessToken.isEmpty) return null;
    if (provider != TrackingProvider.myAnimeList) return accessToken;

    final expiresAtValue = await _storage.read(
      key: provider.expiresAtStorageKey,
    );
    final expiresAt = DateTime.tryParse(expiresAtValue ?? '');
    if (expiresAt == null ||
        expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 5)),
        )) {
      return accessToken;
    }

    final refreshToken = await _storage.read(
      key: provider.refreshTokenStorageKey,
    );
    final brokerUrl = await effectiveAuthBrokerBaseUrl(_storage);
    if (refreshToken == null || refreshToken.isEmpty || brokerUrl == null) {
      return accessToken;
    }

    final tokens = await TrackingPairingClient(
      provider,
      baseUrl: brokerUrl,
    ).refresh(refreshToken);
    await _storage.write(
      key: provider.tokenStorageKey,
      value: tokens.accessToken,
    );
    if (tokens.refreshToken case final rotated? when rotated.isNotEmpty) {
      await _storage.write(
        key: provider.refreshTokenStorageKey,
        value: rotated,
      );
    }
    if (tokens.expiresAt case final newExpiry?) {
      await _storage.write(
        key: provider.expiresAtStorageKey,
        value: newExpiry.toUtc().toIso8601String(),
      );
    }
    return tokens.accessToken;
  }

  Future<void> save(TrackingProvider provider, String token) async {
    await _storage.write(key: provider.tokenStorageKey, value: token.trim());
  }

  Future<void> clear(TrackingProvider provider) async {
    await Future.wait([
      _storage.delete(key: provider.tokenStorageKey),
      _storage.delete(key: provider.refreshTokenStorageKey),
      _storage.delete(key: provider.expiresAtStorageKey),
    ]);
  }
}
