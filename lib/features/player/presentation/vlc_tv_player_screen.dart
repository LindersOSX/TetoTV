import 'dart:async';
import 'dart:io';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/player/application/skip_segment_service.dart';
import 'package:anime_tv/features/player/presentation/native_media3_player_screen.dart'
    show isTerminalDebridAlternativeFailure;
import 'package:anime_tv/features/streaming/application/debrid_resolver_factory.dart';
import 'package:anime_tv/features/streaming/application/debrid_token_service.dart';
import 'package:anime_tv/features/player/presentation/player_control_overlay.dart';
import 'package:anime_tv/features/player/presentation/player_stream_source_picker.dart';
import 'package:anime_tv/features/player/presentation/teto_player_chrome.dart';
import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/data/web_stream_validator.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/application/tracking_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

enum VlcDecoderMode { hardwareCopy, software }

typedef _VlcMenuResult = ({String type, Object value});

HwAcc vlcHwAccForMode(VlcDecoderMode mode) => switch (mode) {
  VlcDecoderMode.hardwareCopy => HwAcc.decoding,
  VlcDecoderMode.software => HwAcc.disabled,
};

String vlcDecoderLabel(VlcDecoderMode mode) => switch (mode) {
  VlcDecoderMode.hardwareCopy => 'VLC compatibility (recommended)',
  VlcDecoderMode.software => 'VLC software decoding',
};

int? preferredVlcTrack(
  Map<int, String> tracks, {
  required String language,
  bool preferDub = false,
}) {
  if (tracks.isEmpty) return null;
  int score(String title) {
    final value = title.toLowerCase();
    var result = playerTrackLanguageScore(
      title: title,
      preferredLanguage: language,
    );
    if (preferDub && value.contains('dub')) result += 3;
    if (value.contains('commentary') || value.contains('description')) {
      result -= 8;
    }
    return result;
  }

  final ranked = tracks.entries.toList()
    ..sort((a, b) => score(b.value).compareTo(score(a.value)));
  return score(ranked.first.value) > 0 ? ranked.first.key : null;
}

/// A second, independent Android playback engine.
///
/// media_kit/libmpv renders through one Flutter texture pipeline. Some Android
/// TV firmware returns corrupt color planes through that path without reporting
/// a decoder error. This independent libVLC engine disables MediaCodec direct
/// rendering, copies decoded frames through VLC's renderer, and automatically
/// falls back to software decoding. MPV remains available for unusual subtitle
/// releases.
class VlcTvPlayerScreen extends ConsumerStatefulWidget {
  const VlcTvPlayerScreen({
    required this.source,
    required this.title,
    required this.debridService,
    required this.launch,
    required this.onUseMpv,
    this.onSelectEngine,
    this.initialPosition,
    this.subtitle,
    this.anilistMediaId,
    this.malMediaId,
    this.episode,
    this.coverImageUrl,
    super.key,
  });

  final String source;
  final String title;
  final DebridService debridService;
  final PlaybackLaunch launch;
  final void Function(
    Duration position,
    StreamReady stream,
    ReleaseCandidate release,
    List<PlaybackStreamOption> directStreams,
  )
  onUseMpv;
  final void Function(
    PreferredPlayer player,
    Duration position,
    StreamReady stream,
    ReleaseCandidate release,
    List<PlaybackStreamOption> directStreams,
  )?
  onSelectEngine;
  final Duration? initialPosition;
  final String? subtitle;
  final int? anilistMediaId;
  final int? malMediaId;
  final int? episode;
  final String? coverImageUrl;

  @override
  ConsumerState<VlcTvPlayerScreen> createState() => _VlcTvPlayerScreenState();
}

class _VlcTvPlayerScreenState extends ConsumerState<VlcTvPlayerScreen> {
  VlcPlayerController? _controller;
  final _rootFocus = FocusNode(debugLabel: 'vlc.player.root');
  final _playFocus = FocusNode(debugLabel: 'vlc.player.play');
  final _skipFocus = FocusNode(debugLabel: 'vlc.player.skip-segment');
  final _scrubController = PlayerScrubController();
  StreamSubscription<MediaAction>? _mediaActionSubscription;
  Timer? _controlsTimer;
  Timer? _trackMessageTimer;
  Timer? _initializationWatchdog;
  Timer? _videoWatchdog;
  bool _controlsVisible = true;
  bool _persistenceReady = false;
  bool _completionHandled = false;
  bool _syncHandled = false;
  bool _restarting = false;
  bool _failingOver = false;
  bool _audioPreferenceApplied = false;
  bool _subtitlePreferenceApplied = false;
  int _trackDiscoveryAttempts = 0;
  Timer? _trackDiscoveryTimer;
  bool _engineInitialized = false;
  bool _canSkip = false;
  SkipSegment? _activeSkip;
  String? _trackMessage;
  String? _playbackError;
  Duration? _pendingResume;
  DateTime _lastCheckpointSave = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMediaSessionUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  late String _source;
  late ReleaseCandidate _release;
  late StreamReady _currentStream;
  List<PlaybackStreamOption> _directStreamOptions = const [];
  StreamSubscription<WebStreamSearchProgress>? _sourceDiscoverySubscription;
  final Set<String> _failedDirectStreamUris = {};
  int _alternativeIndex = 0;
  List<SkipSegment> _skips = const [];
  SeriesPlaybackPreferences _preferences = const SeriesPlaybackPreferences();
  VlcDecoderMode _decoderMode = VlcDecoderMode.hardwareCopy;
  double _playbackRate = 1;
  double _subtitleSize = 34;
  int _subtitleDelayMs = 0;
  int _audioDelayMs = 0;
  int _videoAspectIndex = 0;
  Duration? _queuedSeekTarget;
  Completer<void>? _seekDrainCompleter;
  Future<bool>? _skipSeekOperation;
  bool _skipInProgress = false;
  int _seekBackSeconds = 10;
  int _seekForwardSeconds = 10;
  int _captionTextColor = 0xFFFFFFFF;
  int _captionBackgroundColor = 0x00000000;
  final Set<String> _autoFocusedSkipSegments = {};
  final Set<String> _consumedSkipSegments = {};
  bool _allowExit = false;
  bool _confirmingExit = false;
  TapDownDetails? _touchDoubleTapDetails;
  bool _reportedPlaybackSuccess = false;
  bool _engineHandoffInProgress = false;
  bool _controllerReleasedForHandoff = false;
  bool _nativePlaybackStateClearedForHandoff = false;
  final Set<Future<void>> _controllerMutationOperations = <Future<void>>{};
  final Set<VlcPlayerController> _releasedControllers =
      Set<VlcPlayerController>.identity();

