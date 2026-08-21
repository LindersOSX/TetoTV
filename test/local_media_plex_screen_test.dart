import 'dart:async';
import 'dart:convert';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/features/local_media/application/local_media_controller.dart';
import 'package:anime_tv/features/local_media/application/plex_controller.dart';
import 'package:anime_tv/features/local_media/data/jellyfin_client.dart';
import 'package:anime_tv/features/local_media/data/plex_client.dart';
import 'package:anime_tv/features/local_media/domain/plex_models.dart';
import 'package:anime_tv/features/local_media/presentation/local_media_screen.dart';
import 'package:anime_tv/features/player/domain/library_playback_request.dart';
import 'package:anime_tv/features/player/presentation/library_tv_player_screen.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();
  const androidChannel = MethodChannel('dev.tetotv/android_tv');

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, null);
  });

  testWidgets(
    'Plex browse uses bounded byte artwork and sends token only as playback header',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Map<Object?, Object?>? playerArguments;
      final playerExit = Completer<Map<String, Object?>>();
      addTearDown(() {
        if (!playerExit.isCompleted) {
          playerExit.complete({
            'status': 'exit',
            'positionMs': 0,
            'durationMs': 0,
          });
        }
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, (call) async {
            if (call.method == 'startNativePlayer') {
              playerArguments = (call.arguments as Map)
                  .cast<Object?, Object?>();
              return playerExit.future;
            }
            return null;
          });

      final localController = LocalMediaController(
        storage,
        JellyfinClient(),
        AndroidTvBridge.instance,
      );
      await localController.load();
      final plexClient = _ScreenPlexClient();
      final plexController = PlexController(storage, plexClient);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        FlutterSecureStorage.setMockInitialValues({});
      });
      await plexController.connect(
        address: 'https://plex.example.com/base',
        token: _token,
      );
      await plexController.openLibrary(plexClient.library);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localMediaControllerProvider.overrideWith((_) => localController),
            plexControllerProvider.overrideWith((_) => plexController),
            settingsPreferencesProvider.overrideWith(
              (_) => _Media3SettingsController(),
            ),
          ],
          child: const MaterialApp(home: LocalMediaScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final outerScroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('plex-item-movie-1')),
        250,
        scrollable: outerScroll,
      );
      await tester.pumpAndSettle();

      expect(find.text('Movie One'), findsOneWidget);
      expect(plexClient.loadedImages, [
        Uri.parse(
          'https://plex.example.com/base/library/metadata/movie-1/thumb/1',
        ),
      ]);
      final plexImages = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byKey(const ValueKey('plex-item-movie-1')),
              matching: find.byType(Image),
            ),
          )
          .toList();
      expect(plexImages, hasLength(1));
      expect(_isMemoryImage(plexImages.single.image), isTrue);
      final networkImages = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => _networkImage(image.image))
          .whereType<NetworkImage>();
      expect(
        networkImages.every((image) => image.headers?['X-Plex-Token'] == null),
        isTrue,
      );

      final rowFocus = tester
          .widget<FocusableActionDetector>(
            find.descendant(
              of: find.byKey(const ValueKey('plex-item-movie-1')),
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!;
      rowFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'top-level.active-navigation',
      );

      await tester.tap(find.text('Movie One'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      final libraryPlayer = tester.widget<LibraryTvPlayerScreen>(
        find.byType(LibraryTvPlayerScreen),
      );
      final request = libraryPlayer.request;
      expect(request.source.toString(), isNot(contains(_token)));
      expect(request.headers['X-Plex-Token'], _token);
      expect(request.artworkUrl, isNot(contains(_token)));
      expect(
        request.allowsFlutterEngines,
        isFalse,
        reason: 'Plex credentials stay inside origin-scoped native Media3',
      );
      expect(request.isolation.animeTrackingEnabled, isFalse);
      expect(request.isolation.animeCheckpointEnabled, isFalse);
      expect(request.isolation.aniSkipEnabled, isFalse);
      expect(request.isolation.nextEpisodeEnabled, isFalse);
      expect(request.checkpointKey, isNot(contains(_token)));
      expect(request.timelineIdentity, isNot(contains(_token)));

      final report = request.onProgress!;
      final firstSample = DateTime.utc(2026, 8, 20, 12);
      final reportsBeforeSamples = plexClient.timelineStates.length;
      await report(
        LibraryPlaybackProgress(
          position: const Duration(seconds: 20),
          duration: const Duration(minutes: 90),
          playing: true,
          sampledAt: firstSample,
        ),
      );
      expect(plexClient.timelineStates.length, reportsBeforeSamples + 1);
      await report(
        LibraryPlaybackProgress(
          position: const Duration(seconds: 22),
          duration: const Duration(minutes: 90),
          playing: true,
          sampledAt: firstSample.add(const Duration(seconds: 2)),
        ),
      );
      expect(
        plexClient.timelineStates.length,
        reportsBeforeSamples + 1,
        reason: 'ordinary progress writes are throttled before secure storage',
      );
      await report(
        LibraryPlaybackProgress(
          position: const Duration(seconds: 23),
          duration: const Duration(minutes: 90),
          playing: false,
          sampledAt: firstSample.add(const Duration(seconds: 3)),
        ),
      );
      expect(plexClient.timelineStates.last, isFalse);

      expect(playerArguments, isNotNull);
      expect(
        playerArguments!['source'],
        'https://plex.example.com/base/library/parts/600/file.mkv',
      );
      expect(playerArguments!['source'].toString(), isNot(contains(_token)));
      final headers = (playerArguments!['headers'] as Map)
          .cast<String, String>();
      expect(headers['X-Plex-Token'], _token);
      expect(headers, isNot(contains('Accept')));
      expect(playerArguments!['trustedLocalSource'], isTrue);
      expect(playerArguments!['libraryPlayback'], isTrue);
      expect(
        playerArguments!['allowEngineSwitch'],
        isFalse,
        reason: 'authenticated Plex headers must stay in native Media3',
      );
      expect(
        playerArguments!['artworkUrl'],
        'https://plex.example.com/base/library/metadata/movie-1/thumb/1',
      );
      expect(playerArguments!['artworkUrl'], isNot(contains(_token)));
      playerExit.complete({'status': 'exit', 'positionMs': 0, 'durationMs': 0});
      await tester.pumpAndSettle();
      if (find.byType(LibraryTvPlayerScreen).evaluate().isNotEmpty) {
        Navigator.of(tester.element(find.byType(LibraryTvPlayerScreen))).pop();
        await tester.pumpAndSettle();
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      expect(plexClient.timelineStates, containsAllInOrder([true, false]));
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

NetworkImage? _networkImage(ImageProvider provider) => switch (provider) {
  NetworkImage value => value,
  ResizeImage value => _networkImage(value.imageProvider),
  _ => null,
};

bool _isMemoryImage(ImageProvider provider) => switch (provider) {
  MemoryImage _ => true,
  ResizeImage value => _isMemoryImage(value.imageProvider),
  _ => false,
};

const _token = 'plex-access-token-123456';

class _ScreenPlexClient extends PlexClient {
  final loadedImages = <Uri>[];
  final timelineStates = <bool>[];

  final library = const PlexLibrary(
    key: '1',
    title: 'Movies',
    type: PlexMediaType.movie,
  );

  @override
  Future<PlexServerIdentity> serverIdentity(PlexConnection connection) async =>
      const PlexServerIdentity(
        name: 'Living Room Plex',
        machineIdentifier: 'machine-12345678',
        version: '1.41.4',
      );

  @override
  Future<List<PlexLibrary>> libraries(PlexConnection connection) async => [
    library,
  ];

  @override
  Future<PlexPage<PlexMediaItem>> libraryItems(
    PlexConnection connection,
    PlexLibrary library, {
    int start = 0,
    int size = 100,
  }) async => const PlexPage(
    items: [
      PlexMediaItem(
        ratingKey: 'movie-1',
        key: '/library/metadata/movie-1',
        title: 'Movie One',
        type: PlexMediaType.movie,
        year: 2026,
        thumb: '/library/metadata/movie-1/thumb/1',
        parts: [PlexMediaPart(key: '/library/parts/600/file.mkv')],
      ),
    ],
    totalCount: 1,
    offset: 0,
    nextOffset: 1,
  );

  @override
  Future<Uint8List> imageBytes(PlexConnection connection, Uri uri) async {
    loadedImages.add(uri);
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
  }

  @override
  Future<void> reportTimeline(
    PlexConnection connection,
    PlexMediaItem item, {
    required Duration position,
    required bool playing,
  }) async {
    timelineStates.add(playing);
  }
}

class _Media3SettingsController extends SettingsPreferencesController {
  _Media3SettingsController() : super(const FlutterSecureStorage()) {
    state = const SettingsPreferences(
      loaded: true,
      preferredPlayer: PreferredPlayer.media3,
    );
  }

  @override
  Future<void> load() async {}
}
