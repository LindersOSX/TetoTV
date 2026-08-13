import 'dart:async';

import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/web_stream_validator.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/data/composite_release_source.dart';
import 'package:anime_tv/features/streaming/data/all_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/premiumize_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/torbox_client.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/streaming/presentation/resolve_episode_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('similar releases prefer the same group, then provider', () {
    const sameGroup = ReleaseCandidate(
      infoHash: '1111111111111111111111111111111111111111',
      magnetUri: 'magnet:?xt=urn:btih:1111111111111111111111111111111111111111',
      releaseName: '[SubsPlease] Show - 02 [1080p].mkv',
      seeders: 5,
      sourceId: 'other-source',
      provider: 'Other provider',
    );
    const sameProvider = ReleaseCandidate(
      infoHash: '2222222222222222222222222222222222222222',
      magnetUri: 'magnet:?xt=urn:btih:2222222222222222222222222222222222222222',
      releaseName: '[Different] Show - 02 [1080p].mkv',
      seeders: 500,
      sourceId: 'preferred-source',
      provider: 'Preferred provider',
    );
    const unrelated = ReleaseCandidate(
      infoHash: '3333333333333333333333333333333333333333',
      magnetUri: 'magnet:?xt=urn:btih:3333333333333333333333333333333333333333',
      releaseName: '[Other] Show - 02 [1080p].mkv',
      seeders: 900,
      sourceId: 'other-source',
      provider: 'Other provider',
    );
    final releases = [unrelated, sameProvider, sameGroup]
      ..sort(
        (left, right) => compareStreamReleases(
          left,
          right,
          preferredProvider: 'Preferred provider',
          preferredReleaseGroup: 'subsplease',
        ),
      );

    expect(releases, [sameGroup, sameProvider, unrelated]);
    expect(releaseGroupKey('[SubsPlease] Show - 02'), 'subsplease');
    expect(releaseGroupKey('Show - 02'), isNull);
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      DebridService.realDebrid.tokenStorageKey: 'valid-manual-token',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.tetotv/android_tv'),
          (call) async =>
              call.method == 'getDeviceProfile' ? <String, Object?>{} : null,
        );
  });

  tearDown(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.tetotv/android_tv'),
          null,
        );
  });

  testWidgets('shows resolver errors and debounces repeated activation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var resolveCalls = 0;
    final failResolution = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _FakeReleaseSource(),
          ),
          debridStreamResolverFactoryProvider.overrideWithValue(({
            required service,
            required token,
            required source,
          }) {
            resolveCalls++;
            return _FailingResolver(failResolution.future);
          }),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('Dubbed release'));
    expect(find.text('Dubbed release'), findsOneWidget);
    expect(find.text('More filters'), findsOneWidget);
    expect(find.text('QUALITY'), findsNothing);
    expect(find.text('BATCHES ON'), findsNothing);

    await tester.tap(find.text('More filters'));
    // Provider discovery is intentionally progressive and may keep its
    // loading indicator active while filters remain fully interactive.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('QUALITY'), findsOneWidget);
    expect(find.text('BATCHES ON'), findsOneWidget);

    // A held/duplicated remote-select event must not add the same magnet twice.
    await tester.tap(find.text('Dubbed release'));
    await tester.tap(find.text('Dubbed release'), warnIfMissed: false);
    await tester.pump();
    expect(resolveCalls, 1);
    failResolution.complete();
    await _pumpUntilFound(tester, find.text('Retry'));

    expect(
      find.textContaining('Could not start this stream: Release unavailable'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(resolveCalls, 2);
  });

  testWidgets('keeps the picker usable while another resolver is loading', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final slow = Completer<List<ReleaseCandidate>>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            CompositeReleaseSource([
              const _FakeReleaseSource(),
              _CallbackReleaseSource('slow', () => slow.future),
            ]),
          ),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Dubbed release'));
    expect(find.text('Dubbed release'), findsOneWidget);
    expect(
      find.textContaining('Available results can be selected now'),
      findsOneWidget,
    );

    final focusedControl = find
        .ancestor(
          of: find.text('Dubbed release'),
          matching: find.byType(FocusableActionDetector),
        )
        .first;
    final focusNode = tester
        .widget<FocusableActionDetector>(focusedControl)
        .focusNode!;
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    slow.complete(const [
      ReleaseCandidate(
        infoHash: '89abcdef0123456789abcdef0123456789abcdef',
        magnetUri:
            'magnet:?xt=urn:btih:89abcdef0123456789abcdef0123456789abcdef',
        releaseName: 'Higher quality release',
        seeders: 50,
        sourceId: 'slow',
        isDubbed: true,
        quality: '2160p',
        codec: 'H.264',
      ),
    ]);
    // Do not wait for unrelated web providers to finish; this test verifies
    // that the debrid list reorders safely while discovery is still active.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Dubbed release'), findsOneWidget);
    expect(find.text('Higher quality release'), findsOneWidget);
    expect(focusNode.hasFocus, isTrue);
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is FocusableActionDetector &&
              identical(widget.focusNode, focusNode),
        ),
        matching: find.text('Dubbed release'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'autoplay launches an immediate debrid result without waiting for web',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final never = Completer<void>();
      addTearDown(() {
        if (!never.isCompleted) never.complete();
      });
      final webAggregator = _NeverCompletingWebAggregator(never.future);
      var resolverCalls = 0;
      var playerBuilds = 0;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) {
              playerBuilds++;
              return const Scaffold(body: Text('PLAYER OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _FakeReleaseSource(),
            ),
            webStreamAggregatorProvider.overrideWithValue(webAggregator),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ReadyResolver();
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('PLAYER OPENED'));
      expect(webAggregator.searchCalls, 1);
      expect(never.isCompleted, isFalse);
      expect(resolverCalls, 1);
      expect(playerBuilds, 1);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        resolverCalls,
        1,
        reason: 'late source progress must not relaunch',
      );
      expect(playerBuilds, 1);
    },
  );

  testWidgets(
    'autoplay ranks all concurrent repositories before checking debrid cache',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final slowSource = Completer<List<ReleaseCandidate>>();
      final neverWeb = Completer<void>();
      addTearDown(() {
        if (!slowSource.isCompleted) slowSource.complete(const []);
        if (!neverWeb.isCompleted) neverWeb.complete();
      });
      var resolverCalls = 0;
      PlaybackLaunch? opened;
      final source = CompositeReleaseSource([
        _CallbackReleaseSource(
          'fast',
          () async => const [
            ReleaseCandidate(
              infoHash: '1111111111111111111111111111111111111111',
              magnetUri:
                  'magnet:?xt=urn:btih:1111111111111111111111111111111111111111',
              releaseName: 'Fast repository result English Dub',
              seeders: 1,
              sourceId: 'fast',
              isDubbed: true,
              quality: '1080p',
              codec: 'H.264',
            ),
          ],
        ),
        _CallbackReleaseSource('slow', () => slowSource.future),
      ]);
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              opened = state.extra! as PlaybackLaunch;
              return const Scaffold(body: Text('RANKED PLAYER OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(source),
            webStreamAggregatorProvider.overrideWithValue(
              _NeverCompletingWebAggregator(neverWeb.future),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ReadyResolver();
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(
        tester,
        find.text('Fast repository result English Dub'),
      );
      expect(resolverCalls, 0);
      slowSource.complete(const [
        ReleaseCandidate(
          infoHash: '2222222222222222222222222222222222222222',
          magnetUri:
              'magnet:?xt=urn:btih:2222222222222222222222222222222222222222',
          releaseName: 'Better ranked result English Dub',
          seeders: 100,
          sourceId: 'slow',
          isDubbed: true,
          quality: '1080p',
          codec: 'H.264',
        ),
      ]);
      await _pumpUntilFound(tester, find.text('RANKED PLAYER OPENED'));

      expect(resolverCalls, 1);
      expect(opened?.selectedRelease.infoHash, startsWith('2222'));
      expect(neverWeb.isCompleted, isFalse);
    },
  );

  testWidgets(
    'web autoplay uses highest quality when preferred language is unavailable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = _NoopAddonStore();
      final webAggregator = _FixedWebAggregator([
        _webStream('480p'),
        _webStream('1080p'),
      ]);
      Uri? preflightUri;
      PlaybackLaunch? launch;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 424242,
                title: 'Sub-only Show',
                episode: 1,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              launch = state.extra! as PlaybackLaunch;
              return const Scaffold(body: Text('WEB PLAYER OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(null),
            addonStoreProvider.overrideWithValue(store),
            webStreamAggregatorProvider.overrideWithValue(webAggregator),
            webStreamPreflightProvider.overrideWithValue((uri, headers) async {
              preflightUri = uri;
              return ValidatedWebStream(
                uri: uri,
                headers: headers,
                contentType: 'application/vnd.apple.mpegurl',
              );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('WEB PLAYER OPENED'));
      expect(preflightUri, Uri.parse('https://cdn.example.com/1080p.m3u8'));
      expect(launch!.stream.uri, preflightUri);
    },
  );

  testWidgets(
    'release-specific failures continue through the fifth unique candidate',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var resolverCalls = 0;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) => const Scaffold(body: Text('PLAYER OPENED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _RankedReleaseSource(5),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return resolverCalls == 5
                  ? const _ReadyResolver()
                  : _ErrorResolver(
                      RealDebridException.fromApi(code: 35, httpStatus: 403),
                    );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('Release 5'));
      await tester.tap(find.text('Release 5'));
      await _pumpUntilFound(tester, find.text('PLAYER OPENED'));

      expect(resolverCalls, 5);
    },
  );

  testWidgets('release exhaustion reports the aggregate failure safely', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var resolverCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _RankedReleaseSource(3),
          ),
          debridStreamResolverFactoryProvider.overrideWithValue(({
            required service,
            required token,
            required source,
          }) {
            resolverCalls++;
            return _ErrorResolver(
              RealDebridException.fromApi(code: 35, httpStatus: 403),
            );
          }),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Release 3'));
    await tester.tap(find.text('Release 3'));
    await _pumpUntilFound(
      tester,
      find.textContaining('could not provide 3 different releases'),
    );

    expect(resolverCalls, 3);
    expect(find.textContaining('infringing_file'), findsNothing);
  });

  testWidgets(
    'uncached Real-Debrid releases report that no download was kept',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var resolverCalls = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _RankedReleaseSource(3),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ErrorResolver(
                DebridCacheMissException(DebridService.realDebrid),
              );
            }),
          ],
          child: const MaterialApp(
            home: ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(tester, find.text('Release 3'));
      await tester.tap(find.text('Release 3'));
      await _pumpUntilFound(
        tester,
        find.textContaining('No instantly cached Real-Debrid stream was found'),
      );

      expect(resolverCalls, 3);
      expect(find.textContaining('did not leave an uncached'), findsOneWidget);
    },
  );

  testWidgets('terminal Real-Debrid authorization failure stops failover', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var resolverCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _RankedReleaseSource(5),
          ),
          debridStreamResolverFactoryProvider.overrideWithValue(({
            required service,
            required token,
            required source,
          }) {
            resolverCalls++;
            return _ErrorResolver(
              RealDebridException.fromApi(code: 8, httpStatus: 401),
            );
          }),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Release 5'));
    await tester.tap(find.text('Release 5'));
    await _pumpUntilFound(tester, find.textContaining('Reconnect it'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(resolverCalls, 1);
    expect(find.textContaining('infringing_file'), findsNothing);
  });

  testWidgets(
    'terminal debrid cleanup failure stops failover and names the dashboard',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var resolverCalls = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _RankedReleaseSource(5),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ErrorResolver(
                DebridCleanupFailureException(DebridService.realDebrid),
              );
            }),
          ],
          child: const MaterialApp(
            home: ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(tester, find.text('Release 5'));
      await tester.tap(find.text('Release 5'));
      await _pumpUntilFound(
        tester,
        find.textContaining('Check your Real-Debrid dashboard'),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(resolverCalls, 1);
      expect(find.textContaining('Automatic failover stopped'), findsOneWidget);
    },
  );

  testWidgets('Real-Debrid rate limiting does not fan out across releases', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var resolverCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _RankedReleaseSource(5),
          ),
          debridStreamResolverFactoryProvider.overrideWithValue(({
            required service,
            required token,
            required source,
          }) {
            resolverCalls++;
            return _ErrorResolver(RealDebridException.fromApi(code: 34));
          }),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Release 5'));
    await tester.tap(find.text('Release 5'));
    await _pumpUntilFound(tester, find.textContaining('too many requests'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(resolverCalls, 1);
  });

  for (final testCase
      in <
        ({
          DebridService service,
          DebridProviderFailure error,
          String expectedMessage,
        })
      >[
        (
          service: DebridService.realDebrid,
          error: RealDebridException.fromApi(code: 8, httpStatus: 401),
          expectedMessage: 'Reconnect it',
        ),
        (
          service: DebridService.torBox,
          error: const TorBoxException(
            'TorBox token expired',
            code: 'AUTH_ERROR',
          ),
          expectedMessage: 'TorBox token expired',
        ),
        (
          service: DebridService.premiumize,
          error: const PremiumizeException(
            'Premiumize token expired',
            code: 'authentication_failed',
          ),
          expectedMessage: 'Premiumize token expired',
        ),
        (
          service: DebridService.allDebrid,
          error: const AllDebridException(
            'AllDebrid token expired',
            code: 'AUTH_BAD_APIKEY',
          ),
          expectedMessage: 'AllDebrid token expired',
        ),
      ]) {
    testWidgets(
      '${testCase.service.displayName} terminal provider errors stop Resolve '
      'candidate fan-out',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({
          testCase.service.tokenStorageKey: 'provider-token',
        });
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var resolverCalls = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              configuredReleaseSourceProvider.overrideWithValue(
                const _RankedReleaseSource(5),
              ),
              debridStreamResolverFactoryProvider.overrideWithValue(({
                required service,
                required token,
                required source,
              }) {
                expect(service, testCase.service);
                resolverCalls++;
                return _ErrorResolver(testCase.error);
              }),
            ],
            child: const MaterialApp(
              home: ResolveEpisodeScreen(
                episode: EpisodeReference(
                  anilistMediaId: 42,
                  title: 'Example Show',
                  episode: 1,
                ),
              ),
            ),
          ),
        );

        await _pumpUntilFound(tester, find.text('Release 5'));
        await tester.tap(find.text('Release 5'));
        await _pumpUntilFound(
          tester,
          find.textContaining(testCase.expectedMessage),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(resolverCalls, 1);
      },
    );
  }

  test(
    'stream filters distinguish language, quality, codec, HDR and batches',
    () {
      const release = ReleaseCandidate(
        infoHash: 'hash',
        magnetUri: 'magnet:?xt=urn:btih:hash',
        releaseName: 'Show S01 2160p HEVC HDR Dual Audio Batch',
        seeders: 50,
        sourceId: 'test',
        isDubbed: true,
        isBatch: true,
        isHdr: true,
        quality: '2160p',
        codec: 'HEVC',
      );

      expect(
        releaseMatchesStreamFilters(
          release,
          language: 'dub',
          quality: 'p2160',
          codec: 'hevc',
          hdr: 'hdr',
        ),
        isTrue,
      );
      expect(
        releaseMatchesStreamFilters(release, language: 'sub'),
        isTrue,
        reason: 'dual-audio files contain a usable original-language track',
      );
      expect(releaseMatchesStreamFilters(release, allowBatch: false), isFalse);
    },
  );

  test('preferred language is ranked before provider affinity on fallback', () {
    const dubbed = ReleaseCandidate(
      infoHash: 'dub',
      magnetUri: 'magnet:?xt=urn:btih:dub',
      releaseName: '[Other] Show 01 English Dub',
      seeders: 1,
      sourceId: 'other',
      isDubbed: true,
    );
    const subtitled = ReleaseCandidate(
      infoHash: 'sub',
      magnetUri: 'magnet:?xt=urn:btih:sub',
      releaseName: '[Preferred] Show 01',
      seeders: 500,
      sourceId: 'preferred',
      provider: 'Preferred provider',
    );

    expect(
      compareStreamReleases(
        dubbed,
        subtitled,
        preferredProvider: 'Preferred provider',
        preferredAudio: PlaybackAudioPreference.dub,
      ),
      lessThan(0),
    );
  });

  test('web qualities are ranked from highest to lowest', () {
    final streams = [
      _webStream('Auto'),
      _webStream('720p'),
      _webStream('4K UHD'),
      _webStream('1080p'),
    ]..sort(compareWebStreamsByQuality);

    expect(streams.map((item) => item.title), [
      '4K UHD',
      '1080p',
      '720p',
      'Auto',
    ]);
  });

  test('cached-only exhaustion message covers every debrid service', () {
    for (final service in DebridService.values) {
      final message = debridCacheExhaustedMessage(service, 3);
      expect(message, contains(service.displayName));
      expect(message, contains('3 releases'));
      expect(message, contains('did not leave an uncached cloud download'));
    }
  });
}

