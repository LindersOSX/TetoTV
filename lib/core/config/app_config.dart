abstract final class AppConfig {
  static const authBrokerBaseUrl = String.fromEnvironment(
    'AUTH_BROKER_BASE_URL',
    defaultValue: 'https://tetotv-auth.onrender.com',
  );

  static const releaseResolverBaseUrl = String.fromEnvironment(
    'RELEASE_RESOLVER_BASE_URL',
  );

  static bool get hasAuthBroker => authBrokerBaseUrl.trim().isNotEmpty;
  static bool get hasReleaseResolver =>
      releaseResolverBaseUrl.trim().isNotEmpty;
}
