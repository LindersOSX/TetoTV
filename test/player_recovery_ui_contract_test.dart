import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MPV, VLC, and Media3 announce successful automatic recovery', () {
    final mpv = File(
      'lib/features/player/presentation/tv_player_screen.dart',
    ).readAsStringSync();
    final vlc = File(
      'lib/features/player/presentation/vlc_tv_player_screen.dart',
    ).readAsStringSync();
    final media3 = File(
      'lib/features/player/presentation/native_media3_player_screen.dart',
    ).readAsStringSync();
    final native = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    for (final flutterPlayer in [mpv, vlc]) {
      expect(flutterPlayer, contains('_showAutomaticFailoverNotice('));
      expect(flutterPlayer, contains('option.stream,'));
      expect(flutterPlayer, contains('ready, candidate'));
      expect(flutterPlayer, contains('notify: false'));
    }
    expect(media3, contains('_queueAutomaticFailoverNotice('));
    expect(media3, contains('failoverNotice: pendingFailoverNotice'));
    expect(media3, contains('_handoffToMpvAfterFailure('));
    expect(native, contains('STATUS_FALLBACK_MPV'));
    expect(native, contains('EXTRA_FAILOVER_NOTICE'));
  });

  test('every player skip overlay has one-shot transport-aware autofocus', () {
    final mpv = File(
      'lib/features/player/presentation/tv_player_screen.dart',
    ).readAsStringSync();
    final vlc = File(
      'lib/features/player/presentation/vlc_tv_player_screen.dart',
    ).readAsStringSync();
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    for (final flutterPlayer in [mpv, vlc]) {
      expect(flutterPlayer, contains('PlayerSkipAutoFocusGate'));
      expect(flutterPlayer, contains('shouldAutoFocusSkipAction('));
      expect(flutterPlayer, contains('ModalRoute.of(context)?.isCurrent'));
      expect(flutterPlayer, contains('node: _transportFocusScope'));
    }
    expect(media3, contains('nativeShouldAutoFocusSkipAction('));
    expect(media3, contains('nativeTransportHubHasFocus()'));
    expect(media3, contains('autoFocusedSkipSegments.add(focusKey)'));
    expect(media3, contains('activeTrackDialog?.isShowing == true'));
  });
}
