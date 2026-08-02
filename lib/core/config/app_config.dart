abstract final class AppConfig {
  static const authBrokerBaseUrl = String.fromEnvironment(
    'AUTH_BROKER_BASE_URL',
    defaultValue: '',
  );

  static const releaseResolverBaseUrl = String.fromEnvironment(
    'RELEASE_RESOLVER_BASE_URL',
  );
  static const stremioAddonManifestUrl = String.fromEnvironment(
    'STREMIO_ADDON_MANIFEST_URL',
    defaultValue: 'https://torrentio.strem.fun/manifest.json',
  );

  static bool get hasAuthBroker => authBrokerBaseUrl.trim().isNotEmpty;
  static bool get hasReleaseResolver =>
      releaseResolverBaseUrl.trim().isNotEmpty;
  static bool get hasStremioAddon => stremioAddonManifestUrl.trim().isNotEmpty;
}
