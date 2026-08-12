import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Discord activity uses the configured TetoTV app icon asset', () {
    final source = File(
      'android/app/src/main/cpp/discord_rich_presence.cpp',
    ).readAsStringSync();

    expect(
      source,
      contains('constexpr auto kAppIconAssetKey = "tetotv_app_icon";'),
    );
    expect(
      source,
      contains('assets.SetLargeImage(std::string{kAppIconAssetKey});'),
    );
    expect(source, contains('assets.SetLargeText(std::string{"TetoTV"});'));
    expect(source, contains('activity.SetAssets(std::move(assets));'));

    final setAssets = source.indexOf('activity.SetAssets(std::move(assets));');
    final publish = source.indexOf('g_client->UpdateRichPresence(');
    expect(setAssets, greaterThanOrEqualTo(0));
    expect(publish, greaterThan(setAssets));
  });

  test('Discord asset documentation preserves the portal contract', () {
    final notes = File(
      'third_party/discord_social_sdk/README.md',
    ).readAsStringSync();

    expect(notes, contains('Rich Presence large-image key: `tetotv_app_icon`'));
    expect(notes, contains('assets/branding/tetotv_icon.png'));
    expect(File('assets/branding/tetotv_icon.png').existsSync(), isTrue);
  });
}
