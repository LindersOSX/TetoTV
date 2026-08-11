import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Discord callback activity preserves the mobile OAuth return contract', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = RegExp(
      r'<activity\s+[^>]*android:name="com\.discord\.socialsdk\.AuthenticationActivity"[^>]*>[\s\S]*?</activity>',
    ).firstMatch(manifest)?.group(0);

    expect(
      activity,
      isNotNull,
      reason: 'Discord AuthenticationActivity must be declared by the app.',
    );
    expect(activity, contains('android:exported="true"'));
    expect(activity, contains('android:launchMode="singleTask"'));
    expect(
      activity,
      isNot(contains('android:taskAffinity')),
      reason:
          'Overriding the SDK activity affinity prevents Android from reusing '
          'the pending singleTask instance for the OAuth callback.',
    );

    final schemes = RegExp(
      r'android:scheme="([^"]+)"',
    ).allMatches(activity!).map((match) => match.group(1)).toList();
    expect(schemes, const ['discord-1536801401710055474']);
  });
}
