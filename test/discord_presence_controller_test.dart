import 'dart:async';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/features/discord/application/discord_presence_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const storage = FlutterSecureStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'fresh installs remain unlinked and never connect automatically',
    () async {
      final platform = _FakeDiscordPlatform();
      final controller = DiscordPresenceController(storage, platform);
      addTearDown(controller.dispose);

      await _settle();

      expect(controller.state.loaded, isTrue);
      expect(controller.state.available, isTrue);
      expect(controller.state.linked, isFalse);
      expect(controller.state.enabled, isFalse);
      expect(platform.connectCalls, 0);
      expect(platform.authenticateCalls, 0);
    },
  );

  test(
    'link stores tokens securely and connects the opted-in account',
    () async {
      final platform = _FakeDiscordPlatform();
      final controller = DiscordPresenceController(storage, platform);
      addTearDown(controller.dispose);
      await _settle();

      await controller.linkAccount();

      expect(controller.state.linked, isTrue);
      expect(controller.state.enabled, isTrue);
      expect(controller.state.connected, isTrue);
      expect(platform.authenticateCalls, 1);
      expect(platform.connectCalls, 1);
      expect(
        await storage.read(key: 'discord_rich_presence_access_token'),
        'access-token',
      );
      expect(
        await storage.read(key: 'discord_rich_presence_refresh_token'),
        'refresh-token',
      );
    },
  );

  test('concurrent link requests start authentication only once', () async {
    final platform = _FakeDiscordPlatform();
    final authentication = Completer<DiscordTokenBundle>();
    platform.authenticationCompleter = authentication;
    final controller = DiscordPresenceController(storage, platform);
    addTearDown(controller.dispose);
    await _settle();

    final firstLink = controller.linkAccount();
    final secondLink = controller.linkAccount();

    expect(controller.state.busy, isTrue);
    expect(platform.authenticateCalls, 1);

    authentication.complete(platform.token);
    await Future.wait([firstLink, secondLink]);

    expect(platform.authenticateCalls, 1);
    expect(platform.connectCalls, 1);
    expect(controller.state.linked, isTrue);
    expect(controller.state.busy, isFalse);
  });

  test('failed authentication clears busy state and stores nothing', () async {
    final platform = _FakeDiscordPlatform()
      ..authenticationError = StateError('authorization canceled');
    final controller = DiscordPresenceController(storage, platform);
    addTearDown(controller.dispose);
    await _settle();

    await controller.linkAccount();

    expect(platform.authenticateCalls, 1);
    expect(platform.connectCalls, 0);
    expect(controller.state.busy, isFalse);
    expect(controller.state.linked, isFalse);
    expect(controller.state.enabled, isFalse);
    expect(controller.state.error, contains('authorization canceled'));
    expect(await storage.read(key: 'discord_rich_presence_enabled'), isNull);
    expect(
      await storage.read(key: 'discord_rich_presence_access_token'),
      isNull,
    );
    expect(
      await storage.read(key: 'discord_rich_presence_refresh_token'),
      isNull,
    );
  });

  test(
    'connect failure retains the linked token and retry does not reauthenticate',
    () async {
      final platform = _FakeDiscordPlatform()..connectFailuresRemaining = 1;
      final controller = DiscordPresenceController(storage, platform);
      addTearDown(controller.dispose);
      await _settle();

      await controller.linkAccount();

      expect(controller.state.linked, isTrue);
      expect(controller.state.enabled, isTrue);
      expect(controller.state.busy, isFalse);
      expect(controller.state.connected, isFalse);
      expect(controller.state.error, contains('connection failed'));
      expect(platform.authenticateCalls, 1);
      expect(platform.connectCalls, 1);
      expect(
        await storage.read(key: 'discord_rich_presence_access_token'),
        'access-token',
      );

      await controller.retry();

      expect(platform.authenticateCalls, 1);
      expect(platform.refreshCalls, 1);
      expect(platform.connectCalls, 2);
      expect(controller.state.connected, isTrue);
      expect(controller.state.busy, isFalse);
    },
  );

  test(
    'disable stops presence without unlinking and enable reconnects',
    () async {
      final platform = _FakeDiscordPlatform();
      final controller = DiscordPresenceController(storage, platform);
      addTearDown(controller.dispose);
      await _settle();
      await controller.linkAccount();

      await controller.setEnabled(false);
      expect(controller.state.linked, isTrue);
      expect(controller.state.enabled, isFalse);
      expect(platform.disconnectCalls, 1);

      await controller.setEnabled(true);
      expect(controller.state.enabled, isTrue);
      expect(controller.state.connected, isTrue);
      expect(platform.connectCalls, 2);
    },
  );

  test('unlink revokes and deletes every saved Discord credential', () async {
    final platform = _FakeDiscordPlatform();
    final controller = DiscordPresenceController(storage, platform);
    addTearDown(controller.dispose);
    await _settle();
    await controller.linkAccount();

    await controller.unlinkAccount();

    expect(platform.revokeCalls, 1);
    expect(controller.state.linked, isFalse);
    expect(controller.state.enabled, isFalse);
    expect(
      await storage.read(key: 'discord_rich_presence_access_token'),
      isNull,
    );
    expect(
      await storage.read(key: 'discord_rich_presence_refresh_token'),
      isNull,
    );
  });

  test('expired restored tokens refresh before connecting', () async {
    FlutterSecureStorage.setMockInitialValues({
      'discord_rich_presence_enabled': 'true',
      'discord_rich_presence_access_token': 'old-access',
      'discord_rich_presence_refresh_token': 'old-refresh',
      'discord_rich_presence_token_type': '0',
      'discord_rich_presence_expires_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch
          .toString(),
      'discord_rich_presence_scopes': 'presence',
    });
    final platform = _FakeDiscordPlatform();
    final controller = DiscordPresenceController(storage, platform);
    addTearDown(controller.dispose);

    await _settle();

    expect(platform.refreshCalls, 1);
    expect(platform.connectCalls, 1);
    expect(platform.lastConnected?.accessToken, 'access-token');
    expect(controller.state.connected, isTrue);
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

class _FakeDiscordPlatform implements DiscordPresencePlatform {
  final _events = StreamController<DiscordBridgeEvent>.broadcast();
  Completer<DiscordTokenBundle>? authenticationCompleter;
  Object? authenticationError;
  int connectFailuresRemaining = 0;
  int authenticateCalls = 0;
  int refreshCalls = 0;
  int connectCalls = 0;
  int revokeCalls = 0;
  int disconnectCalls = 0;
  DiscordTokenBundle? lastConnected;

  DiscordTokenBundle get token => DiscordTokenBundle(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    tokenType: 0,
    expiresAt: DateTime.now().add(const Duration(days: 7)),
    scopes: 'openid sdk.social_layer_presence',
  );

  @override
  Stream<DiscordBridgeEvent> get events => _events.stream;

  @override
  Future<Map<Object?, Object?>> sdkInfo() async => {
    'available': true,
    'status': 'disconnected',
    'version': '1.10.18369',
  };

  @override
  Future<DiscordTokenBundle> authenticate() async {
    authenticateCalls++;
    if (authenticationError case final error?) throw error;
    if (authenticationCompleter case final completer?) {
      return completer.future;
    }
    return token;
  }

  @override
  Future<DiscordTokenBundle> refreshToken(String refreshToken) async {
    refreshCalls++;
    return token;
  }

  @override
  Future<void> connect(DiscordTokenBundle token) async {
    connectCalls++;
    lastConnected = token;
    if (connectFailuresRemaining > 0) {
      connectFailuresRemaining--;
      throw StateError('connection failed');
    }
  }

  @override
  Future<bool> revoke(String token) async {
    revokeCalls++;
    return true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }
}
