import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a compatible Seanime JavaScript stream provider', () {
    final addon = MarketplaceAddon.tryParse({
      'id': 'provider.test',
      'name': 'Provider Test',
      'description': 'A provider',
      'author': 'Tester',
      'manifestURI': 'https://example.com/manifest.json',
      'payloadURI': 'https://example.com/provider.js',
      'type': 'onlinestream-provider',
      'language': 'javascript',
      'lang': 'en',
    }, repositoryUrl: defaultMarketplaceRepositoryUrl);

    expect(addon, isNotNull);
    expect(addon!.isCompatible, isTrue);
    expect(addon.payloadUri.toString(), 'https://example.com/provider.js');
  });

  test('rejects private, insecure, and malformed repository resources', () {
    expect(safePublicHttpsUri('http://example.com/catalog.json'), isNull);
    expect(safePublicHttpsUri('https://127.0.0.1/catalog.json'), isNull);
    expect(safePublicHttpsUri('https://10.0.0.1/catalog.json'), isNull);
    expect(safePublicHttpsUri('https://192.168.1.20/catalog.json'), isNull);
    expect(
      MarketplaceAddon.tryParse({
        'id': '../bad',
        'name': 'Bad',
        'manifestURI': 'https://example.com/manifest.json',
      }, repositoryUrl: 'https://example.com/catalog.json'),
      isNull,
    );
  });

  test('rejects non-public IPv4 and IPv6 literal targets', () {
    for (final value in [
      'https://[::ffff:127.0.0.1]/catalog.json',
      'https://[::ffff:10.0.0.1]/catalog.json',
      'https://[::]/catalog.json',
      'https://[fe80::1]/catalog.json',
      'https://[fc00::1]/catalog.json',
      'https://[ff02::1]/catalog.json',
      'https://100.64.0.1/catalog.json',
      'https://224.0.0.1/catalog.json',
      'https://240.0.0.1/catalog.json',
    ]) {
      expect(safePublicHttpsUri(value), isNull, reason: value);
    }
    expect(safePublicHttpsUri('https://93.184.216.34/catalog.json'), isNotNull);
    expect(
      safePublicHttpsUri(
        'https://[2606:2800:220:1:248:1893:25c8:1946]/catalog.json',
      ),
      isNotNull,
    );
  });

  test('accepts TypeScript providers for install-time compilation', () {
    final addon = MarketplaceAddon.tryParse({
      'id': 'provider-ts',
      'name': 'TS Provider',
      'manifestURI': 'https://example.com/manifest.json',
      'type': 'onlinestream-provider',
      'language': 'typescript',
    }, repositoryUrl: 'https://example.com/catalog.json');

    expect(addon, isNotNull);
    expect(addon!.isCompatible, isTrue);
    expect(addon.isTypescript, isTrue);
  });

  test('accepts a bounded inline provider payload', () {
    final addon = MarketplaceAddon.tryParse({
      'id': 'provider-inline',
      'name': 'Inline Provider',
      'manifestURI': 'https://example.com/manifest.json',
      'type': 'onlinestream-provider',
      'language': 'typescript',
      'payload': 'class Provider {}',
    }, repositoryUrl: 'https://example.com/catalog.json');

    expect(addon, isNotNull);
    expect(addon!.inlinePayload, 'class Provider {}');
  });

  test('retains current Seanime marketplace user-config defaults', () {
    // Shape taken from the GojoWtf manifest referenced by the default
    // ASleepyDrink/Seanime-Stuff marketplace.
    final addon = MarketplaceAddon.tryParse({
      'id': 'gojowtf',
      'name': 'GojoWtf',
      'manifestURI':
          'https://raw.githubusercontent.com/kRYstall9/Seanime-streaming-providers/refs/heads/main/src/GojoWtf/manifest.json',
      'payloadURI':
          'https://raw.githubusercontent.com/kRYstall9/Seanime-streaming-providers/refs/heads/main/src/GojoWtf/provider.ts',
      'type': 'onlinestream-provider',
      'language': 'typescript',
      'lang': 'en',
      'userConfig': {
        'requiredConfig': false,
        'fields': [
          {'name': 'api', 'default': 'https://animetsu.net'},
          {'name': 'blobDomain', 'default': 'https://swiftstream.top'},
        ],
      },
    }, repositoryUrl: defaultMarketplaceRepositoryUrl);

    expect(addon!.userConfigDefaults, {
      'api': 'https://animetsu.net',
      'blobDomain': 'https://swiftstream.top',
    });
    final restored = MarketplaceAddon.tryParse(
      addon.toJson(),
      repositoryUrl: defaultMarketplaceRepositoryUrl,
    );
    expect(restored!.userConfigDefaults, addon.userConfigDefaults);
  });
}