WebStreamResult _webStream(String quality) => WebStreamResult(
  providerId: quality,
  providerName: 'Provider',
  title: quality,
  uri: Uri.parse('https://cdn.example.com/$quality.m3u8'),
  quality: quality,
);

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

class _FakeReleaseSource implements ReleaseSource {
  const _FakeReleaseSource();

  @override
  String get id => 'fake';

  @override
  Future<List<ReleaseCandidate>> search(
    EpisodeReference episode,
  ) async => const [
    ReleaseCandidate(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
      magnetUri: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
      releaseName: 'Dubbed release',
      seeders: 10,
      sourceId: 'fake',
      isDubbed: true,
      quality: '1080p',
      codec: 'H.264',
    ),
  ];
}

class _CallbackReleaseSource implements ReleaseSource {
  const _CallbackReleaseSource(this.id, this.callback);

  @override
  final String id;
  final Future<List<ReleaseCandidate>> Function() callback;

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) => callback();
}

class _RankedReleaseSource implements ReleaseSource {
  const _RankedReleaseSource(this.count);

  final int count;

  @override
  String get id => 'ranked';

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) async => [
    for (var index = 1; index <= count; index++)
      ReleaseCandidate(
        infoHash: index.toString().padLeft(40, '0'),
        magnetUri: 'magnet:?xt=urn:btih:${index.toString().padLeft(40, '0')}',
        releaseName: 'Release $index',
        seeders: index,
        sourceId: id,
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      ),
  ];
}

