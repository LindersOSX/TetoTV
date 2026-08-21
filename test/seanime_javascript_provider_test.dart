import 'dart:io';

import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanitizes untrusted addon request and playback headers', () {
    final headers = sanitizeAddonHeaders({
      'Referer': 'https://example.com/',
      'Host': 'internal.example',
      'Content-Length': '999',
      'X-Injected': 'safe\r\nAuthorization: hidden',
      'Authorization': 'Bearer provider-session',
      'X-Api-Key': 'provider-api-secret',
      'X-Auth-Token': 'provider-auth-secret',
    });

    expect(headers['Referer'], 'https://example.com/');
    expect(headers['Authorization'], 'Bearer provider-session');
    expect(headers, isNot(contains('Host')));
    expect(headers, isNot(contains('Content-Length')));
    expect(headers, isNot(contains('X-Injected')));

    final redirected = sanitizeAddonHeaders(headers, stripCredentials: true);
    expect(redirected, isNot(contains('Authorization')));
    expect(redirected, isNot(contains('X-Api-Key')));
    expect(redirected, isNot(contains('X-Auth-Token')));
    expect(redirected['Referer'], 'https://example.com/');
  });

  test('preserves bounded multi-value response headers', () {
    final headers = sanitizeAddonResponseHeaders({
      'Content-Type': ['application/json', 'text/plain'],
      'Set-Cookie': ['session=one', 'theme=dark'],
      'Bad\r\nHeader': ['hidden'],
      'X-Injected': ['safe\r\nhidden'],
    });

    expect(headers['Content-Type'], ['application/json', 'text/plain']);
    expect(headers['Set-Cookie'], ['session=one', 'theme=dark']);
    expect(headers, isNot(contains('Bad\r\nHeader')));
    expect(headers, isNot(contains('X-Injected')));
  });

  test(
    'parses valid response cookies after malformed and oversized values',
    () {
      final cookies = parseAddonResponseCookies([
        'oversized=${List.filled(9000, 'x').join()}',
        'bad name=hidden',
        'session=fixture-cookie; Path=/; HttpOnly',
        'theme=dark; Secure; SameSite=Lax',
      ]);

      expect(cookies, {'session': 'fixture-cookie', 'theme': 'dark'});
    },
  );

  test(
    'bounds addon network concurrency, request count, and responses',
    () async {
      final budget = AddonRuntimeNetworkBudget(
        maximumRequests: 4,
        maximumConcurrentRequests: 1,
        maximumResponseBytes: 8,
      );
      await budget.acquire();
      var secondStarted = false;
      final second = budget.acquire().then((_) => secondStarted = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondStarted, isFalse);
      budget.release();
      await second;
      budget.recordResponse('1234');
      budget.release();

      await budget.acquire();
      expect(
        () => budget.recordResponse('56789'),
        throwsA(isA<FormatException>()),
      );
      budget.release();
      await expectLater(budget.acquire(), throwsA(isA<FormatException>()));

      final requestBudget = AddonRuntimeNetworkBudget(
        maximumRequests: 1,
        maximumConcurrentRequests: 1,
      );
      await requestBudget.acquire();
      requestBudget.release();
      await expectLater(
        requestBudget.acquire(),
        throwsA(isA<FormatException>()),
      );
    },
  );

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

  test('searches dedicated English and Romaji titles for legacy providers', () {
    expect(
      seanimeProviderSearchTitles(
        const EpisodeReference(
          anilistMediaId: 1,
          title: 'English Display',
          titleEnglish: 'English Display',
          titleRomaji: 'Dedicated Romaji',
          alternativeTitles: ['English Display', 'Alternate'],
          episode: 1,
        ),
      ),
      ['English Display', 'Dedicated Romaji', 'Alternate'],
    );
  });

  test('keeps all bounded media synonyms beyond the search-attempt cap', () {
    final episode = EpisodeReference(
      anilistMediaId: 1,
      title: 'Primary',
      titleEnglish: 'English',
      titleRomaji: 'Romaji',
      alternativeTitles: [
        'Alias 1',
        'Alias 2',
        'Alias 3',
        'Alias 4',
        'Site-specific alias',
      ],
      episode: 1,
    );

    expect(seanimeProviderSearchTitles(episode), hasLength(5));
    expect(
      seanimeProviderMediaSynonyms(episode),
      contains('Site-specific alias'),
    );
    expect(seanimeProviderMediaSynonyms(episode), isNot(contains('Primary')));
  });

  test('provider stream errors are actionable and hide Dart prefixes', () {
    final message = seanimeProviderFailureMessage(
      StateError(
        'NO_STREAM: The provider found the episode but returned no compatible stream.',
      ),
    );

    expect(
      isSeanimeProviderNoStream(StateError('NO_STREAM: unavailable')),
      isTrue,
    );
    expect(message, contains('provider found the episode'));
    expect(message, isNot(contains('Bad state')));
    expect(message, isNot(contains('NO_STREAM')));

    final workerMessage = seanimeProviderFailureMessage(
      StateError(
        'Bad state: NO_STREAM: The provider found the episode but returned no compatible stream.',
      ),
    );
    expect(workerMessage, contains('provider found the episode'));
    expect(workerMessage, isNot(contains('Bad state')));
    expect(workerMessage, isNot(contains('NO_STREAM')));
  });

  test('provider failure markers expose only bounded stage and reason', () {
    final error = StateError(
      'Bad state: NO_STREAM: https://media.example/private?token=secret '
      '[stage=server; reason=http_403]',
    );
    final details = seanimeProviderFailureDetails(error);
    final message = seanimeProviderFailureMessage(error);

    expect(details?.stage, 'server');
    expect(details?.reason, 'http_403');
    expect(message, contains('HTTP 403'));
    expect(message, isNot(contains('token')));
    expect(message, isNot(contains('media.example')));
    expect(
      seanimeProviderFailureDetails(
        StateError('[stage=arbitrary; reason=raw_secret]'),
      ),
      isNull,
    );
  });

  test('provider diagnostics include provenance without full URLs', () {
    final manifest = MarketplaceAddon.tryParse({
      'id': 'fixture-provider',
      'name': 'Fixture Provider',
      'manifestURI': 'https://code.example/providers/manifest.json?secret=one',
      'payloadURI': 'https://cdn.example/provider.js?secret=two',
      'version': '1.2.3',
      'type': 'onlinestream-provider',
      'language': 'javascript',
    }, repositoryUrl: 'https://catalog.example/main.json?secret=three')!;
    final provider = SeanimeJavascriptProvider(
      InstalledStreamingAddon(
        manifest: manifest,
        payload: 'class Provider {}',
        enabled: true,
        installedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    final message = seanimeProviderDiagnosticMessage(
      provider,
      StateError(
        'NO_STREAM: token=hidden [stage=server; reason=empty_sources]',
      ),
    );

    expect(message, contains('provider=fixture-provider'));
    expect(message, contains('version=1.2.3'));
    expect(message, contains('repositoryHost=catalog.example'));
    expect(message, contains('executableHost=cdn.example'));
    expect(message, contains('stage=server'));
    expect(message, contains('reason=empty_sources'));
    expect(message, isNot(contains('hidden')));
    expect(message, isNot(contains('?')));
  });

  test('bounds Seanime request timeouts to the remaining runtime', () {
    expect(addonRequestTimeout(0.05), const Duration(milliseconds: 100));
    expect(addonRequestTimeout(2), const Duration(seconds: 2));
    expect(
      addonRequestTimeout(30, maximum: const Duration(seconds: 4)),
      const Duration(seconds: 4),
    );
    expect(
      addonRequestTimeout(null, maximum: const Duration(seconds: 3)),
      const Duration(seconds: 3),
    );
    expect(
      addonRequestTimeout(30, maximum: const Duration(seconds: 6)),
      const Duration(seconds: 6),
      reason: 'one dead host must leave time for provider fallback endpoints',
    );
  });

  test('bounds Seanime sleep without extending the runtime deadline', () {
    expect(
      addonSleepDuration(200, remaining: const Duration(seconds: 5)),
      const Duration(milliseconds: 200),
    );
    expect(
      addonSleepDuration(5000, remaining: const Duration(seconds: 5)),
      const Duration(seconds: 1),
    );
    expect(
      addonSleepDuration(500, remaining: const Duration(milliseconds: 75)),
      const Duration(milliseconds: 75),
    );
    expect(
      addonSleepDuration(
        double.infinity,
        remaining: const Duration(seconds: 5),
      ),
      Duration.zero,
    );
    expect(
      addonSleepDuration(-1, remaining: const Duration(seconds: 5)),
      Duration.zero,
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
