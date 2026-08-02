import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const storage = FlutterSecureStorage();

  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  test('saving a manual token clears stale OAuth refresh metadata', () async {
    FlutterSecureStorage.setMockInitialValues({
      realDebridTokenStorageKey: 'old-oauth-token',
      realDebridRefreshTokenStorageKey: 'stale-refresh-token',
      realDebridClientIdStorageKey: 'stale-client-id',
      realDebridClientSecretStorageKey: 'stale-client-secret',
      realDebridAccessExpiryStorageKey: DateTime.utc(2020).toIso8601String(),
    });
    final controller = RealDebridSettingsController(
      storage,
      (_) => _ValidRealDebridClient(),
    );

    expect(await controller.saveAndValidate('manual-api-token'), isTrue);
    expect(
      await storage.read(key: realDebridTokenStorageKey),
      'manual-api-token',
    );
    expect(await storage.read(key: realDebridRefreshTokenStorageKey), isNull);
    expect(await storage.read(key: realDebridClientIdStorageKey), isNull);
    expect(await storage.read(key: realDebridClientSecretStorageKey), isNull);
    expect(await storage.read(key: realDebridAccessExpiryStorageKey), isNull);
  });
}

class _ValidRealDebridClient extends RealDebridClient {
  _ValidRealDebridClient() : super(token: 'test');

  @override
  Future<RealDebridAccount> account() async =>
      const RealDebridAccount(id: 1, username: 'test-user', type: 'premium');
}
