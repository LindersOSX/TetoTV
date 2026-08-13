import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter and Media3 HUDs keep the same control order and labels', () {
    final flutterChrome = File(
      'lib/features/player/presentation/teto_player_chrome.dart',
    ).readAsStringSync();
    final nativeChrome = File(
      'android/app/src/main/res/layout/tetotv_player_controls.xml',
    ).readAsStringSync();
    final nativeStrings = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();

    _expectInOrder(flutterChrome, const [
      "label: 'Back \${seekBackSeconds}s'",
      "label: isPlaying ? 'Pause' : 'Play'",
      "label: 'Forward \${seekForwardSeconds}s'",
      "label: 'Audio'",
      "label: 'CC'",
      "label: 'Size'",
      "label: 'Picture'",
      "label: 'Player'",
      "label: 'Sources'",
      "label: 'Options'",
    ]);
    _expectInOrder(nativeChrome, const [
      '@id/exo_rew',
      '@id/exo_play_pause',
      '@id/exo_ffwd',
      '@+id/tetotv_audio_tracks',
      '@+id/tetotv_caption_tracks',
      '@+id/tetotv_caption_size',
      '@+id/tetotv_picture_mode',
      '@+id/tetotv_fix_video',
      '@+id/tetotv_player_sources',
      '@+id/tetotv_player_options',
    ]);

    for (final label in [
      '>Audio<',
      '>CC<',
      '>Size<',
      '>Picture<',
      '>Player<',
      '>Sources<',
      '>Options<',
    ]) {
      expect(nativeStrings, contains(label));
    }
  });

  test('all HUDs reveal the final controls instead of clipping focus', () {
    final flutterChrome = File(
      'lib/features/player/presentation/teto_player_chrome.dart',
    ).readAsStringSync();
    final nativeChrome = File(
      'android/app/src/main/res/layout/tetotv_player_controls.xml',
    ).readAsStringSync();
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    expect(flutterChrome, contains('Scrollable.ensureVisible('));
    expect(
      flutterChrome,
      contains('ScrollPositionAlignmentPolicy.keepVisibleAtEnd'),
    );
    expect(nativeChrome, contains('android:clipChildren="false"'));
    expect(nativeChrome, contains('@+id/tetotv_sources_control'));
    expect(nativeChrome, contains('@drawable/tetotv_ic_sources'));
    expect(media3, contains('container.requestRectangleOnScreen('));
    expect(media3, contains('STATUS_NEXT_STREAM'));
    expect(media3, contains('EXTRA_HAS_DIRECT_SOURCES'));
  });

  test('all player engines keep five-second hide and Down dismissal', () {
    final flutterPolicy = File(
      'lib/features/player/presentation/player_control_overlay.dart',
    ).readAsStringSync();
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    expect(
      flutterPolicy,
      contains('playerControlsIdleTimeout = Duration(seconds: 5)'),
    );
    expect(media3, contains('CONTROLLER_HIDE_TIMEOUT_MS = 5_000L'));
    expect(media3, contains('KeyEvent.KEYCODE_DPAD_DOWN'));
    expect(media3, contains('playerView.hideController()'));
  });

  test('Media3 shortcut cleanup and buffering intent stay coherent', () {
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    final dispatchStart = media3.indexOf('override fun dispatchKeyEvent');
    final dispatchEnd = media3.indexOf(
      '/** Keyboard/gamepad shortcuts',
      dispatchStart,
    );
    final dispatch = media3.substring(dispatchStart, dispatchEnd);
    final cleanup = dispatch.indexOf('consumedNavigationKeyUp?.let');
    final modalGuard = dispatch.indexOf('exitDialog?.isShowing == true');
    expect(cleanup, greaterThanOrEqualTo(0));
    expect(cleanup, lessThan(modalGuard));
    expect(
      dispatch,
      contains('if (event.keyCode !in MODAL_CHROME_SHORTCUT_KEYS)'),
    );
    for (final dialogKey in [
      'KEYCODE_S',
      'KEYCODE_C',
      'KEYCODE_M',
      'KEYCODE_MENU',
      'KEYCODE_BUTTON_Y',
    ]) {
      expect(media3, contains(dialogKey));
    }
    expect(media3, contains('consumedNavigationKeyUp = null'));
    expect(
      media3,
      contains(
        'player.playWhenReady && player.playbackState != Player.STATE_ENDED',
      ),
    );
    expect(
      media3,
      contains(
        'KeyEvent.KEYCODE_K -> if (isPlaybackIntended()) player.pause() '
        'else player.play()',
      ),
    );
    expect(media3, contains('playing = isPlaybackIntended()'));
  });

  test('Media3 restores the prior read-only progress bar', () {
    final flutterChrome = File(
      'lib/features/player/presentation/teto_player_chrome.dart',
    ).readAsStringSync();
    final nativeChrome = File(
      'android/app/src/main/res/layout/tetotv_player_controls.xml',
    ).readAsStringSync();
    final nativePlayer = File(
      'android/app/src/main/res/layout/activity_media3_player.xml',
    ).readAsStringSync();
    final timeBar = RegExp(
      r'<androidx\.media3\.ui\.DefaultTimeBar[\s\S]*?/>',
    ).firstMatch(nativeChrome)?.group(0);

    expect(timeBar, isNotNull);
    expect(timeBar, contains('android:layout_height="32dp"'));
    // 4dp margin + 14dp centering inside the 32dp touch target keeps the
    // visible 4dp bar exactly 18dp below the action row.
    expect(timeBar, contains('android:layout_marginTop="4dp"'));
    expect(timeBar, contains('app:bar_height="4dp"'));
    expect(timeBar, contains('app:touch_target_height="32dp"'));
    expect(timeBar, contains('android:focusable="false"'));
    expect(timeBar, contains('android:clickable="false"'));
    expect(timeBar, contains('android:longClickable="false"'));
    expect(timeBar, contains('android:importantForAccessibility="no"'));
    expect(timeBar, contains('app:scrubber_disabled_size="0dp"'));
    expect(timeBar, contains('app:scrubber_dragged_size="0dp"'));
    expect(timeBar, contains('app:scrubber_enabled_size="0dp"'));
    expect(nativePlayer, contains('app:time_bar_scrubbing_enabled="false"'));
    expect(flutterChrome, isNot(contains('PlayerScrubController')));
    expect(flutterChrome, isNot(contains('onSeek')));
    expect(flutterChrome, isNot(contains('player-progress-scrubber')));
  });

  test('Media3 resource geometry and palette mirror the MPV master HUD', () {
    final flutterChrome = File(
      'lib/features/player/presentation/teto_player_chrome.dart',
    ).readAsStringSync();
    final nativeChrome = File(
      'android/app/src/main/res/layout/tetotv_player_controls.xml',
    ).readAsStringSync();
    final nativeStyles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();
    final card = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_card_background.xml',
    ).readAsStringSync();
    final badge = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_badge_background.xml',
    ).readAsStringSync();
    final normalControl = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_control_pill_background.xml',
    ).readAsStringSync();
    final primaryControl = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_control_primary_background.xml',
    ).readAsStringSync();
    final scrim = File(
      'android/app/src/main/res/drawable/tetotv_player_controls_scrim.xml',
    ).readAsStringSync();

    // Lock the shared MPV/VLC source of truth first.
    for (final token in [
      'constraints: const BoxConstraints(maxWidth: 1280)',
      'horizontalInset = compact ? 12.0 : 28.0',
      'bottomInset = compact ? 10.0 : 24.0',
      'color: const Color(0xD6080808)',
      'height: 40',
      'color: primary ? AppColors.accent : const Color(0x8F242429)',
      'minHeight: compact ? 3 : 4',
    ]) {
      expect(flutterChrome, contains(token));
    }

    // Media3 keeps the same non-compact geometry and typography.
    for (final token in [
      'android:layout_marginStart="28dp"',
      'android:layout_marginBottom="24dp"',
      'android:paddingStart="18dp"',
      'android:paddingTop="14dp"',
      'android:paddingBottom="12dp"',
      'android:textSize="24sp"',
      'android:layout_height="40dp"',
      'android:layout_marginTop="10dp"',
      'app:bar_height="4dp"',
      'app:played_color="#FFFF496A"',
      'app:unplayed_color="#3DFFFFFF"',
      'android:textColor="#FFB7AEB1"',
    ]) {
      expect(nativeChrome, contains(token));
    }
    expect(
      RegExp(
        r'<style name="TetoTVPlayerControlPill">[\s\S]*?'
        r'<item name="android:layout_height">40dp</item>',
      ).hasMatch(nativeStyles),
      isTrue,
    );
    expect(
      RegExp(
        r'<style name="TetoTVPlayerControlIcon"[\s\S]*?'
        r'<item name="android:layout_height">40dp</item>',
      ).hasMatch(nativeStyles),
      isTrue,
    );
    for (final token in ['#D6080808', '16dp', '1.4dp', '#C7E52B50']) {
      expect(card, contains(token));
    }
    for (final token in ['#33E52B50', '#59E52B50']) {
      expect(badge, contains(token));
    }
    expect(normalControl, contains('#8F242429'));
    expect(normalControl, isNot(contains('#FF3A3A40')));
    expect(primaryControl, contains('#FFE52B50'));
    expect(scrim, contains('#00000000'));
    expect(scrim, isNot(contains('<gradient')));
  });

  test('Media3 clearly disables unavailable engine track controls', () {
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    expect(media3, contains('audioTrackButton.isEnabled = hasAudio'));
    expect(media3, contains('captionTrackButton.isEnabled = hasCaptions'));
    expect(
      media3,
      contains('setChromeControlAvailable(audioControlContainer, hasAudio)'),
    );
    expect(
      media3,
      contains(
        'setChromeControlAvailable(captionControlContainer, hasCaptions)',
      ),
    );
    expect(media3, contains('Player.COMMAND_SEEK_BACK'));
    expect(media3, contains('Player.COMMAND_SEEK_FORWARD'));
  });

  test('native pill surfaces defer accessibility to labeled icon controls', () {
    final nativeStyles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();

    expect(
      nativeStyles,
      contains('<item name="android:importantForAccessibility">no</item>'),
    );
    expect(
      RegExp(
        r'<style name="TetoTVPlayerControlPill">[\s\S]*?'
        r'<item name="android:layout_height">40dp</item>',
      ).hasMatch(nativeStyles),
      isTrue,
    );
    expect(
      RegExp(
        r'<style name="TetoTVPlayerControlIcon"[\s\S]*?'
        r'<item name="android:layout_height">40dp</item>',
      ).hasMatch(nativeStyles),
      isTrue,
    );
  });

  test('Media3 uses app-owned rounded icons and Teto focus treatment', () {
    final nativeChrome = File(
      'android/app/src/main/res/layout/tetotv_player_controls.xml',
    ).readAsStringSync();
    final normalFocus = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_control_pill_background.xml',
    ).readAsStringSync();
    final primaryFocus = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_control_primary_background.xml',
    ).readAsStringSync();

    expect(nativeChrome, isNot(contains('@android:drawable/ic_menu_')));
    for (final icon in ['picture', 'player', 'options']) {
      expect(nativeChrome, contains('@drawable/tetotv_ic_$icon'));
      final vector = File(
        'android/app/src/main/res/drawable/tetotv_ic_$icon.xml',
      ).readAsStringSync();
      expect(vector, contains('<vector'));
      expect(vector, contains('android:strokeLineCap="round"'));
    }
    for (final focusDrawable in [normalFocus, primaryFocus]) {
      expect(focusDrawable, contains('android:state_activated="true"'));
      expect(focusDrawable, contains('android:width="3dp"'));
      expect(focusDrawable, contains('android:color="#FFFF5C78"'));
      expect(focusDrawable, contains('android:color="#E6000000"'));
      expect(focusDrawable, isNot(contains('android:color="#FFFFFFFF"')));
    }
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();
    expect(media3, contains('control.setOnFocusChangeListener'));
    expect(media3, contains('container.isActivated = hasFocus'));
  });
}

void _expectInOrder(String source, List<String> tokens) {
  var previous = -1;
  for (final token in tokens) {
    final index = source.indexOf(token, previous + 1);
    expect(
      index,
      greaterThan(previous),
      reason: 'Missing/out of order: $token',
    );
    previous = index;
  }
}
