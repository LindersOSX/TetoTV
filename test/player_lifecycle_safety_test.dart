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
    expect(
      prepare,
      contains('if (!released) {\n      _handoffAttemptActive = false;'),
    );
    expect(prepare, contains('_handoffReleaseFailed = true'));

    final nextEpisode = _methodSlice(
      source,
      'Future<void> _playNextEpisode',
      'Future<void> _syncProgress',
    );
    _expectInOrder(nextEpisode, const [
      'await _prepareForEngineHandoff(completedPosition)',
      'GoRouter.of(context).pushReplacement<void>(',
      '_popPlayerRouteAfterHandoff(Navigator.of(context))',
    ]);

    final confirmExit = _methodSlice(
      source,
      'Future<void> _confirmExit',
      '@override\n  void dispose',
    );
    _expectInOrder(confirmExit, const [
      'await _player.pause()',
      'exit = await showPlayerExitConfirmation(context)',
      '_confirmingExit = false',
      'final position = _effectiveHandoffPosition()',
      'await _prepareForEngineHandoff(position)',
      '_popPlayerRouteAfterHandoff(navigator)',
    ]);
    final returnToPicker = _methodSlice(
      source,
      'Future<void> _returnToStreamPicker',
      'Future<void> _recordEngineSuccess',
    );
    _expectInOrder(returnToPicker, const [
      'final position = _effectiveHandoffPosition()',
      'await _prepareForEngineHandoff(position)',
      '_popPlayerRouteAfterHandoff(navigator)',
    ]);
    final popAfterHandoff = _methodSlice(
      source,
      'void _popPlayerRouteAfterHandoff',
      'Future<void> _recordEngineSuccess',
    );
    _expectInOrder(popAfterHandoff, const [
      '_routePopScheduled = true',
      'setState(() => _allowExit = true)',
      'navigator.maybePop()',
    ]);
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
      'await _disposeControllerAuthoritatively(controller)',
      '_controllerReleasedForHandoff = true',
    ]);
    expect(
      prepare,
      contains('if (!released) {\n      _handoffAttemptActive = false;'),
    );
    expect(prepare, contains('_handoffReleaseFailed = true'));

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
      'GoRouter.of(context).pushReplacement<void>(',
      '_popPlayerRouteAfterHandoff(Navigator.of(context))',
    ]);
    final restart = _methodSlice(
      source,
      'Future<void> _runRestart',
      'Future<void> _trackControllerMutation',
    );
    expect(restart, contains('await _disposeControllerAuthoritatively(old)'));

    final confirmExit = _methodSlice(
      source,
      'Future<void> _confirmExit',
      '@override\n  void dispose',
    );
    _expectInOrder(confirmExit, const [
      'await controller?.pause()',
      'exit = await showPlayerExitConfirmation(context)',
      '_confirmingExit = false',
      'final position = _effectiveHandoffPosition()',
      'await _prepareForEngineHandoff(position)',
      '_popPlayerRouteAfterHandoff(navigator)',
    ]);
    final returnToPicker = _methodSlice(
      source,
      'Future<void> _returnToStreamPicker',
      'Future<void> _syncProgress',
    );
    _expectInOrder(returnToPicker, const [
      'final position = _effectiveHandoffPosition()',
      'await _prepareForEngineHandoff(position)',
      '_popPlayerRouteAfterHandoff(navigator)',
    ]);
    final popAfterHandoff = _methodSlice(
      source,
      'void _popPlayerRouteAfterHandoff',
      'Future<void> _syncProgress',
    );
    _expectInOrder(popAfterHandoff, const [
      '_routePopScheduled = true',
      'setState(() => _allowExit = true)',
      'navigator.maybePop()',
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
      'releasePlaybackResources()',
      'if (switchingEngine && !playbackResourcesReleased)',
      'setResult(RESULT_OK, result)',
      'finish()',
    ]);
    expect(source, contains('if (playbackResourcesReleased) return'));
    expect(
      source,
      contains('playerViewReleased = !::playerView.isInitialized'),
    );
    expect(source, contains('runCatching { player.release() }.isSuccess'));
    expect(
      source,
      contains('playbackResourcesReleased = playerViewReleased &&'),
    );
    expect(source, contains('STATUS_RELEASE_FAILED'));
    expect(source, contains('!playerCoreReleased && !resultSent'));
    expect(source, contains('runCatching { player.pause() }'));
    expect(source, contains('runCatching { player.play() }'));
    expect(source, contains('updateSkipSegmentButtonPosition'));
    expect(source, contains('seekPastSkipSegment(active, announce = true)'));
    expect(source, contains('safeNativeSkipTargetMs(segment.endMs'));
    expect(
      source,
      contains('override fun handleOnBackPressed() = showExitConfirmation()'),
    );
    expect(source, isNot(contains('dpadScrub')));

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

    final nativeRun = _methodSlice(
      nativeFlutterSource,
      'Future<void> _run()',
      'Future<void> _retryAfterFailure',
    );
    _expectInOrder(nativeRun, const [
      'nativePlayerReturnNavigationForStatus(',
      'NativePlayerReturnNavigation.home',
      "_status = 'Closing video…'",
      'runBestEffortNativePlayerExitBookkeeping([',
      '() => _persistResult(result)',
      '() => _syncResultIfThresholdReached(result)',
      '() => _recordPlayerSuccess(result)',
      'switch (returnNavigation)',
      'case NativePlayerReturnNavigation.home:',
      "GoRouter.of(context).go('/')",
      'case NativePlayerReturnNavigation.previousRoute:',
      'if (context.canPop()) context.pop()',
      'case NativePlayerReturnNavigation.none:',
    ]);
  });

  test('Media3 destroys network metadata resources off the main thread', () {
    final source = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/Media3PlayerActivity.kt',
    ).readAsStringSync();
    final onDestroyStart = source.indexOf('override fun onDestroy() {');
    final releaseStart = source.indexOf(
      'private fun releasePlaybackResources()',
      onDestroyStart,
    );
    expect(onDestroyStart, greaterThanOrEqualTo(0));
    expect(releaseStart, greaterThan(onDestroyStart));
    final onDestroy = source.substring(onDestroyStart, releaseStart);

    expect(onDestroy, contains('Media3NetworkCleanup.shared.schedule('));
    expect(onDestroy, contains('metadataDispatcher::cancelAll'));
    expect(onDestroy, contains('metadataConnectionPool::evictAll'));
    expect(onDestroy, isNot(contains('metadataClient.dispatcher.cancelAll()')));
    expect(
      onDestroy,
      isNot(contains('metadataClient.connectionPool.evictAll()')),
    );
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
