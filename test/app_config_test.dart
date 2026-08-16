import 'package:anime_tv/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production service endpoints remain independently configurable', () {
    expect(AppConfig.authBrokerBaseUrl, 'https://tetotv-auth.onrender.com');
    expect(
      AppConfig.sourcePairingBrokerBaseUrl,
      'https://tetotv-updates-lindows.onrender.com',
    );
    expect(
      AppConfig.sourcePairingBrokerBaseUrl,
      isNot(AppConfig.authBrokerBaseUrl),
    );
    expect(AppConfig.crashReportBaseUrl, 'https://tetotv-bot.wisp.uno');
    expect(
      AppConfig.crashReportBaseUrl,
      isNot(AppConfig.sourcePairingBrokerBaseUrl),
    );
    expect(AppConfig.hasCrashReportEndpoint, isTrue);
  });
}
