import 'dart:convert';

import 'package:anime_tv/features/marketplace/data/marketplace_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const repository = 'https://example.com/marketplace/main.json';

  test('accepts casing-only catalog and manifest ID drift', () {
    final catalog = parseMarketplaceCatalog(
      jsonEncode([
        {
          'id': 'animeAV1',
          'name': 'AnimeAV1',
          'manifestURI': 'https://example.com/animeav1/manifest.json',
          'type': 'onlinestream-provider',
          'language': 'javascript',
        },
      ]),
      repositoryUrl: repository,
    );
    final merged = validateAndMergeMarketplaceManifest(catalog.single, {
      'id': 'animeav1',
      'name': 'AnimeAV1',
      'manifestURI': 'https://example.com/animeav1/manifest.json',
      'payloadURI': 'https://example.com/animeav1/provider.ts',
      'type': 'onlinestream-provider',
      'language': 'typescript',
    });

    expect(catalog, hasLength(1));
    expect(merged.id, 'animeAV1');
    expect(merged.language, 'typescript');
    expect(merged.isCompatible, isTrue);
  });

  test('does not accept a genuinely different manifest identity', () {
    final summary = parseMarketplaceCatalog(
      jsonEncode([
        {
          'id': 'trusted-provider',
          'name': 'Trusted Provider',
          'manifestURI': 'https://example.com/provider/manifest.json',
          'type': 'onlinestream-provider',
          'language': 'javascript',
        },
      ]),
      repositoryUrl: repository,
    ).single;

    expect(
      () => validateAndMergeMarketplaceManifest(summary, {
        'id': 'different-provider',
        'name': 'Different Provider',
        'manifestURI': 'https://example.com/provider/manifest.json',
        'payloadURI': 'https://example.com/provider/provider.js',
        'type': 'onlinestream-provider',
        'language': 'javascript',
      }),
      throwsFormatException,
    );
  });

  test('adapts common wrapped catalogs and URI/language aliases', () {
    final catalog = parseMarketplaceCatalog(
      jsonEncode({
        'data': {
          'providers': [
            {
              'id': 'wrapped-provider',
              'name': 'Wrapped Provider',
              'manifestUrl': 'https://example.com/wrapped/manifest.json',
              'payloadUrl': 'https://example.com/wrapped/provider.js',
              'type': 'onlinestream-provider',
              'language': 'js',
              'locale': 'en',
            },
            {
              'id': 'not-a-stream-provider',
              'name': 'UI plugin',
              'manifestURI': 'https://example.com/plugin/manifest.json',
              'type': 'plugin',
              'language': 'javascript',
            },
          ],
        },
      }),
      repositoryUrl: repository,
    );

    expect(catalog, hasLength(1));
    expect(catalog.single.id, 'wrapped-provider');
    expect(catalog.single.language, 'javascript');
    expect(catalog.single.locale, 'en');
    expect(
      catalog.single.manifestUri,
      Uri.parse('https://example.com/wrapped/manifest.json'),
    );
    expect(
      catalog.single.payloadUri,
      Uri.parse('https://example.com/wrapped/provider.js'),
    );
  });

  test('still rejects catalogs without a bounded provider list', () {
    expect(
      () => parseMarketplaceCatalog(
        jsonEncode({
          'metadata': {'name': 'not a catalog'},
        }),
        repositoryUrl: repository,
      ),
      throwsFormatException,
    );
  });

  test('rejects wrappers nested beyond the compatibility depth bound', () {
    Object nested = <String, Object?>{'providers': <Object?>[]};
    for (var depth = 0; depth < 9; depth++) {
      nested = <String, Object?>{'data': nested};
    }

    expect(
      () => parseMarketplaceCatalog(
        jsonEncode(nested),
        repositoryUrl: repository,
      ),
      throwsFormatException,
    );
  });
}
