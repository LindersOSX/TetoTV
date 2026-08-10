import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/application/source_pairing_controller.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/marketplace_client.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/marketplace/domain/source_pairing.dart';
import 'package:anime_tv/features/marketplace/presentation/source_pairing_dialog.dart';
import 'package:anime_tv/features/settings/presentation/initial_setup_screen.dart';
import 'package:anime_tv/features/settings/application/device_setup_controller.dart';
import 'package:anime_tv/features/streaming/application/user_torrent_sources_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TV setup places Sources between Debrid and tracking', (
    tester,
  ) async {
    await _pumpSetup(tester, const Size(1280, 720));

    // Skip setup starts focused. Down enters the persistent Continue action;
    // focus then stays there while each page advances.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    for (var index = 0; index < 4; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    _expectSourcesStep(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Add sources with phone'));
    await tester.pumpAndSettle();
    expect(find.byType(SourcePairingDialog), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Connect an anime list'), findsOneWidget);
  });

  testWidgets('Sources setup step fits a narrow phone without overflow', (
    tester,
  ) async {
    await _pumpSetup(tester, const Size(390, 844));
    for (var index = 0; index < 4; index++) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    _expectSourcesStep(tester);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSetup(WidgetTester tester, Size size) async {
  FlutterSecureStorage.setMockInitialValues({
    userTorrentSourceManifestsStorageKey:
        '["https://one.example/manifest.json",'
        '"https://two.example/manifest.json",'
        '"https://three.example/manifest.json"]',
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final marketplace = _StaticMarketplaceController(
    MarketplaceState(
      repositories: [
        AddonRepository(
          url: 'https://one.example/marketplace.json',
          updatedAt: DateTime(2026),
        ),
        AddonRepository(
          url: 'https://two.example/marketplace.json',
          updatedAt: DateTime(2026),
        ),
      ],
      loading: false,
    ),
  );
  final pairing = _StaticSourcePairingController();
  final deviceSetup = _StaticDeviceSetupController();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marketplaceControllerProvider.overrideWith((_) => marketplace),
        sourcePairingControllerProvider.overrideWith((_) => pairing),
        deviceSetupProvider.overrideWith((_) => deviceSetup),
      ],
      child: const MaterialApp(home: InitialSetupScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectSourcesStep(WidgetTester tester) {
  expect(find.text('Add streaming sources'), findsOneWidget);
  expect(find.textContaining('does not bundle or recommend'), findsOneWidget);
  expect(find.text('2'), findsOneWidget);
  expect(find.text('Marketplace repositories'), findsOneWidget);
  expect(find.text('3'), findsOneWidget);
  expect(find.text('Torrent source manifests'), findsOneWidget);
  expect(find.text('Add sources with phone'), findsOneWidget);
  expect(find.text('Open Marketplace manually'), findsOneWidget);
  expect(find.text('Skip setup'), findsOneWidget);
  expect(find.text('Back'), findsOneWidget);
  expect(find.text('Continue'), findsOneWidget);
}

class _StaticMarketplaceController extends MarketplaceController {
  _StaticMarketplaceController(MarketplaceState initial)
    : this._(AddonStore(TetoTvDatabase.instance), initial);

  _StaticMarketplaceController._(AddonStore store, MarketplaceState initial)
    : super(store, MarketplaceClient(store)) {
    state = initial;
  }

  @override
  Future<void> load() async {}
}

class _StaticSourcePairingController extends SourcePairingController {
  _StaticSourcePairingController()
    : super(
        () async => null,
        (_) => throw UnimplementedError(),
        (_) async => const SourceImportSummary(),
      );

  @override
  Future<void> start() async {
    state = const SourcePairingState(
      stage: SourcePairingStage.failed,
      message: 'Pairing fixture',
    );
  }
}

class _StaticDeviceSetupController extends DeviceSetupController {
  _StaticDeviceSetupController() : super(const FlutterSecureStorage()) {
    state = DeviceSetupState(
      report: buildDeviceCalibrationReport(const TvDeviceProfile.unknown()),
    );
  }

  @override
  Future<void> scan() async {}
}