  bool get _hasUntriedDirectStream => hasUntriedDirectWebStream(
    current: _currentStream,
    options: _directStreamOptions,
    failedUris: _failedDirectStreamUris,
  );

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _release = widget.launch.selectedRelease;
    _currentStream = widget.launch.stream;
    _pendingResume = widget.initialPosition;
    _directStreamOptions = mergePlaybackStreamOptions([
      PlaybackStreamOption(stream: _currentStream, release: _release),
      ...widget.launch.directAlternatives,
    ], const []);
    _mediaActionSubscription = AndroidTvBridge.instance.mediaActions.listen(
      _handleMediaAction,
    );
    unawaited(_bootstrap());
    unawaited(_startWebSourceDiscovery());
    _scheduleControlsHide();
  }

  Future<void> _bootstrap() async {
    final appearance = ref.read(settingsPreferencesProvider);
    _seekBackSeconds = appearance.seekBackSeconds;
    _seekForwardSeconds = appearance.seekForwardSeconds;
    _captionTextColor = appearance.captionTextColor;
    _captionBackgroundColor = appearance.captionBackgroundColor;
    final mediaId = widget.anilistMediaId;
    if (mediaId != null) {
      final database = ref.read(tetoTvDatabaseProvider);
      _preferences = await database.seriesPreferences(mediaId);
      _subtitleSize = _preferences.subtitleSize == 34
          ? appearance.captionTextSize
          : _preferences.subtitleSize;
      _subtitleDelayMs = _preferences.subtitleDelayMs;
      _audioDelayMs = _preferences.audioDelayMs;
      if (_pendingResume == null &&
          !widget.launch.episode.startFromBeginning &&
          widget.episode != null) {
        final checkpoint = await database.checkpoint(mediaId, widget.episode!);
        if (checkpoint != null &&
            !checkpoint.completed &&
            checkpoint.position > const Duration(seconds: 15) &&
            checkpoint.progress < .95) {
          _pendingResume = checkpoint.position;
        }
      }
    }
    if (!_preferences.subtitlePreferenceSet) {
      _preferences = _preferences.copyWith(
        subtitleEnabled: subtitlesEnabledByDefault(_release),
      );
    }
    if (_releaseRequiresSoftware(_release)) {
      _decoderMode = VlcDecoderMode.software;
    }
    if (!mounted || _engineHandoffInProgress) return;
    _installController(_createController(_source, _decoderMode));
    setState(() {});
  }

  bool _releaseRequiresSoftware(ReleaseCandidate release) {
    final name = release.releaseName.toLowerCase();
    return RegExp(
      r'(?:hi10p|high[ ._-]?10|10[ ._-]?bit|yuv420p10)',
    ).hasMatch(name);
  }

  VlcPlayerController _createController(String source, VlcDecoderMode mode) {
    final streamHeaders = _currentStream.headers;
    final userAgent =
        streamHeaders['User-Agent'] ??
        streamHeaders['user-agent'] ??
        'TetoTV/1.10 Android libVLC';
    final referer = streamHeaders['Referer'] ?? streamHeaders['referer'];
    final options = VlcPlayerOptions(
      advanced: VlcAdvancedOptions([
        VlcAdvancedOptions.networkCaching(5000),
        VlcAdvancedOptions.clockJitter(0),
        VlcAdvancedOptions.clockSynchronization(1),
      ]),
      http: VlcHttpOptions([
        VlcHttpOptions.httpReconnect(true),
        VlcHttpOptions.httpContinuous(true),
        VlcHttpOptions.httpUserAgent(userAgent),
      ]),
      video: VlcVideoOptions([
        VlcVideoOptions.dropLateFrames(true),
        VlcVideoOptions.skipFrames(true),
      ]),
      subtitle: VlcSubtitleOptions([
        VlcSubtitleOptions.relativeFontSize(
          (100 - (_subtitleSize - 20).round()).clamp(45, 85),
        ),
        VlcSubtitleOptions.boldStyle(true),
        VlcSubtitleOptions.color(
          VlcSubtitleColor(_captionTextColor & 0x00FFFFFF),
        ),
        VlcSubtitleOptions.backgroundOpacity(
          _preferences.highContrastSubtitles
              ? 221
              : (_captionBackgroundColor >> 24) & 0xFF,
        ),
        VlcSubtitleOptions.backgroundColor(
          VlcSubtitleColor(_captionBackgroundColor & 0x00FFFFFF),
        ),
      ]),
      extras: [
        '--no-video-title-show',
        '--avcodec-fast',
        '--file-caching=5000',
        if (referer != null && referer.isNotEmpty) '--http-referrer=$referer',
      ],
    );
    final controller = source.startsWith('asset:///')
        ? VlcPlayerController.asset(
            source.substring('asset:///'.length),
            autoInitialize: false,
            autoPlay: true,
            hwAcc: vlcHwAccForMode(mode),
            options: options,
          )
        : VlcPlayerController.network(
            source,
            autoInitialize: false,
            autoPlay: true,
            hwAcc: vlcHwAccForMode(mode),
            options: options,
          );
    controller.addOnInitListener(
      () => unawaited(_trackControllerMutation(_onInitialized(controller))),
    );
    return controller;
  }

  void _installController(VlcPlayerController controller) {
    _controller = controller;
    controller.addListener(_onValueChanged);
    unawaited(
      _trackControllerMutation(_initializeWhenPlatformViewIsReady(controller)),
    );
    _initializationWatchdog?.cancel();
    _initializationWatchdog = Timer(const Duration(seconds: 20), () {
      if (!mounted || controller != _controller) return;
      if (!controller.value.isInitialized) {
        unawaited(
          _handleEngineFailure('VLC could not initialize this stream.'),
        );
      }
    });
  }

  Future<void> _initializeWhenPlatformViewIsReady(
    VlcPlayerController controller,
  ) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (!mounted || _engineHandoffInProgress || controller != _controller) {
        return;
      }
      if (controller.isReadyToInitialize == true) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted || _engineHandoffInProgress || controller != _controller) {
      return;
    }
    if (controller.isReadyToInitialize != true ||
        controller.value.isInitialized) {
      return;
    }
    try {
      await controller.initialize();
    } catch (error) {
      await _handleEngineFailure('VLC initialization failed: $error');
    }
  }

  Future<void> _onInitialized(VlcPlayerController controller) async {
    if (!mounted || _engineHandoffInProgress || controller != _controller) {
      return;
    }
    _initializationWatchdog?.cancel();
    try {
      await controller.setPlaybackSpeed(_playbackRate);
      await controller.setSpuDelay(_subtitleDelayMs);
      await controller.setAudioDelay(_audioDelayMs);
    } catch (_) {
      // Some containers expose delay controls only after the first frame.
    }
    await _applyExternalSubtitle(controller);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _applyPreferredTracks(controller);
    if (!mounted || controller != _controller) return;
    final resume = _pendingResume;
    if (resume != null) {
      await _restoreResume(controller, resume);
      if (controller == _controller) _pendingResume = null;
      _showMessage('Resumed at ${_formatDuration(resume)}');
    }
    _persistenceReady = true;
    unawaited(_loadSkipSegments());
    _scheduleVideoWatchdog(controller);
    if (mounted) {
      setState(() {
        _engineInitialized = true;
        _playbackError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playFocus.requestFocus();
      });
    }
  }

  Future<void> _applyExternalSubtitle(VlcPlayerController controller) async {
    final subtitle =
        _currentStream.externalSubtitle?.toString() ?? widget.subtitle;
    if (subtitle == null || subtitle.isEmpty) return;
    try {
      if (subtitle.startsWith('asset:///')) {
        final assetKey = subtitle.substring('asset:///'.length);
        final data = await rootBundle.loadString(assetKey);
        final directory = await getTemporaryDirectory();
        final file = File(
          '${directory.path}${Platform.pathSeparator}tetotv_external.ass',
        );
        await file.writeAsString(data, flush: true);
        await controller.addSubtitleFromFile(file, isSelected: true);
      } else {
        await controller.addSubtitleFromNetwork(subtitle, isSelected: true);
      }
    } catch (_) {
      _showMessage('External subtitle could not be loaded');
    }
  }

  Future<void> _applyPreferredTracks(VlcPlayerController controller) async {
    if (controller != _controller ||
        (_audioPreferenceApplied && _subtitlePreferenceApplied)) {
      return;
    }
    _trackDiscoveryTimer?.cancel();
    try {
      if (!_audioPreferenceApplied) {
        final audioTracks = await controller.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          final audioId = preferredVlcTrack(
            audioTracks,
            language: _preferences.audioLanguage,
            preferDub: true,
          );
          if (audioId != null) await controller.setAudioTrack(audioId);
          _audioPreferenceApplied = true;
        }
      }
      if (!_preferences.subtitleEnabled && !_subtitlePreferenceApplied) {
        await controller.setSpuTrack(-1);
        _subtitlePreferenceApplied = true;
      } else if (!_subtitlePreferenceApplied) {
        final subtitleTracks = await controller.getSpuTracks();
        if (subtitleTracks.isNotEmpty) {
          final subtitleId = preferredVlcTrack(
            subtitleTracks,
            language: _preferences.subtitleLanguage,
          );
          if (subtitleId != null) await controller.setSpuTrack(subtitleId);
          _subtitlePreferenceApplied = true;
        }
      }
    } catch (_) {
      // VLC commonly reports its track list a few frames after initialization.
    }
    if (!_audioPreferenceApplied || !_subtitlePreferenceApplied) {
      _scheduleTrackDiscoveryRetry(controller);
    }
  }

  void _scheduleTrackDiscoveryRetry(VlcPlayerController controller) {
    if (controller != _controller || _trackDiscoveryAttempts >= 8) return;
    _trackDiscoveryAttempts += 1;
    _trackDiscoveryTimer?.cancel();
    _trackDiscoveryTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_applyPreferredTracks(controller));
    });
  }

  Future<void> _restoreResume(
    VlcPlayerController controller,
    Duration resume,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (controller != _controller) return;
      try {
        await controller.seekTo(resume);
      } catch (_) {
        // The demuxer may not be seekable until it has produced metadata.
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (controller.value.position + const Duration(seconds: 5) >= resume) {
        return;
      }
    }
  }

  void _onValueChanged() {
    if (_engineHandoffInProgress) return;
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.position > const Duration(seconds: 1) &&
        value.size.width > 0 &&
        value.size.height > 0) {
      _videoWatchdog?.cancel();
      if (!_reportedPlaybackSuccess) {
        _reportedPlaybackSuccess = true;
        unawaited(_recordEngineSuccess());
      }
    }
    if (value.hasError && _playbackError != value.errorDescription) {
      unawaited(_handleEngineFailure(value.errorDescription));
      return;
    }
    if (_persistenceReady && value.duration > Duration.zero) {
      unawaited(_persistPlayback(value.position));
      unawaited(_updateMediaSession());
      _checkSkips(value.position);
      final threshold = ref
          .read(settingsPreferencesProvider)
          .trackerUpdateThreshold;
      if (!_syncHandled &&
          widget.episode != null &&
          (widget.anilistMediaId != null || widget.malMediaId != null) &&
          trackerUpdateThresholdReached(
            position: value.position,
            duration: value.duration,
            threshold: threshold,
          )) {
        _syncHandled = true;
        unawaited(_syncProgress());
      }
    }
    if (value.isEnded) _handlePlaybackCompleted();
  }

  void _scheduleVideoWatchdog(VlcPlayerController controller) {
    _videoWatchdog?.cancel();
    _videoWatchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || controller != _controller) return;
      final value = controller.value;
      if (value.position < const Duration(seconds: 1)) {
        unawaited(_handleEngineFailure('The stream did not start playing.'));
      } else if (value.size.width <= 0 || value.size.height <= 0) {
        unawaited(
          _handleEngineFailure(
            'Audio started, but this decoder produced no video frames.',
          ),
        );
      }
    });
  }

  Future<void> _handleEngineFailure(String message) async {
    if (_restarting || _failingOver || _engineHandoffInProgress) return;
    if (_hasUntriedDirectStream) {
      await _tryNextStream(message);
      return;
    }
    if (_decoderMode != VlcDecoderMode.software) {
      await _restart(
        VlcDecoderMode.software,
        reason: 'VLC safe decoder enabled',
      );
      return;
    }
    await _tryNextStream(message);
    await _recordEngineFailure(message);
  }

  Future<void> _recordEngineSuccess() async {
    final database = ref.read(tetoTvDatabaseProvider);
    if (_currentStream.providerId case final providerId?) {
      await database.recordProviderSuccess(providerId);
      return;
    }
    final device = await AndroidTvBridge.instance.getDeviceProfile();
    await database.recordPlayerSuccess(device.key, 'vlc');
  }

  Future<void> _recordEngineFailure(String reason) async {
    final database = ref.read(tetoTvDatabaseProvider);
    if (_currentStream.providerId case final providerId?) {
      await database.recordProviderFailure(providerId, reason);
    } else {
      final device = await AndroidTvBridge.instance.getDeviceProfile();
      await database.recordPlayerFailure(device.key, 'vlc');
    }
    await database.recordDiagnosticEvent(
      category: 'player-vlc',
      message: reason,
    );
  }

  Future<void> _restart(VlcDecoderMode mode, {String? reason}) {
    if (_engineHandoffInProgress) return Future<void>.value();
    return _trackControllerMutation(_runRestart(mode, reason: reason));
  }

  Future<void> _runRestart(VlcDecoderMode mode, {String? reason}) async {
    if (_restarting) return;
    _restarting = true;
    final old = _controller;
    final position = old?.value.position ?? Duration.zero;
    _persistenceReady = false;
    _engineInitialized = false;
    _videoWatchdog?.cancel();
    _decoderMode = mode;
    _pendingResume = position > const Duration(seconds: 2) ? position : null;
    _trackDiscoveryTimer?.cancel();
    _trackDiscoveryAttempts = 0;
    _audioPreferenceApplied = false;
    _subtitlePreferenceApplied = false;
    _completionHandled = false;
    try {
      _queuedSeekTarget = null;
      await _waitForSeekDrain();
      if (_engineHandoffInProgress) return;
      if (old != null) {
        old.removeListener(_onValueChanged);
        if (old.value.isInitialized) await old.stop();
        if (old.isReadyToInitialize == true) {
          await old.dispose();
          _releasedControllers.add(old);
        }
      }
      if (!mounted || _engineHandoffInProgress) return;
      _installController(_createController(_source, mode));
      setState(() => _playbackError = null);
      if (reason != null) _showMessage(reason);
    } finally {
      _restarting = false;
    }
  }

  Future<void> _trackControllerMutation(Future<void> operation) async {
    final guardedOperation = (() async {
      try {
        await operation;
      } catch (error) {
        if (mounted && !_engineHandoffInProgress) {
          setState(() => _playbackError = error.toString());
        }
      }
    })();
    _controllerMutationOperations.add(guardedOperation);
    try {
      await guardedOperation;
    } finally {
      _controllerMutationOperations.remove(guardedOperation);
    }
  }

  Future<void> _waitForControllerMutations() async {
    while (_controllerMutationOperations.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_controllerMutationOperations));
    }
  }

  Future<void> _persistPlayback(
    Duration position, {
    bool force = false,
    VlcPlayerController? controllerOverride,
  }) async {
    if (!_persistenceReady) return;
    final controller = controllerOverride ?? _controller;
    final mediaId = widget.anilistMediaId;
    final episode = widget.episode;
    if (controller == null || mediaId == null || episode == null) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastCheckpointSave) < const Duration(seconds: 10)) {
      return;
    }
    _lastCheckpointSave = now;
    final completed = position.inMilliseconds / duration.inMilliseconds >= .93;
    await ref
        .read(tetoTvDatabaseProvider)
        .saveCheckpoint(
          PlaybackCheckpoint(
            anilistMediaId: mediaId,
            malMediaId: widget.malMediaId,
            episode: episode,
            title: widget.launch.episode.title,
            coverImageUrl: widget.coverImageUrl,
            position: completed ? duration : position,
            duration: duration,
            updatedAt: now,
            completed: completed,
          ),
        );
    if (force && mounted) ref.invalidate(recentPlaybackProvider);
    if (!completed && position > const Duration(seconds: 30)) {
      await AndroidTvBridge.instance.publishWatchNext(
        mediaId: mediaId,
        episode: episode,
        title: widget.launch.episode.title,
        posterUrl: widget.coverImageUrl,
        position: position,
        duration: duration,
      );
    } else if (completed) {
      await AndroidTvBridge.instance.removeWatchNext(mediaId);
    }
  }

  Future<void> _updateMediaSession({bool force = false}) async {
    final controller = _controller;
    if (controller == null) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastMediaSessionUpdate) < const Duration(seconds: 5)) {
      return;
    }
    _lastMediaSessionUpdate = now;
    await AndroidTvBridge.instance.updateMediaSession(
      title: widget.launch.episode.title,
      episode: widget.episode ?? 1,
      position: controller.value.position,
      duration: controller.value.duration,
      playing: controller.value.isPlaying,
      seekBackSeconds: _seekBackSeconds,
      seekForwardSeconds: _seekForwardSeconds,
    );
  }

  void _handleMediaAction(MediaAction action) {
    final controller = _controller;
    if (controller == null) return;
    switch (action.action) {
      case 'play':
        unawaited(controller.play());
      case 'pause':
        unawaited(controller.pause());
      case 'seekTo':
        unawaited(controller.seekTo(Duration(milliseconds: action.value ?? 0)));
      case 'seekBy':
        unawaited(_seekBy(Duration(milliseconds: action.value ?? 0)));
      case 'next':
        unawaited(_playNextEpisode());
      case 'previous':
        unawaited(controller.seekTo(Duration.zero));
    }
  }

  Future<void> _loadSkipSegments() async {
    if (widget.malMediaId == null || widget.episode == null) return;
    try {
      var duration = _controller?.value.duration ?? Duration.zero;
      for (
        var attempt = 0;
        duration <= Duration.zero && attempt < 30;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        duration = _controller?.value.duration ?? Duration.zero;
      }
      if (duration <= Duration.zero) return;
      final segments = await AniSkipClient().segments(
        malMediaId: widget.malMediaId!,
        episode: widget.episode!,
        episodeDuration: duration,
      );
      if (mounted) setState(() => _skips = segments);
      _checkSkips(_controller?.value.position ?? Duration.zero);
    } catch (_) {
      // Skip data is optional.
    }
  }

  void _checkSkips(Duration position) {
    final active = _skips
        .where(
          (skip) =>
              skip.contains(position) &&
              !_consumedSkipSegments.contains(
                '${skip.kind.name}:${skip.start.inMilliseconds}',
              ),
        )
        .firstOrNull;
    if (active != null) {
      final settings = ref.read(settingsPreferencesProvider);
      final autoSkip =
          (active.kind == SkipSegmentKind.opening && settings.autoSkipIntros) ||
          (active.kind == SkipSegmentKind.ending && settings.autoSkipOutros);
      final key = '${active.kind.name}:${active.start.inMilliseconds}';
      if (autoSkip && _consumedSkipSegments.add(key)) {
        final controller = _controller;
        if (mounted) {
          setState(() {
            _activeSkip = null;
            _canSkip = false;
          });
        }
        if (controller != null) {
          unawaited(_autoSkipSegment(controller, active));
        }
        return;
      }
    }
    final available = active != null;
    if (mounted && (available != _canSkip || !identical(active, _activeSkip))) {
      setState(() {
        _canSkip = available;
        _activeSkip = active;
      });
      if (active != null) _focusSkipOnce(active);
    }
  }

  void _focusSkipOnce(SkipSegment segment) {
    final key = '${segment.kind.name}:${segment.start.inMilliseconds}';
    if (!_autoFocusedSkipSegments.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activeSkip == segment) _skipFocus.requestFocus();
    });
  }

  Future<void> _skipCurrentSegment() async {
    if (_skipInProgress || _engineHandoffInProgress) return;
    final controller = _controller;
    final segment = _activeSkip;
    if (controller == null || segment == null) return;
    _skipInProgress = true;
    final duration = controller.value.duration;
    final target = safeSkipSegmentTarget(
      requested: segment.end,
      duration: duration,
    );
    final segmentKey = '${segment.kind.name}:${segment.start.inMilliseconds}';
    _consumedSkipSegments.add(segmentKey);
    if (mounted) {
      setState(() {
        _activeSkip = null;
        _canSkip = false;
      });
    }
    try {
      final wasPlaying = controller.value.isPlaying;
      final succeeded = await _seekForSkip(controller, target);
      if (!succeeded) throw StateError('skip seek failed');
      if (mounted && !_engineHandoffInProgress) {
        _showMessage(segment.actionLabel.replaceFirst('Skip', 'Skipped'));
      }
      if (!wasPlaying &&
          segment.kind == SkipSegmentKind.ending &&
          skipSegmentReachesPlaybackEnd(
            requestedEnd: segment.end,
            duration: duration,
          )) {
        _handlePlaybackCompleted();
      }
    } catch (_) {
      _consumedSkipSegments.remove(segmentKey);
      if (mounted && !_engineHandoffInProgress) {
        _showMessage('Could not skip this segment');
      }
    } finally {
      _skipInProgress = false;
    }
  }

  Future<void> _autoSkipSegment(
    VlcPlayerController controller,
    SkipSegment segment,
  ) async {
    if (_skipInProgress || _engineHandoffInProgress) return;
    _skipInProgress = true;
    final segmentKey = '${segment.kind.name}:${segment.start.inMilliseconds}';
    try {
      final duration = controller.value.duration;
      final wasPlaying = controller.value.isPlaying;
      final succeeded = await _seekForSkip(
        controller,
        safeSkipSegmentTarget(requested: segment.end, duration: duration),
      );
      if (!succeeded) throw StateError('skip seek failed');
      if (mounted && !_engineHandoffInProgress) {
        _showMessage(
          segment.kind == SkipSegmentKind.opening
              ? 'Intro skipped'
              : 'Outro skipped',
        );
      }
      if (!wasPlaying &&
          segment.kind == SkipSegmentKind.ending &&
          skipSegmentReachesPlaybackEnd(
            requestedEnd: segment.end,
            duration: duration,
          )) {
        _handlePlaybackCompleted();
      }
    } catch (_) {
      _consumedSkipSegments.remove(segmentKey);
      if (mounted && !_engineHandoffInProgress) {
        _showMessage('Could not skip this segment');
      }
    } finally {
      _skipInProgress = false;
    }
  }

  void _handlePlaybackCompleted() {
    if (_completionHandled || _engineHandoffInProgress) return;
    _completionHandled = true;
    if (!_syncHandled &&
        widget.episode != null &&
        (widget.anilistMediaId != null || widget.malMediaId != null)) {
      _syncHandled = true;
      unawaited(_syncProgress());
    }
    unawaited(_offerNextEpisode());
  }

  Future<bool> _seekForSkip(VlcPlayerController controller, Duration target) {
    if (_engineHandoffInProgress || controller != _controller) {
      return Future<bool>.value(false);
    }
    late final Future<bool> operation;
    operation =
        (() async {
          try {
            await controller.seekTo(target);
            return true;
          } catch (_) {
            return false;
          }
        })().whenComplete(() {
          if (identical(_skipSeekOperation, operation)) {
            _skipSeekOperation = null;
          }
        });
    _skipSeekOperation = operation;
    return operation;
  }

  Future<void> _openAudioTrackPicker() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      var tracks = await controller.getAudioTracks();
      for (var attempt = 0; tracks.isEmpty && attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        tracks = await controller.getAudioTracks();
      }
      final ids = tracks.keys.where((id) => id >= 0).toList()..sort();
      if (ids.isEmpty) {
        _showMessage('No alternate audio tracks');
        return;
      }
      final current = await controller.getAudioTrack() ?? ids.first;
      if (!mounted) return;
      _controlsTimer?.cancel();
      final selected = await showPlayerTrackPicker<int>(
        context: context,
        title: 'Audio track',
        icon: Icons.audiotrack_rounded,
        selectedValue: current,
        options: ids
            .map(
              (id) => PlayerTrackOption<int>(
                value: id,
                label: tracks[id] ?? 'Track $id',
                detail:
                    playerTrackMatchesLanguage(
                      title: tracks[id],
                      preferredLanguage: 'eng',
                    )
                    ? 'English'
                    : null,
                icon: Icons.surround_sound_rounded,
              ),
            )
            .toList(growable: false),
      );
      if (!mounted || selected == null) return;
      await controller.setAudioTrack(selected);
      _audioPreferenceApplied = true;
      await _saveTrackPreferences(audioLabel: tracks[selected]);
      _showMessage('Audio: ${tracks[selected] ?? 'Track $selected'}');
    } catch (_) {
      _showMessage('Audio tracks are not available yet');
    } finally {
      if (mounted) _showControls();
    }
  }

  Future<void> _openSubtitleTrackPicker() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      var tracks = await controller.getSpuTracks();
      for (var attempt = 0; tracks.isEmpty && attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        tracks = await controller.getSpuTracks();
      }
      final ids = <int>[-1, ...tracks.keys.where((id) => id >= 0)]..sort();
      final current = await controller.getSpuTrack() ?? -1;
      if (!mounted) return;
      _controlsTimer?.cancel();
      final selected = await showPlayerTrackPicker<int>(
        context: context,
        title: 'Closed captions',
        icon: Icons.closed_caption_rounded,
        selectedValue: current,
        options: ids
            .map(
              (id) => PlayerTrackOption<int>(
                value: id,
                label: id == -1 ? 'Off' : tracks[id] ?? 'Track $id',
                detail: id == -1
                    ? 'Disable captions'
                    : playerTrackMatchesLanguage(
                        title: tracks[id],
                        preferredLanguage: 'eng',
                      )
                    ? 'English'
                    : null,
                icon: id == -1
                    ? Icons.closed_caption_disabled_rounded
                    : Icons.closed_caption_rounded,
              ),
            )
            .toList(growable: false),
      );
      if (!mounted || selected == null) return;
      await controller.setSpuTrack(selected);
      _subtitlePreferenceApplied = true;
      await _saveTrackPreferences(
        subtitleLabel: selected == -1 ? null : tracks[selected],
        subtitleEnabled: selected != -1,
      );
      _showMessage(
        selected == -1
            ? 'Subtitles: Off'
            : 'Subtitles: ${tracks[selected] ?? 'Track $selected'}',
      );
    } catch (_) {
      _showMessage('Subtitle tracks are not available yet');
    } finally {
      if (mounted) _showControls();
    }
  }

  Future<void> _cyclePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    const values = ['', '16:9', '4:3'];
    const labels = ['Picture: Original', 'Picture: 16:9', 'Picture: 4:3'];
    _videoAspectIndex = (_videoAspectIndex + 1) % values.length;
    try {
      await controller.setVideoAspectRatio(values[_videoAspectIndex]);
      _showMessage(labels[_videoAspectIndex]);
    } catch (_) {
      _showMessage('This device cannot change picture mode');
    }
  }

  Future<void> _saveTrackPreferences({
    String? audioLabel,
    String? subtitleLabel,
    bool? subtitleEnabled,
  }) async {
    final mediaId = widget.anilistMediaId;
    if (mediaId == null) return;
    _preferences = _preferences.copyWith(
      audioLanguage: audioLabel == null
          ? _preferences.audioLanguage
          : canonicalPlayerLanguage(audioLabel),
      subtitleLanguage: subtitleLabel == null
          ? _preferences.subtitleLanguage
          : canonicalPlayerLanguage(subtitleLabel),
      subtitleEnabled: subtitleEnabled ?? _preferences.subtitleEnabled,
      subtitlePreferenceSet: subtitleEnabled == null
          ? _preferences.subtitlePreferenceSet
          : true,
      subtitleSize: _subtitleSize,
      subtitlePosition: _preferences.subtitlePosition,
      subtitleDelayMs: _subtitleDelayMs,
      audioDelayMs: _audioDelayMs,
    );
    await ref
        .read(tetoTvDatabaseProvider)
        .saveSeriesPreferences(mediaId, _preferences);
  }

  Future<void> _seekBy(Duration offset) async {
    if (_engineHandoffInProgress || _restarting) return;
    final controller = _controller;
    if (controller == null) return;
    _queuedSeekTarget = playerSeekTarget(
      position: _queuedSeekTarget ?? controller.value.position,
      offset: offset,
      duration: controller.value.duration,
    );
    await _drainSeekQueue();
  }

  Future<void> _seekTo(Duration target) async {
    if (_engineHandoffInProgress || _restarting) return;
    final controller = _controller;
    if (controller == null) return;
    _queuedSeekTarget = playerSeekTarget(
      position: target,
      offset: Duration.zero,
      duration: controller.value.duration,
    );
    await _drainSeekQueue();
  }

  Future<void> _drainSeekQueue() async {
    final activeDrain = _seekDrainCompleter;
    if (activeDrain != null) {
      await activeDrain.future;
      return;
    }
    final drain = Completer<void>();
    _seekDrainCompleter = drain;
    try {
      while (_queuedSeekTarget != null) {
        final target = _queuedSeekTarget!;
        _queuedSeekTarget = null;
        final activeController = _controller;
        if (activeController == null) return;
        await activeController.seekTo(target);
      }
    } catch (_) {
      _queuedSeekTarget = null;
      if (mounted && !_engineHandoffInProgress && !_restarting) {
        _showMessage('Could not seek to that position');
      }
    } finally {
      if (identical(_seekDrainCompleter, drain)) {
        _seekDrainCompleter = null;
      }
      if (!drain.isCompleted) drain.complete();
    }
  }

  Future<void> _waitForSeekDrain() async {
    final drain = _seekDrainCompleter;
    if (drain != null) await drain.future;
  }

  Duration _effectiveHandoffPosition() {
    final position = _controller?.value.position ?? Duration.zero;
    final inherited = _pendingResume;
    if (inherited != null &&
        inherited > position &&
        position < const Duration(seconds: 2)) {
      return inherited;
    }
    return position;
  }

  Future<StreamReady?> _resolveRelease(ReleaseCandidate release) async {
    final token = await ref
        .read(debridTokenServiceProvider)
        .accessToken(widget.debridService);
    if (token == null || token.isEmpty) return null;
    final source = SingleReleaseSource(release);
    final resolver = createDebridStreamResolver(
      service: widget.debridService,
      token: token,
      source: source,
    );
    await for (final resolution in resolver.resolve(widget.launch.episode)) {
      if (resolution is StreamReady) return resolution;
    }
    return null;
  }

  Future<void> _tryNextStream(String reason) async {
    if (_failingOver) return;
    _failingOver = true;
    Object? terminalFailure;
    try {
      if (await _switchToNextDirectStream()) return;
      while (_alternativeIndex < widget.launch.alternatives.length) {
        final candidate = widget.launch.alternatives[_alternativeIndex++];
        _showMessage('Trying another compatible stream...');
        StreamReady? ready;
        try {
          ready = await _resolveRelease(candidate);
        } catch (error) {
          if (isTerminalDebridAlternativeFailure(error)) {
            terminalFailure = error;
            break;
          }
          // A rejected or broken release must not abort the remaining list.
          continue;
        }
        if (ready == null) continue;
        _source = ready.uri.toString();
        _release = candidate;
        _currentStream = ready;
        _preferences = _preferences.copyWith(
          subtitleEnabled: subtitlesEnabledByDefault(candidate),
        );
        _decoderMode = _releaseRequiresSoftware(candidate)
            ? VlcDecoderMode.software
            : VlcDecoderMode.hardwareCopy;
        await _restart(_decoderMode, reason: 'Switched to another stream');
        return;
      }
      if (mounted) {
        setState(
          () => _playbackError =
              terminalFailure?.toString() ??
              'Every debrid stream failed. $reason',
        );
      }
    } finally {
      _failingOver = false;
    }
  }

  Future<bool> _switchToNextDirectStream() async {
    if (!_currentStream.isWebStream) return false;
    _failedDirectStreamUris.add(_currentStream.uri.toString());
    final candidates = _directStreamOptions.where(
      (option) =>
          option.stream.isWebStream &&
          !_failedDirectStreamUris.contains(option.stream.uri.toString()),
    );
    for (final candidate in candidates) {
      final requestedUri = candidate.stream.uri;
      _failedDirectStreamUris.add(requestedUri.toString());
      final option = await _preflightDirectStream(candidate);
      if (option == null) continue;
      if (validatedRedirectWasAlreadyAttempted(
        requestedUri: requestedUri,
        validatedUri: option.stream.uri,
        attemptedUris: _failedDirectStreamUris,
      )) {
        continue;
      }
      _failedDirectStreamUris.add(option.stream.uri.toString());
      _currentStream = option.stream;
      _release = option.release;
      _source = option.stream.uri.toString();
      _decoderMode = _releaseRequiresSoftware(option.release)
          ? VlcDecoderMode.software
          : VlcDecoderMode.hardwareCopy;
      await _restart(
        _decoderMode,
        reason: 'Recovered with ${playbackStreamOptionLabel(option)}',
      );
      return true;
    }
    return false;
  }

  Future<void> _returnToStreamPicker() async {
    final position = _controller?.value.position ?? Duration.zero;
    await _persistPlayback(position, force: true);
    if (mounted && context.canPop()) context.pop();
  }

  Future<void> _syncProgress() async {
    if (widget.episode == null) return;
    try {
      final synced = await ref
          .read(trackingSyncServiceProvider)
          .syncEpisode(
            completedEpisodes: widget.episode!,
            anilistMediaId: widget.anilistMediaId,
            malMediaId: widget.malMediaId,
          );
      if (synced) {
        ref.invalidate(trackingHomeProvider);
        _showMessage('Episode progress saved');
      } else {
        _showMessage('Progress will sync when the tracker reconnects');
      }
    } catch (_) {
      _showMessage('Progress will sync when the tracker reconnects');
    }
  }

  Future<void> _offerNextEpisode() async {
    final controller = _controller;
    if (!mounted || controller == null) return;
    try {
      await _persistPlayback(controller.value.duration, force: true);
    } catch (_) {
      // Completion should not become an uncaught player error when checkpoint
      // or watch-next persistence is temporarily unavailable.
    }
    if (!mounted || _engineHandoffInProgress) return;
    final play = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _VlcNextEpisodeDialog(),
    );
    if (play == true) await _playNextEpisode();
  }

  Future<void> _playNextEpisode() async {
    if (widget.anilistMediaId == null || widget.episode == null) return;
    try {
      final details = await ref
          .read(catalogClientProvider)
          .details(widget.anilistMediaId!);
      final nextEpisode = widget.episode! + 1;
      if (details.episodes != null && nextEpisode > details.episodes!) return;
      if (!mounted) return;
      final route = Uri(
        path: '/resolve',
        queryParameters: {
          'anilistId': widget.anilistMediaId.toString(),
          'title': details.title,
          'synonyms': details.synonyms.join('|'),
          'episode': nextEpisode.toString(),
          'autoplay': '1',
          if (details.seasonYear != null) 'year': details.seasonYear.toString(),
          if (details.coverImageUrl != null) 'cover': details.coverImageUrl!,
          if (widget.malMediaId != null) 'malId': widget.malMediaId.toString(),
        },
      ).toString();
      final controller = _controller;
      final completedPosition =
          controller != null && controller.value.duration > Duration.zero
          ? controller.value.duration
          : controller?.value.position ?? Duration.zero;
      if (!await _prepareForEngineHandoff(completedPosition)) return;
      if (!mounted) return;
      context.pushReplacement(route);
    } catch (_) {
      _showMessage('The next episode could not be prepared');
    }
  }

  void _playOrPause() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.value.isPlaying ? controller.pause() : controller.play(),
    );
  }

  Stream<WebStreamSearchProgress> _webSourceSearch({bool refresh = false}) =>
      ref
          .read(webStreamAggregatorProvider)
          .watchSearchIncrementally(widget.launch.episode, refresh: refresh);

  Future<void> _startWebSourceDiscovery({bool restart = false}) async {
    if (!_currentStream.isWebStream ||
        !ref.read(settingsPreferencesProvider).webStreamsEnabled) {
      return;
    }
    if (_sourceDiscoverySubscription != null && !restart) return;
    await _sourceDiscoverySubscription?.cancel();
    _sourceDiscoverySubscription = _webSourceSearch().listen((progress) {
      if (!mounted) return;
      final merged = mergePlaybackStreamOptions(
        _directStreamOptions,
        progress.aggregation.streams.map(playbackOptionForWebStream),
      );
      final before = _directStreamOptions
          .map((option) => option.stream.uri.toString())
          .join('\n');
      final after = merged
          .map((option) => option.stream.uri.toString())
          .join('\n');
      if (before != after) setState(() => _directStreamOptions = merged);
    }, onError: (_) {});
  }

  Future<PlaybackStreamOption?> _preflightDirectStream(
    PlaybackStreamOption option,
  ) async {
    if (!option.stream.isWebStream) return option;
    _showMessage('Checking ${playbackStreamOptionLabel(option)}...');
    try {
      final validated = await const WebStreamValidator().validate(
        option.stream.uri,
        option.stream.headers,
      );
      final validatedOption = PlaybackStreamOption(
        stream: StreamReady(
          uri: validated.uri,
          displayName: option.stream.displayName,
          headers: validated.headers,
          externalSubtitle: option.stream.externalSubtitle,
          providerId: option.stream.providerId,
          providerName: option.stream.providerName,
        ),
        release: option.release,
      );
      _directStreamOptions = replaceValidatedPlaybackStreamOption(
        options: _directStreamOptions,
        requestedUri: option.stream.uri,
        validated: validatedOption,
      );
      return validatedOption;
    } catch (error) {
      _failedDirectStreamUris.add(option.stream.uri.toString());
      _showMessage(
        'That source is unavailable: '
        "${error.toString().replaceFirst('FormatException: ', '')}",
      );
      return null;
    }
  }

  Future<void> _openStreamSourcePicker() async {
    _controlsTimer?.cancel();
    final selected = await showPlayerStreamSourcePicker(
      context: context,
      initialOptions: _directStreamOptions,
      selectedUri: _currentStream.uri,
      onOptionsChanged: (options) {
        if (mounted) setState(() => _directStreamOptions = options);
      },
      discover:
          _currentStream.isWebStream &&
              ref.read(settingsPreferencesProvider).webStreamsEnabled
          ? _webSourceSearch
          : null,
    );
    if (!mounted) return;
    if (selected == null || selected.stream.uri == _currentStream.uri) {
      _showControls();
      return;
    }
    final option = await _preflightDirectStream(selected);
    if (!mounted || option == null) {
      _showControls();
      return;
    }
    _failedDirectStreamUris.clear();
    _currentStream = option.stream;
    _source = option.stream.uri.toString();
    _release = option.release;
    _directStreamOptions = mergePlaybackStreamOptions(
      [option],
      _directStreamOptions.where(
        (candidate) => candidate.stream.uri != selected.stream.uri,
      ),
    );
    _decoderMode = _releaseRequiresSoftware(option.release)
        ? VlcDecoderMode.software
        : VlcDecoderMode.hardwareCopy;
    await _restart(
      _decoderMode,
      reason: 'Playing ${playbackStreamOptionLabel(option)}',
    );
    _showControls();
  }

  // TODO: Remove after older persisted player-route labels are migrated.
  // ignore: unused_element
  static String _streamOptionLabel(PlaybackStreamOption option) {
    final quality = option.release.quality?.trim();
    final provider =
        option.stream.providerName ??
        option.release.provider ??
        option.release.sourceId;
    return [
      if (quality != null && quality.isNotEmpty) quality,
      provider,
    ].join(' • ');
  }

  Future<bool> _prepareForEngineHandoff(Duration position) async {
    if (_engineHandoffInProgress) return false;
    _engineHandoffInProgress = true;
    _scrubController.cancel();
    _controlsTimer?.cancel();
    _initializationWatchdog?.cancel();
    _videoWatchdog?.cancel();
    _trackDiscoveryTimer?.cancel();
    final controller = _controller;
    if (mounted) {
      setState(() {
        _controlsVisible = false;
        _controller = null;
      });
    }

    // Remove libVLC's TextureRegistry surface before another native engine is
    // constructed, then await decoder disposal before notifying the router.
    await WidgetsBinding.instance.endOfFrame;
    _queuedSeekTarget = null;
    await _waitForSeekDrain();
    final skipSeek = _skipSeekOperation;
    if (skipSeek != null) await skipSeek;
    await _waitForControllerMutations();
    try {
      await _persistPlayback(
        position,
        force: true,
        controllerOverride: controller,
      );
    } catch (_) {
      // Checkpoint I/O must not strand a completed decoder handoff.
    }
    await _mediaActionSubscription?.cancel();
    await _sourceDiscoverySubscription?.cancel();
    try {
      if (controller != null) {
        controller.removeListener(_onValueChanged);
        if (!_releasedControllers.contains(controller)) {
          if (controller.value.isInitialized) {
            try {
              await controller.stop();
            } catch (_) {
              // The render gate may already have released the native view;
              // controller.dispose() below still clears the platform registry.
            }
          }
          if (controller.isReadyToInitialize == true) {
            await controller.dispose();
            _releasedControllers.add(controller);
          }
        }
      }
      _controllerReleasedForHandoff = true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _trackMessage =
              'Player switch stopped safely. Press Back and reopen playback.';
        });
      }
      return false;
    }
    try {
      await AndroidTvBridge.instance.clearMediaSession();
      await AndroidTvBridge.instance.clearPreferredFrameRate();
    } catch (_) {
      // Decoder ownership is already released; session cleanup is best effort.
    }
    _nativePlaybackStateClearedForHandoff = true;
    return mounted;
  }

  Future<void> _handoffTo(PreferredPlayer selected) async {
    final callback = widget.onSelectEngine;
    if (callback == null && selected != PreferredPlayer.mpv) {
      _showMessage('This player is not available from this screen');
      _showControls();
      return;
    }
    final position = _effectiveHandoffPosition();
    final stream = _currentStream;
    final release = _release;
    final directStreams = List<PlaybackStreamOption>.unmodifiable(
      _directStreamOptions,
    );
    if (!await _prepareForEngineHandoff(position)) return;
    if (!mounted) return;
    if (callback != null) {
      callback(selected, position, stream, release, directStreams);
    } else {
      widget.onUseMpv(position, stream, release, directStreams);
    }
  }

  Future<void> _openPlayerPicker() async {
    _controlsTimer?.cancel();
    final selected = await showPlayerEnginePicker(
      context: context,
      current: PreferredPlayer.vlc,
    );
    if (!mounted || selected == null || selected == PreferredPlayer.vlc) {
      if (mounted) _showControls();
      return;
    }
    await _handoffTo(selected);
  }

  Future<void> _openOptions() async {
    _controlsTimer?.cancel();
    final result = await showDialog<_VlcMenuResult>(
      context: context,
      barrierColor: const Color(0xDD000000),
      builder: (_) => _VlcOptionsDialog(
        mode: _decoderMode,
        playbackRate: _playbackRate,
        subtitleSize: _subtitleSize,
        subtitleDelayMs: _subtitleDelayMs,
        audioDelayMs: _audioDelayMs,
        hasAlternateStreams:
            _alternativeIndex < widget.launch.alternatives.length,
        hasDirectSources: _currentStream.isWebStream,
      ),
    );
    if (!mounted || result == null) {
      _scheduleControlsHide();
      return;
    }
    switch (result.type) {
      case 'decoder':
        await _restart(result.value as VlcDecoderMode);
      case 'rate':
        final rate = result.value as double;
        _playbackRate = rate;
        await _controller?.setPlaybackSpeed(rate);
        _showMessage('Playback speed ${rate}x');
      case 'subtitleSize':
        _subtitleSize = result.value as double;
        _preferences = _preferences.copyWith(subtitleSize: _subtitleSize);
        await _saveTrackPreferences();
        await _restart(
          _decoderMode,
          reason: 'Subtitle size ${_subtitleSize.round()}',
        );
      case 'subtitleDelay':
        _subtitleDelayMs = result.value as int;
        await _controller?.setSpuDelay(_subtitleDelayMs);
        _showMessage('Subtitle delay ${_subtitleDelayMs}ms');
      case 'audioDelay':
        _audioDelayMs = result.value as int;
        await _controller?.setAudioDelay(_audioDelayMs);
        _showMessage('Audio delay ${_audioDelayMs}ms');
      case 'retry':
        await _restart(_decoderMode, reason: 'Stream restarted');
      case 'nextStream':
        await _tryNextStream('Stream changed manually');
      case 'sources':
        await _openStreamSourcePicker();
      case 'mpv':
        await _handoffTo(PreferredPlayer.mpv);
    }
    if (!mounted) return;
    _scheduleControlsHide();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_engineHandoffInProgress) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (consumeHiddenPlayerHudDownRepeat(
      key: key,
      isRepeat: event is KeyRepeatEvent,
      controlsVisible: _controlsVisible,
    )) {
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.arrowDown &&
        _controlsVisible) {
      _hideControls();
      return KeyEventResult.handled;
    }
    final directional =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final wasHidden = !_controlsVisible;
    _showControls(focusControls: wasHidden && directional);
    if (!node.hasPrimaryFocus &&
        (directional ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    if (node.hasPrimaryFocus && directional) {
      _showControls(focusControls: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyJ ||
        key == LogicalKeyboardKey.mediaRewind) {
      unawaited(_seekBy(Duration(seconds: -_seekBackSeconds)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.mediaFastForward) {
      unawaited(_seekBy(Duration(seconds: _seekForwardSeconds)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.keyK) {
      _playOrPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      unawaited(_openSubtitleTrackPicker());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      if (_decoderMode == VlcDecoderMode.software) {
        _showMessage('VLC software decoding is already enabled');
      } else {
        unawaited(
          _restart(
            VlcDecoderMode.software,
            reason: 'VLC software decoding enabled',
          ),
        );
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM ||
        key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.gameButtonY) {
      unawaited(_openOptions());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    _trackMessageTimer?.cancel();
    setState(() => _trackMessage = message);
    _trackMessageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _trackMessage == message) {
        setState(() => _trackMessage = null);
      }
    });
  }

  void _showControls({bool focusControls = false}) {
    if (mounted) setState(() => _controlsVisible = true);
    if (focusControls) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playFocus.requestFocus();
      });
    }
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(playerControlsIdleTimeout, () {
      if (mounted) _hideControls();
    });
  }

  void _hideControls() {
    _controlsTimer?.cancel();
    if (mounted && _controlsVisible) {
      setState(() => _controlsVisible = false);
    }
    _rootFocus.requestFocus();
  }

  void _handleSurfaceTap() {
    if (_engineHandoffInProgress) return;
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _handleSurfaceDoubleTap() {
    if (_engineHandoffInProgress) return;
    final details = _touchDoubleTapDetails;
    final controller = _controller;
    if (details == null || controller == null || !mounted) return;
    final width = MediaQuery.sizeOf(context).width;
    final x = details.localPosition.dx;
    if (x < width / 3) {
      unawaited(_seekBy(Duration(seconds: -_seekBackSeconds)));
    } else if (x > width * 2 / 3) {
      unawaited(_seekBy(Duration(seconds: _seekForwardSeconds)));
    } else {
      _playOrPause();
    }
    _showControls();
  }

  Future<void> _confirmExit() async {
    if (_confirmingExit || !mounted) return;
    if (_engineHandoffInProgress) {
      setState(() => _allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.canPop()) context.pop();
      });
      return;
    }
    _confirmingExit = true;
    final controller = _controller;
    final wasPlaying = controller?.value.isPlaying == true;
    if (wasPlaying) await controller?.pause();
    if (!mounted) return;
    final exit = await showPlayerExitConfirmation(context);
    _confirmingExit = false;
    if (!mounted) return;
    if (exit == true) {
      if (controller != null) {
        await _persistPlayback(controller.value.position, force: true);
      }
      if (!mounted) return;
      setState(() => _allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.canPop()) context.pop();
      });
    } else if (wasPlaying) {
      await controller?.play();
      _showControls(focusControls: true);
    }
  }

  @override
  void dispose() {
    _scrubController.cancel();
    final controller = _controller;
    if (controller != null && !_controllerReleasedForHandoff) {
      unawaited(_persistPlayback(controller.value.position, force: true));
      controller.removeListener(_onValueChanged);
      if (controller.isReadyToInitialize == true) {
        unawaited(controller.dispose());
      }
    }
    if (!_nativePlaybackStateClearedForHandoff) {
      unawaited(AndroidTvBridge.instance.clearMediaSession());
      unawaited(AndroidTvBridge.instance.clearPreferredFrameRate());
    }
    _mediaActionSubscription?.cancel();
    _controlsTimer?.cancel();
    _trackMessageTimer?.cancel();
    _initializationWatchdog?.cancel();
    _videoWatchdog?.cancel();
    _trackDiscoveryTimer?.cancel();
    _sourceDiscoverySubscription?.cancel();
    _rootFocus.dispose();
    _playFocus.dispose();
    _skipFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_scrubController.cancel()) {
          unawaited(_confirmExit());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleSurfaceTap,
            onDoubleTapDown: (details) => _touchDoubleTapDetails = details,
            onDoubleTap: _handleSurfaceDoubleTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null && !_engineHandoffInProgress)
                  KeyedSubtree(
                    // Never replace the Android platform view when initialization
                    // completes. Re-keying this subtree disposes libVLC's surface
                    // while its decoder is producing the first frame.
                    key: const ValueKey('vlc-player-surface'),
                    child: Center(
                      child: VlcPlayer(
                        controller: controller,
                        aspectRatio: 16 / 9,
                        // flutter_vlc_player owns a TextureRegistry surface. Its
                        // AndroidView/virtual-display path keeps that surface alive
                        // across the controller's asynchronous initialization;
                        // hybrid composition abandons it on several TV runtimes.
                        virtualDisplay: true,
                        placeholder: const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                if (_engineInitialized)
                  const SizedBox(
                    key: ValueKey('vlc-player-initialized'),
                    width: 0,
                    height: 0,
                  ),
                if (controller == null && !_engineHandoffInProgress)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.cyan),
                  )
                else if (controller != null && !_engineHandoffInProgress)
                  ValueListenableBuilder<VlcPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, child) => Stack(
                      children: [
                        if (value.position > const Duration(seconds: 1) &&
                            value.size.width > 0 &&
                            value.size.height > 0)
                          const SizedBox(
                            key: ValueKey('vlc-playback-advancing'),
                            width: 0,
                            height: 0,
                          ),
                        if (value.isBuffering)
                          const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.cyan,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (controller != null && !_engineHandoffInProgress)
                  Positioned(
                    left: 34,
                    right: 34,
                    top: 28,
                    child: ValueListenableBuilder<VlcPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, child) => value.isPlaying
                          ? const SizedBox.shrink()
                          : Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                            ),
                    ),
                  ),
                ExcludeFocus(
                  excluding: !_controlsVisible,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: _UnifiedVlcPlayerChrome(
                        controller: controller,
                        title: widget.title,
                        streamLabel:
                            _currentStream.providerName ??
                            '${widget.debridService.displayName} stream',
                        playFocusNode: _playFocus,
                        seekBackSeconds: _seekBackSeconds,
                        seekForwardSeconds: _seekForwardSeconds,
                        mode: _decoderMode,
                        onRewind: () => unawaited(
                          _seekBy(Duration(seconds: -_seekBackSeconds)),
                        ),
                        onPlayPause: _playOrPause,
                        onForward: () => unawaited(
                          _seekBy(Duration(seconds: _seekForwardSeconds)),
                        ),
                        onSeek: (target) => unawaited(_seekTo(target)),
                        onAudio: () => unawaited(_openAudioTrackPicker()),
                        onSubtitles: () =>
                            unawaited(_openSubtitleTrackPicker()),
                        onCaptionSize: () => unawaited(_openOptions()),
                        onPicture: () => unawaited(_cyclePicture()),
                        onFixVideo: () => unawaited(_openPlayerPicker()),
                        onSources: _currentStream.isWebStream
                            ? () => unawaited(_openStreamSourcePicker())
                            : null,
                        onOptions: () => unawaited(_openOptions()),
                        onDismiss: _hideControls,
                        scrubController: _scrubController,
                        onScrubStarted: () => _controlsTimer?.cancel(),
                        onScrubFinished: _scheduleControlsHide,
                      ),
                    ),
                  ),
                ),
                if (_canSkip && _activeSkip != null)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    right: MediaQuery.sizeOf(context).width < 720 ? 16 : 38,
                    bottom: _controlsVisible
                        ? (MediaQuery.sizeOf(context).height < 480 ? 132 : 184)
                        : 26,
                    child: TetoSkipSegmentOverlay(
                      focusNode: _skipFocus,
                      label: _activeSkip!.actionLabel,
                      onPressed: () => unawaited(_skipCurrentSegment()),
                    ),
                  ),
                if (_playbackError case final error?)
                  Positioned(
                    left: 36,
                    right: 36,
                    bottom: 104,
                    child: _VlcPlaybackError(
                      message: error,
                      onRetry: () => unawaited(_restart(_decoderMode)),
                      onNextStream: () =>
                          unawaited(_tryNextStream('Selected after failure')),
                      onUseMpv: () =>
                          unawaited(_handoffTo(PreferredPlayer.mpv)),
                      onChooseStream: () => unawaited(_returnToStreamPicker()),
                    ),
                  ),
                if (_trackMessage case final message?)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEE0A0A0A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: .6),
                        ),
                      ),
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnifiedVlcPlayerChrome extends StatelessWidget {
  const _UnifiedVlcPlayerChrome({
    required this.controller,
    required this.title,
    required this.streamLabel,
    required this.playFocusNode,
    required this.seekBackSeconds,
    required this.seekForwardSeconds,
    required this.mode,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onSeek,
    required this.onAudio,
    required this.onSubtitles,
    required this.onCaptionSize,
    required this.onPicture,
    required this.onFixVideo,
    this.onSources,
    required this.onOptions,
    required this.onDismiss,
    required this.scrubController,
    this.onScrubStarted,
    this.onScrubFinished,
  });

  final VlcPlayerController? controller;
  final String title;
  final String streamLabel;
  final FocusNode playFocusNode;
  final int seekBackSeconds;
  final int seekForwardSeconds;
  final VlcDecoderMode mode;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;
  final VoidCallback onCaptionSize;
  final VoidCallback onPicture;
  final VoidCallback onFixVideo;
  final VoidCallback? onSources;
  final VoidCallback onOptions;
  final VoidCallback onDismiss;
  final PlayerScrubController scrubController;
  final VoidCallback? onScrubStarted;
  final VoidCallback? onScrubFinished;

  @override
  Widget build(BuildContext context) {
    final activeController = controller;
    if (activeController == null) {
      return _chrome(null);
    }
    return ValueListenableBuilder<VlcPlayerValue>(
      valueListenable: activeController,
      builder: (context, value, child) => _chrome(value),
    );
  }

  Widget _chrome(VlcPlayerValue? value) {
    return TetoPlayerChrome(
      engineKey: 'vlc',
      engineLabel: vlcDecoderLabel(mode),
      title: title,
      streamLabel: streamLabel,
      position: value?.position ?? Duration.zero,
      duration: value?.duration ?? Duration.zero,
      isPlaying: value?.isPlaying ?? false,
      playFocusNode: playFocusNode,
      seekBackSeconds: seekBackSeconds,
      seekForwardSeconds: seekForwardSeconds,
      onRewind: onRewind,
      onPlayPause: onPlayPause,
      onForward: onForward,
      onSeek: onSeek,
      onAudio: onAudio,
      onSubtitles: onSubtitles,
      onCaptionSize: onCaptionSize,
      onPicture: onPicture,
      onFixVideo: onFixVideo,
      onSources: onSources,
      onOptions: onOptions,
      onDismiss: onDismiss,
      scrubController: scrubController,
      onScrubStarted: onScrubStarted,
      onScrubFinished: onScrubFinished,
    );
  }
}

