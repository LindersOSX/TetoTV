import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MPV completion, skip, and engine handoff remain single-owner', () {
    final source = _read(
      'lib/features/player/presentation/tv_player_screen.dart',
    );

    expect(source, contains('if (completed) _handlePlaybackCompleted()'));
    expect(
      source,
      contains('if (_completionHandled || _engineHandoffInProgress) return'),
    );
    expect(
      source,
      contains('if (_skipInProgress || _engineHandoffInProgress)'),
    );
    expect(source, contains('safeSkipSegmentTarget('));
    expect(
      source,
      contains("_showTrackMessage('Could not skip this segment')"),
    );
    expect(
      RegExp(r'if \(!_engineHandoffInProgress\)\n\s+Video\(').hasMatch(source),
      isTrue,
    );

    final prepare = _methodSlice(
      source,
      'Future<bool> _prepareForEngineHandoff',
      'Future<void> _fallbackToVlc',
    );
    _expectInOrder(prepare, const [
      'await WidgetsBinding.instance.endOfFrame',
      'await _waitForPlayerMutations()',
      'await _waitForSeekDrain()',
      'await _progressSubscription?.cancel()',
      'await _player.stop()',
      'await _player.dispose()',
      '_playerReleasedForHandoff = true',
    ]);
    expect(
      source,
      contains('if (!_engineHandoffInProgress && !_playerReleasedForHandoff)'),
    );
  });

  test('VLC router and auto-next await decoder disposal', () {
    final source = _read(
      'lib/features/player/presentation/vlc_tv_player_screen.dart',
    );
    expect(source, contains('safeSkipSegmentTarget('));
    expect(source, contains("_showMessage('Could not skip this segment')"));
    expect(source, contains('_controllerReleasedForHandoff = true'));

    final prepare = _methodSlice(
      source,
      'Future<bool> _prepareForEngineHandoff',
      'Future<void> _handoffTo',
    );
    _expectInOrder(prepare, const [
      '_controller = null',
      'await WidgetsBinding.instance.endOfFrame',
      'await _waitForSeekDrain()',
      'await _waitForControllerMutations()',
      'controller.removeListener(_onValueChanged)',
      'await controller.stop()',
      'await controller.dispose()',
      '_controllerReleasedForHandoff = true',
    ]);

    final handoff = _methodSlice(
      source,
      'Future<void> _handoffTo',
      'Future<void> _openPlayerPicker',
    );
    _expectInOrder(handoff, const [
      'await _prepareForEngineHandoff(position)',
      'callback(selected, position, stream, release, directStreams)',
    ]);

    final nextEpisode = _methodSlice(
      source,
      'Future<void> _playNextEpisode',
      '@override\n  Widget build',
    );
    _expectInOrder(nextEpisode, const [
      'await _prepareForEngineHandoff(completedPosition)',
      'context.pushReplacement(',
    ]);
  });

  test('Media3 releases native playback before returning an engine result', () {
    final source = _read(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    );

    final finish = _methodSlice(
      source,
      'private fun finishWithResult',
      'private fun memoryClassMb',
    );
    _expectInOrder(finish, const [
      'if (resultSent) return',
      'resultSent = true',
      'setResult(RESULT_OK, result)',
      'releasePlaybackResources()',
      'finish()',
    ]);
    expect(source, contains('if (playbackResourcesReleased) return'));
    expect(source, contains('seekPastSkipSegment(active, announce = true)'));
    expect(source, contains('safeNativeSkipTargetMs(segment.endMs'));
    expect(source, contains('if (!cancelDpadScrub()) showExitConfirmation()'));
    expect(source, contains('dpadScrubRenderRunnable'));
    expect(source, contains('playerView.controllerShowTimeoutMs = 0'));

    final scrubKeys = _methodSlice(
      source,
      'private fun handleDpadScrubKey',
      '/** Keyboard/gamepad shortcuts',
    );
    expect(
      scrubKeys,
      isNot(contains('KeyEvent.KEYCODE_BACK')),
      reason: 'Back must flow through OnBackPressedDispatcher on Android 16+',
    );

    final nativeFlutterSource = _read(
      'lib/features/player/presentation/native_media3_player_screen.dart',
    );
    final inheritedResume = _methodSlice(
      nativeFlutterSource,
      'Future<void> _loadResumeAndPreferences',
      'Future<void> _persistResult',
    );
    _expectInOrder(inheritedResume, const [
      'if (widget.initialPosition case final handoffPosition?)',
      '_startFromBeginning = false',
      '_resumePosition = handoffPosition',
    ]);
  });
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _methodSlice(String source, String startToken, String endToken) {
  final start = source.indexOf(startToken);
  final end = source.indexOf(endToken, start + startToken.length);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startToken');
  expect(
    end,
    greaterThan(start),
    reason: 'Missing $endToken after $startToken',
  );
  return source.substring(start, end);
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
