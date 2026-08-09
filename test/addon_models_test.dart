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
}
