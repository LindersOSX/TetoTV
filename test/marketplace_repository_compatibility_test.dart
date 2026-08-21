import 'dart:convert';
import 'dart:io';

import 'package:anime_tv/features/marketplace/data/marketplace_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const repository = 'https://example.com/marketplace/main.json';

  group('current user-supplied Seanime catalog shapes', () {
    String fixture(String name) =>
        File('test/fixtures/marketplace/$name').readAsStringSync();

    test('Bas catalog retains advisory working and broken status', () {
      const source =
          'https://raw.githubusercontent.com/Bas1874/Seanime-Marketplace/'
          'refs/heads/main/Marketplace/Main.json';
      final catalog = parseMarketplaceCatalog(
        fixture('bas_marketplace_excerpt.json'),
        repositoryUrl: source,
      );

      expect(catalog.map((addon) => addon.id), ['allmangaanime', 'anidb']);
      expect(catalog.first.reportedWorking, isFalse);
      expect(catalog.first.reportedBroken, isTrue);
      expect(catalog.last.reportedWorking, isTrue);
      expect(catalog.last.lastWorkingVersion, '3.10.2');
    });

    test('ASleepyDrink catalog keeps status unknown when it is absent', () {
      const source =
          'https://raw.githubusercontent.com/ASleepyDrink/Seanime-Stuff/'
          'refs/heads/main/marketplace.json';
      final catalog = parseMarketplaceCatalog(
        fixture('sleepy_marketplace_excerpt.json'),
        repositoryUrl: source,
      );

      expect(catalog, hasLength(2));
      expect(catalog.every((addon) => addon.reportedWorking == null), isTrue);
      expect(catalog.every((addon) => !addon.reportedBroken), isTrue);
    });

    test('Pal catalog accepts casing drift without changing visible ID', () {
      const source =
          'https://raw.githubusercontent.com/Pal-droid/Seanime-Providers/'
          'main/marketplace/main.json';
      final catalog = parseMarketplaceCatalog(
        fixture('pal_marketplace_excerpt.json'),
        repositoryUrl: source,
      );

      expect(catalog, hasLength(2));
      expect(catalog.first.id, 'animeAV1');
      expect(catalog.first.isCompatible, isTrue);
    });

    test(
      'Carloss catalog is valid but contains no online-stream providers',
      () {
        const source =
            'https://raw.githubusercontent.com/Carloss616/seanime-extensions/'
            'main/marketplace.json';
        final catalog = parseMarketplaceCatalog(
          fixture('carloss_marketplace_excerpt.json'),
          repositoryUrl: source,
        );

        expect(catalog, isEmpty);
      },
    );
  });

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

  test('adapts a bounded ID-keyed catalog map', () {
    final catalog = parseMarketplaceCatalog(
      jsonEncode({
        'marketplace': {
          'extensions': {
            'mapped-provider': {
              'identifier': 'mapped-provider',
              'title': 'Mapped provider',
              'manifest': './mapped/manifest.json',
              'kind': 'anime_stream_provider',
              'runtime': 'js',
            },
          },
        },
      }),
      repositoryUrl: repository,
    );

    expect(catalog, hasLength(1));
    expect(catalog.single.id, 'mapped-provider');
    expect(
      catalog.single.manifestUri,
      Uri.parse('https://example.com/marketplace/mapped/manifest.json'),
    );
  });

  test('unwraps a manifest and preserves catalog-only executable fields', () {
    final summary = parseMarketplaceCatalog(
      jsonEncode([
        {
          'id': 'wrapped-manifest-provider',
          'name': 'Catalog name',
          'description': 'Catalog description',
          'author': 'Catalog author',
          'manifestURI': 'https://example.com/provider/manifest.json',
          'payloadURI': 'https://example.com/provider/provider.js',
          'type': 'onlinestream-provider',
          'language': 'javascript',
          'lang': 'en',
          'workingTag': true,
        },
      ]),
      repositoryUrl: repository,
    ).single;

    final merged = validateAndMergeMarketplaceManifest(summary, {
      'data': {
        'provider': {
          'id': 'WRAPPED-MANIFEST-PROVIDER',
          'name': 'Manifest name',
          'description': '',
          'author': 'Unknown',
          'manifestURI': './manifest.json',
        },
      },
    });

    expect(merged.name, 'Manifest name');
    expect(merged.description, 'Catalog description');
    expect(merged.author, 'Catalog author');
    expect(merged.language, 'javascript');
    expect(merged.type, 'onlinestream-provider');
    expect(merged.reportedWorking, isTrue);
    expect(
      merged.payloadUri,
      Uri.parse('https://example.com/provider/provider.js'),
    );
    expect(merged.isCompatible, isTrue);
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
