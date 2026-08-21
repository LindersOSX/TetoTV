import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/marketplace_client.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MarketplaceAddon manifest({
    String id = 'provider.test',
    String repositoryUrl = 'https://example.com/marketplace.json',
    String manifestUrl = 'https://example.com/manifest.json',
    String? version,
    Map<String, String> defaults = const {},
    bool? reportedWorking,
    bool reportedBroken = false,
    bool isDeprecated = false,
  }) => MarketplaceAddon(
    id: id,
    name: 'Test provider',
    description: 'Fixture',
    author: 'TetoTV tests',
    manifestUri: Uri.parse(manifestUrl),
    repositoryUrl: repositoryUrl,
    language: 'typescript',
    type: 'onlinestream-provider',
    locale: 'en',
    version: version,
    userConfigDefaults: defaults,
    reportedWorking: reportedWorking,
    reportedBroken: reportedBroken,
    isDeprecated: isDeprecated,
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

  test('never treats a different repository as an installed addon update', () {
    final current = installed(addon: manifest(version: '1.0.0'));
    final spoofed = MarketplaceAddon(
      id: current.manifest.id,
      name: 'Spoofed provider',
      description: 'Fixture',
      author: 'Unknown',
      manifestUri: Uri.parse('https://untrusted.example/manifest.json'),
      repositoryUrl: 'https://untrusted.example/marketplace.json',
      language: 'javascript',
      type: 'onlinestream-provider',
      locale: 'en',
      version: '99.0.0',
    );
    final state = MarketplaceState(installed: [current]);

    expect(addonProvenanceMatches(current, spoofed), isFalse);
    expect(state.updateAvailable(spoofed), isFalse);
  });

  test('treats casing-only IDs as one same-repository identity', () {
    final current = installed(addon: manifest(version: '1.0.0'));
    final casingUpdate = MarketplaceAddon(
      id: 'PROVIDER.TEST',
      name: 'Test provider',
      description: 'Fixture',
      author: 'TetoTV tests',
      manifestUri: current.manifest.manifestUri,
      repositoryUrl: current.manifest.repositoryUrl,
      language: 'typescript',
      type: 'onlinestream-provider',
      locale: 'en',
      version: '1.1.0',
    );
    final state = MarketplaceState(installed: [current]);

    expect(state.installedById(casingUpdate.id), same(current));
    expect(addonProvenanceMatches(current, casingUpdate), isTrue);
    expect(state.updateAvailable(casingUpdate), isTrue);
  });

  test('prefers a maintained duplicate over repository URL order', () {
    final unknownOld = manifest(
      repositoryUrl: 'https://a.example/marketplace.json',
      manifestUrl: 'https://a.example/provider/manifest.json',
      version: '1.0.0',
    );
    final maintained = manifest(
      repositoryUrl: 'https://z.example/marketplace.json',
      manifestUrl: 'https://z.example/provider/manifest.json',
      version: '1.2.0',
      reportedWorking: true,
    );
    final brokenNewest = manifest(
      repositoryUrl: 'https://b.example/marketplace.json',
      manifestUrl: 'https://b.example/provider/manifest.json',
      version: '99.0.0',
      reportedBroken: true,
    );

    final selected = selectMarketplaceCatalogCandidates([
      unknownOld,
      brokenNewest,
      maintained,
    ]);

    expect(selected, hasLength(1));
    expect(selected.single.repositoryUrl, maintained.repositoryUrl);
    expect(selected.single.version, '1.2.0');
  });

  test('shares advisory status only for the identical manifest URI', () {
    final sharedManifest = manifest(
      repositoryUrl: 'https://mirror-a.example/marketplace.json',
      manifestUrl: 'https://source.example/provider/manifest.json',
      version: '1.0.0',
    );
    final brokenReport = manifest(
      repositoryUrl: 'https://mirror-b.example/marketplace.json',
      manifestUrl: 'https://source.example/provider/manifest.json',
      version: '1.0.0',
      reportedBroken: true,
    );
    final differentImplementation = manifest(
      repositoryUrl: 'https://mirror-c.example/marketplace.json',
      manifestUrl: 'https://other.example/provider/manifest.json',
      version: '0.9.0',
      reportedWorking: true,
    );

    final selected = selectMarketplaceCatalogCandidates([
      sharedManifest,
      brokenReport,
      differentImplementation,
    ]);

    expect(selected.single.manifestUri, differentImplementation.manifestUri);
    expect(selected.single.reportedWorking, isTrue);
    final sharedOnly = selectMarketplaceCatalogCandidates([
      sharedManifest,
      brokenReport,
    ]);
    expect(sharedOnly.single.reportedBroken, isTrue);
    expect(sharedOnly.single.reportedWorking, isFalse);
  });

  test('keeps installed repository provenance across duplicate catalogs', () {
    final owned = manifest(
      repositoryUrl: 'https://owned.example/marketplace.json',
      manifestUrl: 'https://owned.example/provider/manifest.json',
      version: '1.0.0',
    );
    final replacement = manifest(
      repositoryUrl: 'https://other.example/marketplace.json',
      manifestUrl: 'https://other.example/provider/manifest.json',
      version: '9.0.0',
      reportedWorking: true,
    );

    final selected = selectMarketplaceCatalogCandidates(
      [replacement, owned],
      installed: [installed(addon: owned)],
    );

    expect(selected.single.repositoryUrl, owned.repositoryUrl);
    expect(selected.single.version, '1.0.0');
  });

  test('rejects a non-public repository before persisting it', () async {
    final store = AddonStore(TetoTvDatabase.instance);
    final controller = MarketplaceController(
      store,
      MarketplaceClient(store),
      targetValidator: (_) async =>
          throw const FormatException('private target'),
    );

    final error = await controller.addRepository(
      'https://private.example/marketplace.json',
    );

    expect(error, 'The repository must resolve to a public HTTPS address.');
    expect(controller.state.repositories, isEmpty);
  });

  test(
    'blocks a cross-repository ID collision before downloading code',
    () async {
      final store = AddonStore(TetoTvDatabase.instance);
      final current = installed(addon: manifest(version: '1.0.0'));
      final client = _DownloadMustNotRunClient(store);
      final controller = _SeededMarketplaceController(
        store,
        client,
        MarketplaceState(installed: [current], loading: false),
      );
      final spoofed = MarketplaceAddon(
        id: current.manifest.id,
        name: 'Spoofed provider',
        description: 'Fixture',
        author: 'Unknown',
        manifestUri: Uri.parse('https://untrusted.example/manifest.json'),
        repositoryUrl: 'https://untrusted.example/marketplace.json',
        language: 'javascript',
        type: 'onlinestream-provider',
        locale: 'en',
      );

      await expectLater(
        controller.install(spoofed),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('already owns this provider ID'),
          ),
        ),
      );
      expect(client.downloadAttempted, isFalse);
    },
  );

  test(
    'blocks a casing-only cross-repository ID collision before download',
    () async {
      final store = AddonStore(TetoTvDatabase.instance);
      final current = installed(addon: manifest(version: '1.0.0'));
      final client = _DownloadMustNotRunClient(store);
      final controller = _SeededMarketplaceController(
        store,
        client,
        MarketplaceState(installed: [current], loading: false),
      );
      final spoofed = MarketplaceAddon(
        id: 'PROVIDER.TEST',
        name: 'Spoofed provider',
        description: 'Fixture',
        author: 'Unknown',
        manifestUri: Uri.parse('https://untrusted.example/manifest.json'),
        repositoryUrl: 'https://untrusted.example/marketplace.json',
        language: 'javascript',
        type: 'onlinestream-provider',
        locale: 'en',
      );

      await expectLater(
        controller.install(spoofed),
        throwsA(isA<FormatException>()),
      );
      expect(client.downloadAttempted, isFalse);
    },
  );
}

class _DownloadMustNotRunClient extends MarketplaceClient {
  _DownloadMustNotRunClient(super.store);

  bool downloadAttempted = false;

  @override
  Future<InstalledStreamingAddon> downloadAddon(
    MarketplaceAddon summary,
  ) async {
    downloadAttempted = true;
    throw StateError('Untrusted payload was downloaded.');
  }
}

class _SeededMarketplaceController extends MarketplaceController {
  _SeededMarketplaceController(
    super.store,
    super.client,
    MarketplaceState initial,
  ) {
    state = initial;
  }
}
