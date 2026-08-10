import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MarketplaceAddon manifest({
    String? version,
    Map<String, String> defaults = const {},
  }) => MarketplaceAddon(
    id: 'provider.test',
    name: 'Test provider',
    description: 'Fixture',
    author: 'TetoTV tests',
    manifestUri: Uri.parse('https://example.com/manifest.json'),
    repositoryUrl: 'https://example.com/marketplace.json',
    language: 'typescript',
    type: 'onlinestream-provider',
    locale: 'en',
    version: version,
    userConfigDefaults: defaults,
  );

  InstalledStreamingAddon installed({
    required MarketplaceAddon addon,
    String payload = 'export default class Provider {}',
  }) => InstalledStreamingAddon(
    manifest: addon,
    payload: payload,
    enabled: true,
    installedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test('marks newer provider code for an explicit update', () {
    final current = installed(addon: manifest(version: '1.0.0'));
    final state = MarketplaceState(installed: [current]);

    expect(state.updateAvailable(manifest(version: '1.1.0')), isTrue);
    expect(state.installed.single.payload, current.payload);
  });

  test('marks unresolved legacy configuration for explicit repair', () {
    final current = installed(
      addon: manifest(version: '1.0.0'),
      payload: 'const baseUrl = "{{api}}";',
    );
    final state = MarketplaceState(installed: [current]);

    expect(
      state.updateAvailable(
        manifest(version: '1.0.0', defaults: const {'api': 'https://api.test'}),
      ),
      isTrue,
    );
  });

  test('marks changed safe defaults for explicit update', () {
    final current = installed(
      addon: manifest(
        version: '1.0.0',
        defaults: const {'api': 'https://old.example'},
      ),
    );
    final state = MarketplaceState(installed: [current]);

    expect(
      state.updateAvailable(
        manifest(
          version: '1.0.0',
          defaults: const {'api': 'https://new.example'},
        ),
      ),
      isTrue,
    );
  });
}
