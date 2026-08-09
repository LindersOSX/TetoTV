import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stream source and keyboard preferences persist', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final controller = SettingsPreferencesController(storage);

    await controller.setDebridStreamsEnabled(false);
    await controller.setWebStreamsEnabled(false);
    await controller.setUseBuiltInKeyboard(false);
    await controller.setAutoSkipIntros(true);
    await controller.setAutoSkipOutros(true);

    final restored = SettingsPreferencesController(storage);
    await restored.load();
    expect(restored.state.debridStreamsEnabled, isFalse);
    expect(restored.state.webStreamsEnabled, isFalse);
    expect(restored.state.useBuiltInKeyboard, isFalse);
    expect(restored.state.autoSkipIntros, isTrue);
    expect(restored.state.autoSkipOutros, isTrue);
  });

  test('existing users retain both stream sources by default', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final controller = SettingsPreferencesController(
      const FlutterSecureStorage(),
    );
    await controller.load();

    expect(controller.state.debridStreamsEnabled, isTrue);
    expect(controller.state.webStreamsEnabled, isTrue);
    expect(controller.state.useBuiltInKeyboard, isTrue);
    expect(controller.state.autoSkipIntros, isFalse);
    expect(controller.state.autoSkipOutros, isFalse);
  });
}
