abstract final class AppConfig {
  static const authBrokerBaseUrl = String.fromEnvironment(
    'AUTH_BROKER_BASE_URL',
    defaultValue: 'https://tetotv-auth.onrender.com',
  );

  static const sourcePairingBrokerBaseUrl = String.fromEnvironment(
    'SOURCE_PAIRING_BROKER_BASE_URL',
    defaultValue: 'https://tetotv-bot.wisp.uno',
  );

  static const crashReportBaseUrl = String.fromEnvironment(
    'CRASH_REPORT_BASE_URL',
    defaultValue: 'https://tetotv-bot.wisp.uno',
  );

  static const diagnosticReportBaseUrl = String.fromEnvironment(
    'DIAGNOSTIC_REPORT_BASE_URL',
    defaultValue: 'https://tetotv-bot.wisp.uno',
  );

  static const releaseResolverBaseUrl = String.fromEnvironment(
    'RELEASE_RESOLVER_BASE_URL',
  );

  static bool get hasAuthBroker => authBrokerBaseUrl.trim().isNotEmpty;
  static bool get hasSourcePairingBroker =>
      sourcePairingBrokerBaseUrl.trim().isNotEmpty;
  static bool get hasCrashReportEndpoint =>
      crashReportBaseUrl.trim().isNotEmpty;
  static bool get hasDiagnosticReportEndpoint =>
      diagnosticReportBaseUrl.trim().isNotEmpty;
  static bool get hasReleaseResolver =>
      releaseResolverBaseUrl.trim().isNotEmpty;
}
