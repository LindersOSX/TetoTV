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
    await controller.setHomeLayout(HomeLayout.compact);
    await controller.setShowMyList(false);
    await controller.setShowDiscover(false);
    await controller.setShowCalendar(false);
    await controller.setShowHero(false);
    await controller.setShowPosterMetadata(false);
    await controller.setShowCardSubtitles(false);
    await controller.setTrackerUpdateThreshold(TrackerUpdateThreshold.halfway);

    final restored = SettingsPreferencesController(storage);
    await restored.load();
    expect(restored.state.debridStreamsEnabled, isFalse);
    expect(restored.state.webStreamsEnabled, isFalse);
    expect(restored.state.useBuiltInKeyboard, isFalse);
    expect(restored.state.autoSkipIntros, isTrue);
    expect(restored.state.autoSkipOutros, isTrue);
    expect(restored.state.homeLayout, HomeLayout.compact);
    expect(restored.state.showMyList, isFalse);
    expect(restored.state.showDiscover, isFalse);
    expect(restored.state.showCalendar, isFalse);
    expect(restored.state.showHero, isFalse);
    expect(restored.state.showPosterMetadata, isFalse);
    expect(restored.state.showCardSubtitles, isFalse);
    expect(
      restored.state.trackerUpdateThreshold,
      TrackerUpdateThreshold.halfway,
    );
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
    expect(controller.state.homeLayout, HomeLayout.cinematic);
    expect(controller.state.showMyList, isTrue);
    expect(controller.state.showDiscover, isTrue);
    expect(controller.state.showCalendar, isTrue);
    expect(
      controller.state.trackerUpdateThreshold,
      TrackerUpdateThreshold.nearlyFinished,
    );
  });

  test('tracker threshold only completes a whole episode when crossed', () {
    const duration = Duration(minutes: 24);

    expect(
      trackerUpdateThresholdReached(
        position: const Duration(minutes: 11),
        duration: duration,
        threshold: TrackerUpdateThreshold.halfway,
      ),
      isFalse,
    );
    expect(
      trackerUpdateThresholdReached(
        position: const Duration(minutes: 12),
        duration: duration,
        threshold: TrackerUpdateThreshold.halfway,
      ),
      isTrue,
    );
    expect(
      trackerUpdateThresholdReached(
        position: duration,
        duration: duration,
        threshold: TrackerUpdateThreshold.episodeEnd,
      ),
      isFalse,
    );
    expect(
      trackerUpdateThresholdReached(
        position: duration,
        duration: duration,
        threshold: TrackerUpdateThreshold.episodeEnd,
        playbackEnded: true,
      ),
      isTrue,
    );
  });
}
