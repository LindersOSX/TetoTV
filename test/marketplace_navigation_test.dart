import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/marketplace_client.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/marketplace/presentation/marketplace_screen.dart';
import 'package:anime_tv/features/streaming/application/user_torrent_sources_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'production TV traversal follows Sources actions and the next source rows',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            marketplaceControllerProvider.overrideWith(
              (_) => _SeededMarketplaceController(),
            ),
            userTorrentSourcesControllerProvider.overrideWith(
              (_) => _SeededTorrentSourcesController(),
            ),
          ],
          child: const MaterialApp(
            home: TvShortcuts(child: MarketplaceScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_focusedControl(tester, find.text('Settings')), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        _focusedControl(tester, find.text('Add sources with phone')),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        _focusedControl(tester, find.text('Add Torrent source manifest')),
        isTrue,
      );

      // The third action wraps onto the next line at TetoTV's 1280-wide TV
      // canvas. Down should enter it instead of skipping to a later section.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        _focusedControl(tester, find.text('Add Marketplace repository')),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedControl(tester, find.text('Remove').at(0)), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedControl(tester, find.text('Remove').at(1)), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedControl(tester, find.text('Enabled')), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_focusedControl(tester, find.text('Remove').at(2)), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(_focusedControl(tester, find.text('Enabled')), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(_focusedControl(tester, find.text('Remove').at(1)), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(_focusedControl(tester, find.text('Remove').at(0)), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        _focusedControl(tester, find.text('Add Marketplace repository')),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        _focusedControl(tester, find.text('Add Torrent source manifest')),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

bool _focusedControl(WidgetTester tester, Finder label) {
  final detector = find
      .ancestor(of: label, matching: find.byType(FocusableActionDetector))
      .first;
  return tester.widget<FocusableActionDetector>(detector).focusNode?.hasFocus ??
      false;
}

class _SeededMarketplaceController extends MarketplaceController {
  _SeededMarketplaceController()
    : super(
        AddonStore(TetoTvDatabase.instance),
        MarketplaceClient(AddonStore(TetoTvDatabase.instance)),
      ) {
    state = MarketplaceState(
      repositories: [
        AddonRepository(
          url: 'https://example.com/marketplace.json',
          updatedAt: DateTime.utc(2026),
        ),
      ],
      loading: false,
    );
  }
}

class _SeededTorrentSourcesController extends UserTorrentSourcesController {
  _SeededTorrentSourcesController() : super(const FlutterSecureStorage()) {
    state = const UserTorrentSourcesState(
      manifestUrls: [
        'https://one.example/manifest.json',
        'https://two.example/manifest.json',
      ],
      loaded: true,
    );
  }
}
