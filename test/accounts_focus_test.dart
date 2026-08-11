import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/presentation/accounts_screen.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('D-pad reaches Home shelves and switches to streaming', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: TvShortcuts(child: AccountsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'accounts.back');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.area.customize',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.shelf.tracking',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.shelf.history',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.provider',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.connect',
    );
  });

  testWidgets('D-pad reaches the bottom AniList save action on a TV canvas', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Optional private-repository token'), findsNothing);
    expect(find.text('Read-only GitHub token'), findsNothing);

    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.anilist.save',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('title language toggle is reachable from the header', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.title-language',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Titles: Romaji'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider selector only shows the chosen debrid configuration', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Advanced: personal token'), findsNothing);
    expect(find.text('TorBox API token'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('Advanced: personal token'), findsNothing);
    expect(find.text('Connect by QR'), findsOneWidget);
    expect(find.text('Debrid provider'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Advanced: personal token'), findsNothing);
    expect(find.text('TorBox API token'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D-pad reaches automatic and manual update controls', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.updates.automatic',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.updates.check',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.setup',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.updates.automatic',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.updates.check',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.discord',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.privacy',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.legal',
    );
    expect(find.text('Third-party notices'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('System settings expose a remote-selectable Discord invite QR', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('https://discord.gg/juC6k7d4WY'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.discord',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('connected debrid traversal only targets visible controls', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          realDebridSettingsControllerProvider.overrideWith(
            (_) => _ConnectedRealDebridController(),
          ),
        ],
        child: const MaterialApp(home: AccountsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.connect',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.streaming.debrid',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.connect',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.connect',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.streaming.marketplace',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.streaming.marketplace',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('organized settings sections fit a narrow mobile screen', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('Streaming'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('APPEARANCE & NAVIGATION'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Streaming'));
    await tester.pumpAndSettle();
    expect(find.text('DEBRID STREAMING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'device keyboard does not open while D-pad traverses token to Marketplace',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'input_use_built_in_keyboard': 'false',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AccountsScreen())),
      );
      await tester.pumpAndSettle();

      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'accounts.torbox.token',
      );
      expect(tester.testTextInput.isVisible, isFalse);

      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'accounts.streaming.marketplace',
      );
      expect(tester.testTextInput.isVisible, isFalse);

      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'accounts.torbox.token',
      );
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ConnectedRealDebridController extends RealDebridSettingsController {
  _ConnectedRealDebridController()
    : super(const FlutterSecureStorage(), (_) => throw UnimplementedError()) {
    state = const RealDebridSettingsState(
      hasSavedToken: true,
      account: RealDebridAccount(
        id: 1,
        username: 'connected-user',
        type: 'premium',
      ),
    );
  }

  @override
  Future<void> load() async {}
}
