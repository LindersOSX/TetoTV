import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRef extends Fake implements Ref {}

void main() {
  const storage = FlutterSecureStorage();

  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'token refresh failure finishes loading and reports the account',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        TrackingProvider.myAnimeList.tokenStorageKey: 'expired-token',
        TrackingProvider.myAnimeList.expiresAtStorageKey: DateTime.utc(
          2025,
        ).toIso8601String(),
      });
      final tokenService = TrackingTokenService(
        storage,
        now: () => DateTime.utc(2026),
      );
      final controller = TrackingAccountsController(_FakeRef(), tokenService);

      await controller.load();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.usernames, isEmpty);
      expect(
        controller.state.errors[TrackingProvider.myAnimeList],
        contains('session expired'),
      );
    },
  );
}