// TODO: Remove after the shared chrome has shipped through one stable release.
// ignore: unused_element
class _VlcPlayerChrome extends StatelessWidget {
  const _VlcPlayerChrome({
    required this.controller,
    required this.title,
    required this.streamLabel,
    required this.playFocusNode,
    required this.seekBackSeconds,
    required this.seekForwardSeconds,
    required this.mode,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onAudio,
    required this.onSubtitles,
    required this.onPicture,
    required this.onFixVideo,
    // ignore: unused_element_parameter
    this.onSources,
    required this.onOptions,
  });

  final VlcPlayerController? controller;
  final String title;
  final String streamLabel;
  final FocusNode playFocusNode;
  final int seekBackSeconds;
  final int seekForwardSeconds;
  final VlcDecoderMode mode;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;
  final VoidCallback onPicture;
  final VoidCallback onFixVideo;
  final VoidCallback? onSources;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 720 ||
        MediaQuery.sizeOf(context).height < 480;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          compact ? 12 : 28,
          0,
          compact ? 12 : 28,
          compact ? 10 : 24,
        ),
        child: Container(
          key: const ValueKey('vlc-bottom-player-chrome'),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            compact ? 9 : 12,
            compact ? 12 : 16,
            compact ? 9 : 13,
          ),
          decoration: BoxDecoration(
            color: const Color(0xD6080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withValues(alpha: .7)),
            boxShadow: const [
              BoxShadow(
                color: Color(0xB3000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: compact
                          ? Theme.of(context).textTheme.titleMedium
                          : Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (!compact) ...[
                    _EngineBadge(
                      text: mode == VlcDecoderMode.software
                          ? 'VLC software'
                          : 'VLC compatibility',
                    ),
                    const SizedBox(width: 10),
                  ],
                  _EngineBadge(text: streamLabel),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                key: const ValueKey('vlc-player-controls-scroll'),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    _VlcControl(
                      icon: Icons.replay_rounded,
                      label: 'Back ${seekBackSeconds}s',
                      onPressed: onRewind,
                    ),
                    const SizedBox(width: 8),
                    if (controller != null)
                      ValueListenableBuilder<VlcPlayerValue>(
                        valueListenable: controller!,
                        builder: (context, value, child) => _VlcControl(
                          focusNode: playFocusNode,
                          primary: true,
                          icon: value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          label: value.isPlaying ? 'Pause' : 'Play',
                          onPressed: onPlayPause,
                        ),
                      )
                    else
                      _VlcControl(
                        focusNode: playFocusNode,
                        primary: true,
                        icon: Icons.play_arrow_rounded,
                        label: 'Play',
                        onPressed: onPlayPause,
                      ),
                    const SizedBox(width: 8),
                    _VlcControl(
                      icon: Icons.forward_rounded,
                      label: 'Forward ${seekForwardSeconds}s',
                      onPressed: onForward,
                    ),
                    const SizedBox(width: 18),
                    _VlcControl(
                      icon: Icons.audiotrack_rounded,
                      label: 'Audio',
                      onPressed: onAudio,
                    ),
                    const SizedBox(width: 8),
                    _VlcControl(
                      icon: Icons.closed_caption_rounded,
                      label: 'CC',
                      onPressed: onSubtitles,
                    ),
                    const SizedBox(width: 8),
                    _VlcControl(
                      icon: Icons.aspect_ratio_rounded,
                      label: 'Picture',
                      onPressed: onPicture,
                    ),
                    const SizedBox(width: 8),
                    _VlcControl(
                      icon: Icons.build_circle_outlined,
                      label: 'Fix video',
                      onPressed: onFixVideo,
                    ),
                    if (onSources != null) ...[
                      const SizedBox(width: 8),
                      _VlcControl(
                        icon: Icons.video_library_rounded,
                        label: 'Sources',
                        onPressed: onSources!,
                      ),
                    ],
                    const SizedBox(width: 18),
                    _VlcControl(
                      icon: Icons.tune_rounded,
                      label: 'Options',
                      onPressed: onOptions,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              if (controller != null)
                ValueListenableBuilder<VlcPlayerValue>(
                  valueListenable: controller!,
                  builder: (context, value, child) {
                    final progress = value.duration.inMilliseconds == 0
                        ? 0.0
                        : (value.position.inMilliseconds /
                                  value.duration.inMilliseconds)
                              .clamp(0.0, 1.0);
                    return Column(
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          color: AppColors.accentBright,
                          backgroundColor: Colors.white.withValues(alpha: .22),
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Text(
                              '${_formatDuration(value.position)}  /  '
                              '${_formatDuration(value.duration)}',
                            ),
                            if (!compact) ...[
                              const Spacer(),
                              const Text(
                                'VLC renderer  |  J/L seek  |  C decoder',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngineBadge extends StatelessWidget {
  const _EngineBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: .4)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.accentBright,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _VlcControl extends StatelessWidget {
  const _VlcControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        color: primary ? AppColors.accent : const Color(0x8F242429),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VlcPlaybackError extends StatelessWidget {
  const _VlcPlaybackError({
    required this.message,
    required this.onRetry,
    required this.onNextStream,
    required this.onUseMpv,
    required this.onChooseStream,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onNextStream;
  final VoidCallback onUseMpv;
  final VoidCallback onChooseStream;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xF20A0A0A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppColors.accentBright),
          SizedBox(
            width: 300,
            child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
          _VlcControl(
            icon: Icons.refresh_rounded,
            label: 'Retry VLC',
            primary: true,
            onPressed: onRetry,
          ),
          _VlcControl(
            icon: Icons.skip_next_rounded,
            label: 'Next stream',
            onPressed: onNextStream,
          ),
          _VlcControl(
            icon: Icons.swap_horiz_rounded,
            label: 'Use MPV',
            onPressed: onUseMpv,
          ),
          _VlcControl(
            icon: Icons.list_rounded,
            label: 'Choose stream',
            onPressed: onChooseStream,
          ),
        ],
      ),
    );
  }
}

class _VlcOptionsDialog extends StatelessWidget {
  const _VlcOptionsDialog({
    required this.mode,
    required this.playbackRate,
    required this.subtitleSize,
    required this.subtitleDelayMs,
    required this.audioDelayMs,
    required this.hasAlternateStreams,
    required this.hasDirectSources,
  });

  final VlcDecoderMode mode;
  final double playbackRate;
  final double subtitleSize;
  final int subtitleDelayMs;
  final int audioDelayMs;
  final bool hasAlternateStreams;
  final bool hasDirectSources;

  void _close(BuildContext context, String type, Object value) {
    Navigator.of(context).pop<_VlcMenuResult>((type: type, value: value));
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(
      String label,
      String type,
      Object value, {
      bool selected = false,
      IconData? icon,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: TvFocusable(
          autofocus: selected,
          onPressed: () => _close(context, type, value),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : const Color(0xFF1B1B1B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.accentBright : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget section(String title, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(children: children),
      ],
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 850),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF080808),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: .65),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Playback engine',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                section('DECODER', [
                  for (final decoder in VlcDecoderMode.values)
                    chip(
                      vlcDecoderLabel(decoder),
                      'decoder',
                      decoder,
                      selected: decoder == mode,
                    ),
                  chip(
                    'Restart stream',
                    'retry',
                    true,
                    icon: Icons.refresh_rounded,
                  ),
                  if (hasAlternateStreams)
                    chip(
                      'Try next stream',
                      'nextStream',
                      true,
                      icon: Icons.swap_horiz_rounded,
                    ),
                  if (hasDirectSources)
                    chip(
                      'Sources & quality',
                      'sources',
                      true,
                      icon: Icons.video_library_rounded,
                    ),
                  chip(
                    'Use MPV advanced',
                    'mpv',
                    true,
                    icon: Icons.video_settings_rounded,
                  ),
                ]),
                const SizedBox(height: 8),
                section('SPEED', [
                  for (final rate in const [.75, 1.0, 1.25, 1.5, 2.0])
                    chip(
                      '${rate}x',
                      'rate',
                      rate,
                      selected: playbackRate == rate,
                    ),
                ]),
                const SizedBox(height: 8),
                section('SUBTITLE SIZE', [
                  for (final size in const [28.0, 34.0, 42.0, 50.0])
                    chip(
                      switch (size) {
                        28 => 'Small',
                        34 => 'Medium',
                        42 => 'Large',
                        _ => 'Extra large',
                      },
                      'subtitleSize',
                      size,
                      selected: subtitleSize == size,
                    ),
                ]),
                const SizedBox(height: 8),
                section('SUBTITLE DELAY', [
                  for (final delay in const [-1000, -500, 0, 500, 1000])
                    chip(
                      '${delay}ms',
                      'subtitleDelay',
                      delay,
                      selected: subtitleDelayMs == delay,
                    ),
                ]),
                const SizedBox(height: 8),
                section('AUDIO DELAY', [
                  for (final delay in const [-500, -250, 0, 250, 500])
                    chip(
                      '${delay}ms',
                      'audioDelay',
                      delay,
                      selected: audioDelayMs == delay,
                    ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VlcNextEpisodeDialog extends StatefulWidget {
  const _VlcNextEpisodeDialog();

  @override
  State<_VlcNextEpisodeDialog> createState() => _VlcNextEpisodeDialogState();
}

class _VlcNextEpisodeDialogState extends State<_VlcNextEpisodeDialog> {
  int _seconds = 8;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_seconds <= 1) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF090909),
      title: const Text('Episode complete'),
      content: Text('Playing the next episode in $_seconds seconds.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Stay here'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Play next'),
        ),
      ],
    );
  }
}

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
