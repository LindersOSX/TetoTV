import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_controller.dart';
import 'package:anime_tv/features/watch_together/data/watch_party_client.dart';
import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:anime_tv/features/watch_together/presentation/watch_together_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('TV lobby initially focuses Create room and keeps code visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WatchPartyController(_ScreenWatchPartyClient());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPreferencesProvider.overrideWith(
            (_) => _WatchSettingsController(),
          ),
          watchPartyControllerProvider.overrideWith((_) => controller),
        ],
        child: const MaterialApp(home: WatchTogetherScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Watch Together'), findsOneWidget);
    expect(find.byKey(const ValueKey('watch-together-create')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('watch-together-code-input')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'watch-together.create',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('active room exposes QR, share code, counts, and end action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WatchPartyController(_ScreenWatchPartyClient());
    expect(await controller.create(), isTrue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPreferencesProvider.overrideWith(
            (_) => _WatchSettingsController(),
          ),
          watchPartyControllerProvider.overrideWith((_) => controller),
        ],
        child: const MaterialApp(home: WatchTogetherScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('watch-together-qr')), findsOneWidget);
    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.text('1 guests • 0 ready'), findsOneWidget);
    expect(find.text('Copy code'), findsOneWidget);
    expect(find.text('End room'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'watch-together.copy',
    );
    expect(tester.takeException(), isNull);
  });
}

class _WatchSettingsController extends SettingsPreferencesController {
  _WatchSettingsController() : super(const FlutterSecureStorage()) {
    state = const SettingsPreferences(loaded: true);
  }

  @override
  Future<void> load() async {}
}

class _ScreenWatchPartyClient extends WatchPartyClient {
  _ScreenWatchPartyClient()
    : super(baseUrl: 'https://tetotv.example', dio: Dio());

  final session = WatchPartySession(
    roomCode: 'ABCD2345',
    token: List.filled(43, 'a').join(),
    role: WatchPartyRole.host,
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 6)),
    watchUrl: Uri.parse('https://tetotv.example/watch?room=ABCD2345'),
  );

  @override
  Future<WatchPartyCreated> create() async =>
      WatchPartyCreated(session: session);

  @override
  Future<WatchPartySnapshot> snapshot(WatchPartySession session) async =>
      WatchPartySnapshot(
        roomCode: session.roomCode,
        role: session.role,
        revision: 0,
        playing: false,
        position: Duration.zero,
        effectiveAt: DateTime.now().toUtc(),
        serverTime: DateTime.now().toUtc(),
        participantCount: 1,
        readyCount: 0,
        expiresAt: session.expiresAt,
      );

  @override
  Future<void> leave(WatchPartySession session) async {}
}
