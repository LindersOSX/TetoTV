import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'packaged QuickJS addon runtime resolves a typed stream',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'fixture-provider',
        'name': 'Fixture Provider',
        'description': 'Packaged runtime test provider',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      final addon = InstalledStreamingAddon(
        manifest: manifest,
        payload: r'''
          class Provider {
            getSettings() { return {episodeServers: ['Fixture'], supportsDub: false}; }
            async search(input) {
              console.debug('fixture search', input.query);
              return [{id: 'show', title: input.query, subOrDub: 'sub'}];
            }
            async findEpisodes(id) { return [{id: 'episode', number: 3, url: 'episode'}]; }
            async findEpisodeServer(episode, server) {
              return {server, headers: {Referer: 'https://example.com/'}, videoSources: [
                {url: 'https://example.com/episode-3.m3u8', quality: '1080p', subtitles: [
                  {url: 'https://example.com/episode-3-en.vtt', language: 'English'}
                ]}
              ]};
            }
          }
        ''',
        enabled: true,
        installedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      final results = await SeanimeJavascriptProvider(addon).streams(
        const EpisodeReference(
          anilistMediaId: 1,
          title: 'Fixture Anime',
          episode: 3,
        ),
      );

      expect(results, hasLength(1));
      expect(results.single.providerName, 'Fixture Provider');
      expect(results.single.uri.host, 'example.com');
      expect(results.single.quality, '1080p');
      expect(results.single.headers['Referer'], 'https://example.com/');
      expect(results.single.subtitleLanguage, 'English');
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'packaged QuickJS interrupts non-terminating scripts',
    (tester) async {
      final runtime = QuickJsRuntime2(timeout: 100);
      final stopwatch = Stopwatch()..start();
      try {
        final result = runtime.evaluate('for (;;) {}');
        stopwatch.stop();

        expect(result.isError, isTrue);
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 3)),
          reason: 'The native interrupt handler must bound addon execution.',
        );
      } finally {
        runtime.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  testWidgets(
    'repeated provider cancellation disposes native runtimes gracefully',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'cancellation-fixture-provider',
        'name': 'Cancellation Fixture Provider',
        'description': 'Waits forever until the host cancels it',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      final addon = InstalledStreamingAddon(
        manifest: manifest,
        payload: r'''
          class Provider {
            getSettings() { return {episodeServers: ['Fixture'], supportsDub: false}; }
            async search() { return await new Promise(() => {}); }
          }
        ''',
        enabled: true,
        installedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final provider = SeanimeJavascriptProvider(addon);

      for (var attempt = 0; attempt < 5; attempt++) {
        final cancellation = WebProviderCancellation();
        final search = provider.streams(
          const EpisodeReference(
            anilistMediaId: 1,
            title: 'Cancellation Fixture',
            episode: 1,
          ),
          cancellation: cancellation,
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        cancellation.cancel();
        await expectLater(
          search.timeout(const Duration(seconds: 3)),
          throwsA(isA<WebProviderSearchCancelled>()),
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'cancelling synchronous provider spin waits for native unwind',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'spin-cancellation-fixture-provider',
        'name': 'Spin Cancellation Fixture Provider',
        'description': 'Exercises native interruption during cancellation',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      final provider = SeanimeJavascriptProvider(
        InstalledStreamingAddon(
          manifest: manifest,
          payload: r'''
            class Provider {
              getSettings() { return {episodeServers: ['Fixture'], supportsDub: false}; }
              async search() { for (;;) {} }
            }
          ''',
          enabled: true,
          installedAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final cancellation = WebProviderCancellation();
      final stopwatch = Stopwatch()..start();
      final search = provider.streams(
        const EpisodeReference(
          anilistMediaId: 1,
          title: 'Spin Cancellation Fixture',
          episode: 1,
        ),
        cancellation: cancellation,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      cancellation.cancel();

      await expectLater(
        search.timeout(const Duration(seconds: 9)),
        throwsA(isA<WebProviderSearchCancelled>()),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 9)));
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