class _FailingResolver implements StreamResolver {
  const _FailingResolver(this.failWhenReleased);

  final Future<void> failWhenReleased;

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    await failWhenReleased;
    throw StateError('Release unavailable');
  }
}

class _ReadyResolver implements StreamResolver {
  const _ReadyResolver();

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    yield StreamReady(
      uri: Uri.parse('https://debrid.example.com/episode.mkv'),
      displayName: 'Ready',
      debridService: DebridService.realDebrid,
    );
  }
}

class _ErrorResolver implements StreamResolver {
  const _ErrorResolver(this.error);

  final Object error;

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    throw error;
  }
}

class _NeverCompletingWebAggregator extends WebStreamAggregator {
  _NeverCompletingWebAggregator(this.never)
    : super(AddonStore(TetoTvDatabase.instance));

  final Future<void> never;
  int searchCalls = 0;

  @override
  Stream<WebStreamSearchProgress> searchIncrementally(
    EpisodeReference episode,
  ) async* {
    searchCalls++;
    yield const WebStreamSearchProgress(
      totalProviders: 1,
      pendingProviderNames: ['Never finishes'],
    );
    await never;
  }
}

class _FixedWebAggregator extends WebStreamAggregator {
  _FixedWebAggregator(this.streams)
    : super(AddonStore(TetoTvDatabase.instance));

  final List<WebStreamResult> streams;

  @override
  Stream<WebStreamSearchProgress> searchIncrementally(
    EpisodeReference episode,
  ) async* {
    yield WebStreamSearchProgress(
      aggregation: WebStreamAggregation(streams: streams),
      completedProviders: 1,
      totalProviders: 1,
    );
  }
}

class _NoopAddonStore extends AddonStore {
  _NoopAddonStore() : super(TetoTvDatabase.instance);

  @override
  Future<void> recordProviderSuccess(String id) async {}
}
