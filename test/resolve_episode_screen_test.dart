import 'dart:async';

import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/streaming/presentation/resolve_episode_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    await tester.pumpAndSettle();
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
      expect(releaseMatchesStreamFilters(release, language: 'sub'), isFalse);
      expect(releaseMatchesStreamFilters(release, allowBatch: false), isFalse);
    },
  );
}

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

class _FailingResolver implements StreamResolver {
  const _FailingResolver(this.failWhenReleased);

  final Future<void> failWhenReleased;

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    await failWhenReleased;
    throw StateError('Release unavailable');
  }
}
