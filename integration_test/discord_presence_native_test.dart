import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled Discord Social SDK initializes through JNI', (_) async {
    final info = await AndroidTvBridge.instance.discordSdkInfo();

    expect(info['available'], isTrue);
    expect(info['applicationId'], '1536801401710055474');
    expect(info['version'], '1.10.18369');
    expect(info['status'], isA<String>());
  });
}
