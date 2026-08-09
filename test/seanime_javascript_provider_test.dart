import 'dart:io';

import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no-match provider outcomes are not treated as runtime failures', () {
    expect(
      isSeanimeProviderNoMatch(
        StateError('NO_MATCH: This provider has no matching title.'),
      ),
      isTrue,
    );
    expect(
      isSeanimeProviderNoMatch(
        StateError('NO_STREAM: The provider returned no compatible stream.'),
      ),
      isFalse,
    );
  });

  test(
    'isolated JavaScript provider resolves a typed web stream',
    () async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'fixture-provider',
        'name': 'Fixture Provider',
        'description': 'Test provider',
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
          async search(input) { return [{id: 'show', title: input.query, subOrDub: 'sub'}]; }
          async findEpisodes(id) { return [{id: 'episode', number: 3, url: 'episode'}]; }
          async findEpisodeServer(episode, server) {
            return {server, headers: {Referer: 'https://example.com/'}, videoSources: [
              {url: 'https://cdn.example.com/episode-3.m3u8', quality: '1080p', subtitles: [
                {url: 'https://cdn.example.com/episode-3-en.vtt', language: 'English'}
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
      expect(results.single.uri.host, 'cdn.example.com');
      expect(results.single.quality, '1080p');
      expect(results.single.headers['Referer'], 'https://example.com/');
      expect(results.single.subtitleLanguage, 'English');
    },
    timeout: const Timeout(Duration(seconds: 15)),
    skip: Platform.isWindows
        ? 'flutter_js loads its bridge from the packaged Windows app.'
        : false,
  );
}
