import 'package:anime_tv/features/marketplace/data/marketplace_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applies marketplace defaults to Seanime payload placeholders', () {
    const payload = '''
class Provider {
  baseUrl = "{{api}}";
  blobDomain = "{{blobDomain}}";
}
''';

    final configured = applyAddonConfigDefaults(payload, const {
      'api': 'https://animetsu.net',
      'blobDomain': 'https://swiftstream.top',
    });

    expect(configured, contains('baseUrl = "https://animetsu.net"'));
    expect(configured, contains('blobDomain = "https://swiftstream.top"'));
    expect(configured, isNot(contains('{{')));
  });
}
