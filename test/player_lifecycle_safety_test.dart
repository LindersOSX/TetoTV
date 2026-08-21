import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player disposal never reads a Riverpod ref after unmount', () {
    final source = _read(
      'lib/features/player/presentation/tv_player_screen.dart',
    );
    final router = _methodSlice(
      source,
      'class _TvPlayerScreenRouterState',
      'enum _TvPlaybackEngine',
    );
    final routerDispose = _methodSlice(
      router,
      'void dispose()',
      'Future<void> _loadDevicePreference',
    );
    expect(router, isNot(contains('anonymousUsageReporterProvider')));
    expect(routerDispose, contains('playbackLease?.close()'));
    expect(routerDispose, isNot(contains('ref.')));
    expect(
      router,
      contains('widget.malMediaId ?? _activeLaunch.episode.malMediaId'),
    );
    expect(router, contains('malMediaId: _malMediaId'));
    expect(router, contains('anilistMediaId: _anilistMediaId'));

    final player = _methodSlice(
      source,
      'class _MpvTvPlayerScreenState',
      'class _UnifiedMpvPlayerChrome',
    );
    final savePreferences = _methodSlice(
      player,
      'Future<void> _saveSeriesPreferences',
      'Future<void> _saveDecoderPreference',
    );
    final dispose = player.substring(player.lastIndexOf('void dispose()'));
    expect(player, contains('_database = ref.read(tetoTvDatabaseProvider)'));
    expect(
      savePreferences,
      contains('_database.saveSeriesPreferences(mediaId, _seriesPreferences)'),
    );
    expect(
      savePreferences,
      contains('if (mediaId == null || !_seriesPreferencesReady) return'),
    );
    expect(savePreferences, isNot(contains('ref.')));
    expect(
      savePreferences,
      allOf(
        contains('persistedPlayerAudioLanguage('),
        contains('observedLanguage: audio.language'),
        contains('observedTitle: audio.title'),
      ),
      reason: 'manually selected dub labels must persist without language tags',
    );
    expect(dispose, isNot(contains('ref.')));
    expect(
      dispose,
      contains('if (!_engineHandoffInProgress && !_playerReleasedForHandoff)'),
    );
  });

  test('manual player selection reaches Media3 without automatic redirect', () {
    final router = _read(
      'lib/features/player/presentation/tv_player_screen.dart',
    );
    final native = _read(
      'lib/features/player/presentation/native_media3_player_screen.dart',
    );

    expect(router, contains('_manualEngineSelection = manualSelection'));
    expect(router, contains('manualSelection: true'));
    expect(router, contains('manuallySelected: _manualEngineSelection'));
    expect(native, contains('!manuallySelected &&'));
  });

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
      matches(
        RegExp(
          r'if \(_skipInProgress\s*\|\|\s*_engineHandoffInProgress\s*\|\|\s*'
          r'_blockGuestLocalControl',
        ),
      ),
    );
    expect(source, contains('autoSkip && !_skipInProgress &&'));
    expect(source, contains('_checkSkips(_player.state.position)'));
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
    final detachVideoOutput = _methodSlice(
      source,
      'Future<void> _detachAndroidVideoOutputBeforeRelease',
      'Future<bool> _prepareForEngineHandoff',
    );
    _expectInOrder(detachVideoOutput, const [
      'wid.removeListener',
      'videoParamsSubscription?.cancel()',
      'wid.value = 0',
      'await platformController.widListener()',
    ]);
    _expectInOrder(prepare, const [
      'await WidgetsBinding.instance.endOfFrame',
      'await _waitForPlayerMutations()',
      'await _waitForSeekDrain()',
      'await _progressSubscription?.cancel()',
      'await _player.stop()',
      'await _detachAndroidVideoOutputBeforeRelease()',
      'await _player.dispose()',
      '_playerReleasedForHandoff = true',
    ]);
    expect(
      source,
      contains('if (!_engineHandoffInProgress && !_playerReleasedForHandoff)'),
    );
    final applySubtitle = _methodSlice(
      source,
      'Future<void> _applySubtitle',
      'Future<void> _persistPlayback',
    );
    _expectInOrder(applySubtitle, const [
      'SubtitleTrack.uri(subtitle',
      'if (!_seriesPreferences.subtitleEnabled)',
      '_player.setSubtitleTrack(SubtitleTrack.no())',
    ]);
    expect(
      source,
      contains(
        '_tracksSubscription = _player.stream.tracks.listen(_onTracksChanged)',
      ),
    );
    final trackCallback = _methodSlice(
      source,
      'void _onTracksChanged',
      'Future<void> _applyPreferredAudio',
    );
    _expectInOrder(trackCallback, const [
      '_runTrackedTrackSelection(tracks)',
      '_trackPlayerMutation(() => _selectPreferredTracks(tracks))',
    ]);
    final preferredAudio = _methodSlice(
      source,
      'Future<void> _applyPreferredAudio',
      'Future<void> _selectPreferredTracks',
    );
    _expectInOrder(preferredAudio, const [
      'await AndroidTvBridge.instance.getDeviceProfile()',
      'if (_preferredAudioSelected || !_canApplyTrackSelection) return',
      'await _player.setAudioTrack(preferred)',
    ]);
    final mpvPlayer = _methodSlice(
      source,
      'class _MpvTvPlayerScreenState',
      'class _UnifiedMpvPlayerChrome',
    );
    final dispose = mpvPlayer.substring(
      mpvPlayer.lastIndexOf('void dispose()'),
    );
    _expectInOrder(dispose, const [
      '_engineHandoffInProgress = true',
      'await _waitForPlayerMutations()',
      'await _player.stop()',
      'await _detachAndroidVideoOutputBeforeRelease()',
      'await _player.dispose()',
    ]);
    expect(
      prepare,
      contains('if (!released) {\n      _handoffAttemptActive = false;'),
    );
    expect(prepare, contains('_handoffReleaseFailed = true'));
    expect(source, isNot(contains('Episode progress saved')));
    expect(source, isNot(contains('tracker reconnects')));

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
      '_controlsTimer?.cancel()',
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
    expect(source, contains('autoSkip && !_skipInProgress &&'));
    expect(source, contains('_checkSkips(controller.value.position)'));
    expect(source, contains('_controllerReleasedForHandoff = true'));

    final preferredTracks = _methodSlice(
      source,
      'Future<void> _applyPreferredTracks',
      'void _scheduleTrackDiscoveryRetry',
    );
    _expectInOrder(preferredTracks, const [
      'if (!_canApplyTracksTo(controller)',
      'final audioTracks = await controller.getAudioTracks()',
      'if (!_canApplyTracksTo(controller)) return',
      'if (audioId != null)',
      'await controller.setAudioTrack(audioId)',
      'if (!_canApplyTracksTo(controller)) return',
      '_audioPreferenceApplied = playerTrackMatchesLanguage(',
      'await _saveTrackPreferences(audioLabel: audioTracks[audioId])',
    ]);
    final discoveryRetry = _methodSlice(
      source,
      'void _scheduleTrackDiscoveryRetry',
      'Future<bool> _restoreResume',
    );
    _expectInOrder(discoveryRetry, const [
      'if (!_canApplyTracksTo(controller)',
      '_trackDiscoveryTimer = Timer(',
      'if (!_canApplyTracksTo(controller)) return',
      '_trackControllerMutation(_applyPreferredTracks(controller))',
    ]);

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
    expect(source, isNot(contains('Episode progress saved')));
    expect(source, isNot(contains('tracker reconnects')));

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
    _expectInOrder(restart, const [
      '_controllerPendingRelease = old',
      'setState(() => _controller = null)',
      'await WidgetsBinding.instance.endOfFrame',
      'await _waitForControllerMutations()',
      'await _disposeControllerAuthoritatively(old)',
      '_installController(_createController(_source, mode))',
    ]);
    expect(source, contains('key: ObjectKey(controller)'));
    expect(
      source,
      contains(
        'if (controller == _controller && restored) _pendingResume = null',
      ),
    );
    expect(
      source,
      contains('Keep _pendingResume intact'),
      reason: 'a failed VLC seek must survive an immediate engine handoff',
    );
    expect(
      source,
      contains('vlcSubtitleTrackSignature'),
      reason: 'CC waits for late embedded or external tracks',
    );

    final vlcPlayer = _methodSlice(
      source,
      'class _VlcTvPlayerScreenState',
      'class _VlcPlayerChrome',
    );
    final dispose = vlcPlayer.substring(
      vlcPlayer.lastIndexOf('void dispose()'),
    );
    _expectInOrder(dispose, const [
      '_trackDiscoveryTimer?.cancel()',
      '_engineHandoffInProgress = true',
      '_controller = null',
      'await _waitForControllerMutations()',
      'await _disposeControllerAuthoritatively(controller)',
    ]);

    final confirmExit = _methodSlice(
      source,
      'Future<void> _confirmExit',
      '@override\n  void dispose',
    );
    _expectInOrder(confirmExit, const [
      '_controlsTimer?.cancel()',
      'await pause.timeout(vlcInteractiveCommandTimeout)',
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
    expect(source, contains('pendingCaptionTrackPicker'));
    expect(source, contains('waitForCaptionTracks(sourceButton)'));
    expect(source, contains('unsupportedAudioWatchdog'));
    expect(source, contains('UNSUPPORTED_AUDIO_GRACE_MS'));
    expect(source, contains('if (!preserveDiscordPresenceForEngineHandoff)'));
    expect(source, contains('suppressDiscordPresence = trustedLocalSource'));
    expect(source, contains('R.string.tetotv_player_local_media3_only'));
    expect(
      source,
      contains(
        'if (suppressDiscordPresence || !::player.isInitialized || resultSent) return',
      ),
    );
    _expectInOrder(finish, const [
      'result.putExtra(RESULT_STATUS, deliveredStatus)',
      'preserveDiscordPresenceForEngineHandoff =',
      'setResult(RESULT_OK, result)',
    ]);
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
      'NativePlayerReturnNavigation.previousRoute',
      "_status = 'Closing video…'",
      'runBestEffortNativePlayerExitBookkeeping([',
      '() => _persistResult(result)',
      '() => _syncResultIfThresholdReached(result)',
      '() => _recordPlayerSuccess(result)',
      'switch (returnNavigation)',
      'case NativePlayerReturnNavigation.previousRoute:',
      'if (context.canPop()) {',
      'context.pop()',
      "GoRouter.of(context).go('/anime/\$_mediaId')",
      'case NativePlayerReturnNavigation.none:',
    ]);
  });

  test(
    'next-episode preparation follows live player source and audio state',
    () {
      final mpv = _read(
        'lib/features/player/presentation/tv_player_screen.dart',
      );
      final vlc = _read(
        'lib/features/player/presentation/vlc_tv_player_screen.dart',
      );
      final nativeFlutter = _read(
        'lib/features/player/presentation/native_media3_player_screen.dart',
      );
      final bridge = _read('lib/core/platform/android_tv_bridge.dart');
      final mainActivity = _read(
        'android/app/src/main/kotlin/dev/animetv/anime_tv/MainActivity.kt',
      );
      final media3 = _read(
        'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
        'Media3PlayerActivity.kt',
      );

      for (final player in [mpv, vlc, nativeFlutter]) {
        expect(player, contains('_nextEpisodePreparationRequest()'));
        expect(
          player,
          contains('currentRequest: _nextEpisodePreparationRequest()'),
        );
        expect(player, contains('final generation = _prewarmRetry.generation'));
        expect(player, contains('_prewarmRetry.isCurrent(generation)'));
        expect(player, contains('prepared != null'));
        expect(player, contains('_invalidateNextEpisodePreparation();'));
        expect(player, contains('preparation.warmWithOutcome('));
        expect(player, contains('outcome.isTerminal'));
        expect(player, contains('_prewarmRetry.recordTerminal(generation)'));
        expect(player, contains('_prewarmRetry.recordFailure('));
        expect(
          player,
          contains('_nextEpisodePreparation.hasReady('),
          reason: 'local readiness must not outlive the controller lease TTL',
        );
        expect(player, contains('NextEpisodePrewarmSettingsKey.fromSettings('));
        expect(player, contains('if (!_preserveNextEpisodePreparation &&'));
        expect(player, contains('_nextEpisodePreparation.abandon('));
        expect(player, contains('_preserveNextEpisodePreparation = true;'));
        expect(
          RegExp(
            r'_preserveNextEpisodePreparation = true;[\s\S]{0,300}'
            r'preparedNextEpisodePlayerLocation\(prepared\)',
          ).hasMatch(player),
          isTrue,
          reason: 'prepared-next replacement must transfer cache ownership',
        );
      }

      final mpvExit = _methodSlice(
        mpv,
        'Future<void> _confirmExit()',
        '@override\n  void dispose()',
      );
      final vlcExit = _methodSlice(
        vlc,
        'Future<void> _confirmExit()',
        '@override\n  void dispose()',
      );
      expect(mpvExit, isNot(contains('_preserveNextEpisodePreparation')));
      expect(vlcExit, isNot(contains('_preserveNextEpisodePreparation')));

      final mpvEngineSwitch = _methodSlice(
        mpv,
        'Future<void> _fallbackToVlc',
        'NextEpisodePreparationRequest _nextEpisodePreparationRequest',
      );
      _expectInOrder(mpvEngineSwitch, const [
        '_preserveNextEpisodePreparation = true',
        'widget.onUseVlc(',
      ]);
      final vlcEngineSwitch = _methodSlice(
        vlc,
        'Future<void> _handoffTo',
        'Future<void> _openPlayerPicker',
      );
      _expectInOrder(vlcEngineSwitch, const [
        '_preserveNextEpisodePreparation = true',
        'callback(selected, position, stream, release, directStreams)',
      ]);
      final nativeEngineSwitch = _methodSlice(
        nativeFlutter,
        'void _handoffToMpv()',
        'void _handoffToVlc()',
      );
      _expectInOrder(nativeEngineSwitch, const [
        '_preserveNextEpisodePreparation = true',
        'widget.onUseMpv(',
      ]);
      expect(
        mpv,
        contains('playerAudioIntentChanged('),
        reason: 'MPV manual exact-language changes must replace stale prep',
      );
      expect(
        vlc,
        contains('final manualAudioIntentChanged ='),
        reason: 'VLC manual exact-language changes must replace stale prep',
      );

      final nativeRun = _methodSlice(
        nativeFlutter,
        'Future<void> _run()',
        'Future<int?> _resolveSkipMalMediaId',
      );
      expect(nativeRun, isNot(contains('unawaited(_prewarmNextEpisode())')));
      expect(nativeFlutter, contains('.nativePlaybackProgress'));
      expect(
        nativeFlutter,
        contains('progress.checkpointKey != _checkpointKey'),
      );
      expect(nativeFlutter, contains('if (!progress.isPlaying) return;'));
      expect(nativeFlutter, contains('progress.audioPreferenceSet'));
      expect(nativeFlutter, contains('_persistNativeAudioSelection(progress)'));
      expect(
        nativeFlutter,
        contains('database.saveSeriesPreferences(_mediaId, next)'),
      );
      expect(nativeFlutter, contains('currentRequest: previousRequest'));
      expect(
        nativeFlutter,
        contains(
          'shouldPrepareNextEpisode(position: position, duration: duration)',
        ),
      );
      expect(bridge, contains("case 'nativePlaybackProgress':"));
      expect(
        mainActivity,
        contains('NativePlayerProgressBridge.attach(channel)'),
      );
      expect(
        mainActivity,
        contains('NativePlayerProgressBridge.detach(channel)'),
      );
      expect(media3, contains('publishPlaybackProgress()'));
      expect(
        media3,
        contains('publishPlaybackProgress(includeManualAudioSelection = true)'),
      );
      expect(media3, contains('"isPlaying" to isPlaying'));
      expect(media3, contains('"audioPreferenceSet" to audioPreferenceSet'));
      expect(
        media3,
        contains('publishPlaybackProgress(isPlayingOverride = false)'),
      );
      expect(media3, contains('"nativePlaybackProgress"'));
    },
  );

  test('web streams wait for stable duration before loading skip data', () {
    final mpv = _read('lib/features/player/presentation/tv_player_screen.dart');
    final vlc = _read(
      'lib/features/player/presentation/vlc_tv_player_screen.dart',
    );
    final nativeFlutter = _read(
      'lib/features/player/presentation/native_media3_player_screen.dart',
    );
    final media3 = _read(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    );

    for (final flutterPlayer in [mpv, vlc]) {
      expect(flutterPlayer, contains('_scheduleSkipSegmentLoad'));
      expect(
        flutterPlayer,
        contains('Timer(const Duration(milliseconds: 1200)'),
      );
      expect(flutterPlayer, contains('_resolveSkipMalMediaId'));
      expect(flutterPlayer, contains('catalogClientProvider).details('));
    }
    expect(mpv, contains('_player.stream.duration.listen('));
    expect(vlc, contains('_scheduleSkipSegmentLoad(value.duration)'));
    expect(nativeFlutter, contains('final malMediaIdFuture ='));
    expect(
      nativeFlutter,
      contains('hasDirectSources: _currentStream.isWebStream'),
    );
    expect(media3, contains('SKIP_DURATION_STABILITY_DELAY_MS = 1_200L'));
    expect(media3, contains('skipDurationCandidateMs = durationMs'));
    expect(media3, contains('skipDurationStabilityRunnable'));
  });

  test('MPV exposes skip intro above every visible transport control', () {
    final source = _read(
      'lib/features/player/presentation/tv_player_screen.dart',
    );
    final handleKey = _methodSlice(
      source,
      'KeyEventResult _handleKey',
      'Future<void> _seekBy',
    );

    _expectInOrder(handleKey, const [
      'key == LogicalKeyboardKey.arrowUp',
      '_canSkipNow',
      '_activeSkip != null',
      '_skipControlFocus.requestFocus()',
    ]);
    expect(handleKey, contains('key == LogicalKeyboardKey.arrowDown'));
    expect(handleKey, contains('_skipControlFocus.hasPrimaryFocus'));
    expect(handleKey, contains('_playControlFocus.requestFocus()'));
  });

  test('Media3 routes every torrent seek through the guarded MPV handoff', () {
    final source = _read(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    );

    expect(
      RegExp(r'player\.seekTo\(').allMatches(source),
      hasLength(1),
      reason: 'no transport or skip path may bypass seekOrUseMpv',
    );
    expect(
      source,
      matches(
        RegExp(
          r'setOnClickListener\s*\{\s*if \(blockGuestLocalControl\(\)\) '
          r'return@setOnClickListener\s*seekRelative\(-',
        ),
      ),
    );
    expect(
      source,
      matches(
        RegExp(
          r'setOnClickListener\s*\{\s*if \(blockGuestLocalControl\(\)\) '
          r'return@setOnClickListener\s*seekRelative\(seekForward',
        ),
      ),
    );
    expect(source, contains('KeyEvent.KEYCODE_J -> seekRelative(-'));
    expect(source, contains('KeyEvent.KEYCODE_L -> seekRelative('));
    expect(
      RegExp(r'seekOrUseMpv\(target\)').allMatches(source),
      hasLength(2),
      reason:
          'transport (including coordinator sync) and intro/outro skip must share the same fallback',
    );
    expect(
      source,
      contains('origin = NativeTransportCommandOrigin.WATCH_PARTY_COORDINATOR'),
    );
    expect(source, contains('origin = NativeTransportCommandOrigin.LOCAL_HUD'));
    expect(source, contains('handoffPositionOverrideMs = targetMs'));
    expect(source, contains('finishWithResult(STATUS_USE_MPV)'));
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
    expect(onDestroy, contains('metadataDispatcher.cancelAll()'));
    expect(onDestroy, contains('metadataConnectionPool.evictAll()'));
    expect(onDestroy, contains('avatarDispatcher.cancelAll()'));
    expect(onDestroy, contains('avatarConnectionPool.evictAll()'));
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
