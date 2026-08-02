import 'dart:async';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/config/app_config.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/player/application/audio_track_selector.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_stream_resolver.dart';
import 'package:anime_tv/features/streaming/data/torbox_client.dart';
import 'package:anime_tv/features/streaming/data/torbox_stream_resolver.dart';
import 'package:anime_tv/features/streaming/data/composite_release_source.dart';
import 'package:anime_tv/features/streaming/data/hosted_release_source.dart';
import 'package:anime_tv/features/streaming/data/torrentio_release_source.dart';
import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_sync_service.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

const tetoTvVideoControllerConfiguration = VideoControllerConfiguration(
  enableHardwareAcceleration: true,
  // Copy decoded MediaCodec frames through libmpv's GPU renderer. This avoids
  // the zero-copy Android Surface path that produces green lines/corrupted
  // frames on a number of Fire TV and budget Android TV chipsets, while still
  // retaining hardware decoding for demanding HEVC/10-bit streams.
  vo: 'gpu',
  hwdec: 'mediacodec-copy',
  androidAttachSurfaceAfterVideoParameters: true,
);

enum PlaybackDecoderMode { hardwareSafe, hardwareDirect, software }

typedef _PlaybackMenuResult = ({String type, Object value});

String hwdecForPlaybackMode(PlaybackDecoderMode mode) => switch (mode) {
  PlaybackDecoderMode.hardwareSafe => 'mediacodec-copy',
  PlaybackDecoderMode.hardwareDirect => 'mediacodec',
  PlaybackDecoderMode.software => 'no',
};

String playbackDecoderLabel(PlaybackDecoderMode mode) => switch (mode) {
  PlaybackDecoderMode.hardwareSafe => 'Hardware safe',
  PlaybackDecoderMode.hardwareDirect => 'Hardware direct',
  PlaybackDecoderMode.software => 'Software compatibility',
};

bool isLikelyVideoDecodeFailure(String message) {
  final value = message.toLowerCase();
  return const [
    'mediacodec',
    'video decoder',
    'video codec',
    'failed to decode',
    'hardware decoding',
    'video output',
    'surface',
  ].any(value.contains);
}

Duration? playerSeekOffsetForKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.mediaRewind) {
    return const Duration(seconds: -10);
  }
  if (key == LogicalKeyboardKey.keyL ||
      key == LogicalKeyboardKey.mediaFastForward) {
    return const Duration(seconds: 10);
  }
  return null;
}

String _formatPlayerDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${value.inMinutes}:$seconds';
}

class TvPlayerScreen extends ConsumerStatefulWidget {
  const TvPlayerScreen({
    required this.source,
    required this.title,
    required this.debridService,
    required this.launch,
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
  final String? subtitle;
  final int? anilistMediaId;
  final int? malMediaId;
  final int? episode;
  final String? coverImageUrl;

  @override
  ConsumerState<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends ConsumerState<TvPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final _playerRootFocus = FocusNode(debugLabel: 'player.root');
  final _playControlFocus = FocusNode(debugLabel: 'player.play');
  Timer? _controlsTimer;
  Timer? _videoWatchdog;
  StreamSubscription<Duration>? _progressSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _controlsVisible = true;
  bool _progressHandled = false;
  bool _preferredAudioSelected = false;
  bool _preferredSubtitleSelected = false;
  String? _trackMessage;
  String? _playbackError;
  StreamSubscription<void>? _completedSubscription;
  List<Map<String, dynamic>> _skips = [];
  bool _canSkipNow = false;
  StreamSubscription<VideoParams>? _videoParamsSubscription;
  bool _videoFrameSeen = false;
  bool _softwareFallbackUsed = false;
  bool _changingDecoder = false;
  int _watchdogAttempts = 0;
  PlaybackDecoderMode _decoderMode = PlaybackDecoderMode.hardwareSafe;
  BoxFit _videoFit = BoxFit.contain;
  double _playbackRate = 1;
  double _subtitleSize = 34;
  int _subtitlePosition = 100;
  int _subtitleDelayMs = 0;
  int _audioDelayMs = 0;
  bool _highContrastSubtitles = false;
  late String _source;
  late ReleaseCandidate _currentRelease;
  int _alternativeIndex = 0;
  bool _failingOver = false;
  bool _prewarming = false;
  bool _prewarmed = false;
  DateTime _lastCheckpointSave = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMediaSessionUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<MediaAction>? _mediaActionSubscription;
  SeriesPlaybackPreferences _seriesPreferences =
      const SeriesPlaybackPreferences();
  Uint8List? _seekPreview;
  Duration? _seekPreviewPosition;
  Timer? _seekPreviewTimer;

  Future<void> _bootstrapPlayback() async {
    Duration? resume;
    if (widget.anilistMediaId case final mediaId?) {
      final database = ref.read(tetoTvDatabaseProvider);
      _seriesPreferences = await database.seriesPreferences(mediaId);
      _decoderMode = switch (_seriesPreferences.decoder) {
        'hardware-direct' => PlaybackDecoderMode.hardwareDirect,
        'software' => PlaybackDecoderMode.software,
        _ => PlaybackDecoderMode.hardwareSafe,
      };
      _videoFit = switch (_seriesPreferences.videoFit) {
        'cover' => BoxFit.cover,
        'fill' => BoxFit.fill,
        _ => BoxFit.contain,
      };
      _subtitleSize = _seriesPreferences.subtitleSize;
      _subtitlePosition = _seriesPreferences.subtitlePosition;
      _subtitleDelayMs = _seriesPreferences.subtitleDelayMs;
      _audioDelayMs = _seriesPreferences.audioDelayMs;
      _highContrastSubtitles = _seriesPreferences.highContrastSubtitles;
      if (!widget.launch.episode.startFromBeginning && widget.episode != null) {
        final checkpoint = await database.checkpoint(mediaId, widget.episode!);
        if (checkpoint != null &&
            !checkpoint.completed &&
            checkpoint.position > const Duration(seconds: 15) &&
            checkpoint.progress < .95) {
          resume = checkpoint.position;
        }
      }
    }
    if (!mounted) return;
    await _openMedia(resume: resume);
    if (resume != null) {
      _showTrackMessage('Resumed at ${_formatPlayerDuration(resume)}');
    }
  }

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _currentRelease = widget.launch.selectedRelease;
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'TetoTV',
        // Real-Debrid/TorBox are seekable HTTP sources; a 48 MiB cache keeps
        // playback smooth without starving low-memory Fire TV devices.
        bufferSize: 48 * 1024 * 1024,
        libass: true,
        libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf',
        libassAndroidFontName: 'Noto Sans',
      ),
    );
    _controller = VideoController(
      _player,
      configuration: tetoTvVideoControllerConfiguration,
    );
    _progressSubscription = _player.stream.position.listen(_onPosition);
    _tracksSubscription = _player.stream.tracks.listen(_selectPreferredTracks);
    _errorSubscription = _player.stream.error.listen((message) {
      if (isLikelyVideoDecodeFailure(message) && !_softwareFallbackUsed) {
        unawaited(_restartWithSoftwareDecoder());
        return;
      }
      if (widget.launch.alternatives.isNotEmpty) {
        unawaited(_tryNextStream(message));
        return;
      }
      if (mounted) setState(() => _playbackError = message);
    });
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (completed) _offerNextEpisode();
    });
    _videoParamsSubscription = _player.stream.videoParams.listen((params) {
      if (params.w == null || params.h == null) return;
      _videoFrameSeen = true;
      _videoWatchdog?.cancel();
      debugPrint('\n--- PLAYBACK DIAGNOSTICS ---');
      debugPrint('Resolution: ${params.w}x${params.h}');
      debugPrint('Pixel format: ${params.pixelformat ?? "unknown"}');
      debugPrint('Hardware Pixel format: ${params.hwPixelformat ?? "unknown"}');
      debugPrint('Color matrix: ${params.colormatrix ?? "unknown"}');
      debugPrint('Color levels (range): ${params.colorlevels ?? "unknown"}');
      debugPrint('Primaries (HDR/SDR): ${params.primaries ?? "unknown"}');
      debugPrint('Gamma: ${params.gamma ?? "unknown"}');
      debugPrint(
        'Video Codec: ${_player.state.track.video.codec ?? "unknown"}',
      );
      debugPrint(
        'Audio Codec: ${_player.state.track.audio.codec ?? "unknown"}',
      );
      debugPrint('Player/Backend: media_kit (libmpv)');
      debugPrint('VO/hwdec: gpu / ${hwdecForPlaybackMode(_decoderMode)}');
      debugPrint('----------------------------\n');
      unawaited(_matchContentFrameRate());
    });
    _playingSubscription = _player.stream.playing.listen((_) {
      unawaited(_updateMediaSession(force: true));
    });
    _mediaActionSubscription = AndroidTvBridge.instance.mediaActions.listen(
      _handleMediaAction,
    );
    unawaited(
      _controller.waitUntilFirstFrameRendered.then((_) {
        _videoFrameSeen = true;
        _videoWatchdog?.cancel();
      }),
    );
    unawaited(_bootstrapPlayback());
    _fetchSkips();
    _scheduleControlsHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playControlFocus.requestFocus();
    });
  }

  Future<void> _preferDubAudio(Tracks tracks) async {
    if (_preferredAudioSelected) return;
    final language = _seriesPreferences.audioLanguage.toLowerCase();
    final device = await AndroidTvBridge.instance.getDeviceProfile();
    final preferred =
        tracks.audio.where((track) {
          final haystack = '${track.language} ${track.title}'.toLowerCase();
          return haystack.contains(language) ||
              (language == 'eng' &&
                  (haystack.contains('english') || haystack.contains('dub')));
        }).firstOrNull ??
        preferredDubAudioTrack(
          tracks.audio,
          preferSurround: device.hasHdmiAudio,
        );
    if (preferred == null) return;
    _preferredAudioSelected = true;
    await _player.setAudioTrack(preferred);
    _showTrackMessage(
      'Dub audio: '
      '${preferred.title ?? preferred.language ?? 'English'}',
    );
  }

  Future<void> _selectPreferredTracks(Tracks tracks) async {
    await _preferDubAudio(tracks);
    if (_preferredSubtitleSelected || !_seriesPreferences.subtitleEnabled) {
      return;
    }
    final language = _seriesPreferences.subtitleLanguage.toLowerCase();
    final preferred = tracks.subtitle.where((track) {
      if (track.id == 'auto' || track.id == 'no') return false;
      final haystack = '${track.language} ${track.title}'.toLowerCase();
      return haystack.contains(language) ||
          (language == 'eng' && haystack.contains('english'));
    }).firstOrNull;
    if (preferred == null) return;
    _preferredSubtitleSelected = true;
    await _player.setSubtitleTrack(preferred);
  }

  void _onPosition(Duration position) {
    _checkSkips(position);
    unawaited(_persistPlayback(position));
    unawaited(_updateMediaSession());
    if (_progressHandled || widget.episode == null) return;
    if (widget.anilistMediaId == null && widget.malMediaId == null) return;
    final duration = _player.state.duration;
    if (duration.inSeconds <= 0) return;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    if (!_prewarmed && !_prewarming && ratio >= .65) {
      unawaited(_prewarmNextEpisode());
    }
    if (ratio < .9) return;
    _progressHandled = true;
    unawaited(_syncProgress());
  }

  void _checkSkips(Duration position) {
    if (_skips.isEmpty) return;
    final posSec = position.inMilliseconds / 1000.0;
    bool canSkip = false;
    for (final skip in _skips) {
      final start = skip['interval']['startTime'];
      final end = skip['interval']['endTime'];
      if (posSec >= start && posSec < end) {
        canSkip = true;
        break;
      }
    }
    if (_canSkipNow != canSkip) {
      setState(() => _canSkipNow = canSkip);
      if (canSkip) _showControls();
    }
  }

  Future<void> _fetchSkips() async {
    if (widget.malMediaId == null || widget.episode == null) return;
    try {
      final res = await Dio().get(
        'https://api.aniskip.com/v2/skip-times/${widget.malMediaId}/${widget.episode}?types=op,ed,mixed-op,mixed-ed',
      );
      if (res.data['found'] == true) {
        if (mounted) {
          setState(() {
            _skips = List<Map<String, dynamic>>.from(res.data['results']);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _playNextEpisode() async {
    if (widget.anilistMediaId == null || widget.episode == null) return;
    try {
      final details = await ref
          .read(catalogClientProvider)
          .details(widget.anilistMediaId!);
      final nextEp = widget.episode! + 1;
      if (details.episodes != null && nextEp > details.episodes!) {
        return; // No more episodes
      }
      if (!mounted) return;
      final query = {
        'anilistId': widget.anilistMediaId.toString(),
        'title': details.title,
        'synonyms': details.synonyms.join('|'),
        'episode': nextEp.toString(),
        if (details.coverImageUrl != null) 'cover': details.coverImageUrl!,
        if (widget.malMediaId != null) 'malId': widget.malMediaId.toString(),
      };
      context.pushReplacement(
        Uri(path: '/resolve', queryParameters: query).toString(),
      );
    } catch (_) {}
  }

  Future<void> _syncProgress() async {
    try {
      await ref
          .read(trackingSyncServiceProvider)
          .syncEpisode(
            completedEpisodes: widget.episode!,
            anilistMediaId: widget.anilistMediaId,
            malMediaId: widget.malMediaId,
          );
      ref.invalidate(trackingHomeProvider);
      _showTrackMessage('Episode progress saved');
    } catch (_) {
      _showTrackMessage('Progress will retry when the tracker reconnects');
    }
  }

  Future<void> _openMedia({Duration? resume}) async {
    try {
      await _configureNativePlayback();
      await _player.open(
        Media(
          _source,
          httpHeaders: const {
            'Accept': '*/*',
            'User-Agent': 'TetoTV/1.5 AndroidTV libmpv',
          },
        ),
        play: true,
      );
      await _applySubtitle();
      if (resume != null) await _player.seek(resume);
      _startVideoWatchdog();
    } catch (error) {
      if (mounted) setState(() => _playbackError = error.toString());
    }
  }

  Future<void> _configureNativePlayback() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final properties = <String, String>{
      'hwdec': hwdecForPlaybackMode(_decoderMode),
      'hwdec-software-fallback': 'yes',
      'demuxer-lavf-probesize': '67108864',
      'demuxer-lavf-analyzeduration': '10',
      'network-timeout': '20',
      'cache': 'yes',
      'cache-pause-initial': 'yes',
      'cache-pause-wait': '1',
      'video-sync': 'audio',
      'sub-pos': '$_subtitlePosition',
      'sub-delay': '${_subtitleDelayMs / 1000}',
      'audio-delay': '${_audioDelayMs / 1000}',
      'sub-border-size': _highContrastSubtitles ? '4' : '2.5',
      'sub-back-color': _highContrastSubtitles ? '#88000000' : '#00000000',
    };
    for (final property in properties.entries) {
      try {
        await platform.setProperty(property.key, property.value);
      } catch (_) {
        // libmpv builds vary slightly; unsupported tuning must not block play.
      }
    }
  }

  Future<void> _applyPlayerTuning() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final properties = <String, String>{
      'sub-scale': '${_subtitleSize / 34}',
      'sub-pos': '$_subtitlePosition',
      'sub-delay': '${_subtitleDelayMs / 1000}',
      'audio-delay': '${_audioDelayMs / 1000}',
      'sub-border-size': _highContrastSubtitles ? '4' : '2.5',
      'sub-back-color': _highContrastSubtitles ? '#88000000' : '#00000000',
    };
    for (final property in properties.entries) {
      try {
        await platform.setProperty(property.key, property.value);
      } catch (_) {
        // Keep playback alive on mpv builds missing an optional property.
      }
    }
  }

  Future<void> _applySubtitle() async {
    final subtitle = widget.subtitle;
    if (subtitle != null && subtitle.isNotEmpty) {
      if (subtitle.startsWith('asset:///')) {
        final assetKey = subtitle.substring('asset:///'.length);
        final data = await rootBundle.loadString(assetKey);
        await _player.setSubtitleTrack(
          SubtitleTrack.data(data, title: 'Bundled styled subtitles'),
        );
      } else {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(subtitle, title: 'External subtitles'),
        );
      }
    }
  }

  Future<void> _persistPlayback(Duration position, {bool force = false}) async {
    final mediaId = widget.anilistMediaId;
    final episode = widget.episode;
    if (mediaId == null || episode == null) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastCheckpointSave) < const Duration(seconds: 10)) {
      return;
    }
    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
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
    if (force) ref.invalidate(recentPlaybackProvider);
    if (!completed && position > const Duration(seconds: 30)) {
      await AndroidTvBridge.instance.publishWatchNext(
        mediaId: mediaId,
        episode: episode,
        title: widget.launch.episode.title,
        posterUrl: widget.coverImageUrl,
        position: position,
        duration: duration,
      );
    }
  }

  Future<void> _updateMediaSession({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastMediaSessionUpdate) < const Duration(seconds: 5)) {
      return;
    }
    _lastMediaSessionUpdate = now;
    await AndroidTvBridge.instance.updateMediaSession(
      title: widget.launch.episode.title,
      episode: widget.episode ?? 1,
      position: _player.state.position,
      duration: _player.state.duration,
      playing: _player.state.playing,
    );
  }

  void _handleMediaAction(MediaAction action) {
    switch (action.action) {
      case 'play':
        unawaited(_player.play());
      case 'pause':
        unawaited(_player.pause());
      case 'seekTo':
        unawaited(_player.seek(Duration(milliseconds: action.value ?? 0)));
      case 'seekBy':
        unawaited(_seekBy(Duration(milliseconds: action.value ?? 0)));
      case 'next':
        unawaited(_playNextEpisode());
      case 'previous':
        unawaited(_seekBy(-_player.state.position));
    }
  }

  Future<void> _matchContentFrameRate() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    for (final property in const ['container-fps', 'estimated-vf-fps']) {
      try {
        final value = await platform.getProperty(property);
        final fps = double.tryParse(value);
        if (fps != null && fps >= 20 && fps <= 120) {
          await AndroidTvBridge.instance.setPreferredFrameRate(fps);
          return;
        }
      } catch (_) {
        // Try the next libmpv property.
      }
    }
  }

  Future<StreamReady?> _resolveRelease(
    ReleaseCandidate release,
    EpisodeReference episode,
  ) async {
    final token = await ref
        .read(secureStorageProvider)
        .read(key: widget.debridService.tokenStorageKey);
    if (token == null || token.isEmpty) return null;
    final source = SingleReleaseSource(release);
    final resolver = switch (widget.debridService) {
      DebridService.realDebrid => RealDebridStreamResolver(
        RealDebridClient(token: token),
        source,
      ),
      DebridService.torBox => TorBoxStreamResolver(
        TorBoxClient(token: token),
        source,
      ),
    };
    await for (final resolution in resolver.resolve(episode)) {
      if (resolution is StreamReady) return resolution;
    }
    return null;
  }

  Future<void> _tryNextStream(String reason) async {
    if (_failingOver ||
        _alternativeIndex >= widget.launch.alternatives.length) {
      if (mounted) setState(() => _playbackError = reason);
      return;
    }
    _failingOver = true;
    final position = _player.state.position;
    try {
      final profile = await AndroidTvBridge.instance.getDeviceProfile();
      await ref
          .read(tetoTvDatabaseProvider)
          .recordStreamFailure(
            deviceKey: profile.key,
            infoHash: _currentRelease.infoHash,
            reason: reason,
          );
      while (_alternativeIndex < widget.launch.alternatives.length) {
        final candidate = widget.launch.alternatives[_alternativeIndex++];
        _showTrackMessage('Trying another compatible stream…');
        try {
          final ready = await _resolveRelease(candidate, widget.launch.episode);
          if (ready == null) continue;
          _source = ready.uri.toString();
          _currentRelease = candidate;
          _preferredAudioSelected = false;
          _preferredSubtitleSelected = false;
          _softwareFallbackUsed = false;
          _decoderMode = PlaybackDecoderMode.hardwareSafe;
          _videoFrameSeen = false;
          await _openMedia(resume: position);
          if (mounted) setState(() => _playbackError = null);
          _showTrackMessage('Switched to a compatible stream');
          return;
        } catch (_) {
          // Continue through the ranked debrid-only candidates.
        }
      }
      if (mounted) {
        setState(
          () =>
              _playbackError = 'Every compatible debrid stream failed. $reason',
        );
      }
    } finally {
      _failingOver = false;
    }
  }

  Future<void> _prewarmNextEpisode() async {
    if (_prewarming || _prewarmed || widget.episode == null) return;
    _prewarming = true;
    try {
      final sources = <ReleaseSource>[
        if (AppConfig.hasStremioAddon)
          TorrentioReleaseSource(
            manifestUrl: AppConfig.stremioAddonManifestUrl,
          ),
        if (AppConfig.hasReleaseResolver)
          HostedReleaseSource(baseUrl: AppConfig.releaseResolverBaseUrl),
      ];
      if (sources.isEmpty) return;
      final next = EpisodeReference(
        anilistMediaId: widget.launch.episode.anilistMediaId,
        malMediaId: widget.launch.episode.malMediaId,
        title: widget.launch.episode.title,
        alternativeTitles: widget.launch.episode.alternativeTitles,
        coverImageUrl: widget.launch.episode.coverImageUrl,
        episode: widget.episode! + 1,
      );
      final releases = await CompositeReleaseSource(sources).search(next);
      if (releases.isEmpty) return;
      releases.sort((a, b) {
        final dub = (b.isDubbed ? 1 : 0).compareTo(a.isDubbed ? 1 : 0);
        if (dub != 0) return dub;
        return b.seeders.compareTo(a.seeders);
      });
      await _resolveRelease(releases.first, next);
      _prewarmed = true;
    } catch (_) {
      // Prewarming is intentionally invisible and never blocks playback.
    } finally {
      _prewarming = false;
    }
  }

  Future<void> _saveSeriesPreferences() async {
    final mediaId = widget.anilistMediaId;
    if (mediaId == null) return;
    final audio = _player.state.track.audio;
    final subtitle = _player.state.track.subtitle;
    _seriesPreferences = SeriesPlaybackPreferences(
      audioLanguage: audio.language ?? _seriesPreferences.audioLanguage,
      subtitleLanguage:
          subtitle.language ?? _seriesPreferences.subtitleLanguage,
      subtitleEnabled: subtitle.id != 'no',
      subtitleSize: _subtitleSize,
      subtitlePosition: _subtitlePosition,
      subtitleDelayMs: _subtitleDelayMs,
      audioDelayMs: _audioDelayMs,
      decoder: switch (_decoderMode) {
        PlaybackDecoderMode.hardwareDirect => 'hardware-direct',
        PlaybackDecoderMode.software => 'software',
        _ => 'hardware-safe',
      },
      videoFit: switch (_videoFit) {
        BoxFit.cover => 'cover',
        BoxFit.fill => 'fill',
        _ => 'contain',
      },
      highContrastSubtitles: _highContrastSubtitles,
    );
    await ref
        .read(tetoTvDatabaseProvider)
        .saveSeriesPreferences(mediaId, _seriesPreferences);
  }

  Future<void> _offerNextEpisode() async {
    if (!mounted || widget.episode == null || widget.anilistMediaId == null) {
      return;
    }
    unawaited(_persistPlayback(_player.state.duration, force: true));
    final play = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _NextEpisodeDialog(seconds: 8),
    );
    if (play == true) await _playNextEpisode();
  }

  void _startVideoWatchdog() {
    _videoWatchdog?.cancel();
    _watchdogAttempts = 0;
    _scheduleVideoWatchdogCheck();
  }

  void _scheduleVideoWatchdogCheck() {
    _videoWatchdog = Timer(const Duration(seconds: 8), () {
      if (!mounted || _videoFrameSeen || _changingDecoder) {
        return;
      }
      _watchdogAttempts++;
      if ((_player.state.buffering ||
              _player.state.position < const Duration(seconds: 2)) &&
          _watchdogAttempts < 4) {
        _scheduleVideoWatchdogCheck();
        return;
      }
      if (_softwareFallbackUsed) {
        unawaited(_tryNextStream('No video frames were rendered.'));
      } else {
        unawaited(_restartWithSoftwareDecoder());
      }
    });
  }

  Future<void> _restartWithSoftwareDecoder() =>
      _switchDecoder(PlaybackDecoderMode.software, automatic: true);

  Future<void> _switchDecoder(
    PlaybackDecoderMode mode, {
    bool automatic = false,
  }) async {
    if (_changingDecoder || mode == _decoderMode) return;
    _changingDecoder = true;
    _decoderMode = mode;
    _softwareFallbackUsed = mode == PlaybackDecoderMode.software;
    _videoWatchdog?.cancel();
    final position = _player.state.position;
    final wasPlaying = _player.state.playing;
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('hwdec', hwdecForPlaybackMode(mode));
        await platform.setProperty('hwdec-software-fallback', 'yes');
      }
      _preferredAudioSelected = false;
      _preferredSubtitleSelected = false;
      _videoFrameSeen = false;
      await _player.open(
        Media(
          _source,
          httpHeaders: const {
            'Accept': '*/*',
            'User-Agent': 'TetoTV/1.5 AndroidTV libmpv',
          },
        ),
        play: automatic || wasPlaying,
      );
      if (position > Duration.zero) await _player.seek(position);
      await _applySubtitle();
      await _applyPlayerTuning();
      if (mounted) {
        setState(() => _playbackError = null);
        _showTrackMessage(
          automatic
              ? 'Video failed to start; software compatibility enabled'
              : '${playbackDecoderLabel(mode)} enabled',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _playbackError = error.toString());
    } finally {
      _changingDecoder = false;
    }
  }

  Future<void> _retryPlayback() async {
    final position = _player.state.position;
    final wasPlaying = _player.state.playing;
    setState(() => _playbackError = null);
    try {
      await _configureNativePlayback();
      await _player.open(
        Media(
          _source,
          httpHeaders: const {
            'Accept': '*/*',
            'User-Agent': 'TetoTV/1.5 AndroidTV libmpv',
          },
        ),
        play: wasPlaying,
      );
      if (position > Duration.zero) await _player.seek(position);
      await _applySubtitle();
      await _applyPlayerTuning();
      _startVideoWatchdog();
      _showTrackMessage('Stream restarted');
    } catch (error) {
      if (mounted) setState(() => _playbackError = error.toString());
    }
  }

  Future<void> _openPlaybackMenu() async {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = true);
    final result = await showDialog<_PlaybackMenuResult>(
      context: context,
      barrierColor: const Color(0xD9000000),
      builder: (context) => _PlaybackOptionsDialog(
        decoderMode: _decoderMode,
        videoFit: _videoFit,
        playbackRate: _playbackRate,
        subtitleSize: _subtitleSize,
        subtitlePosition: _subtitlePosition,
        subtitleDelayMs: _subtitleDelayMs,
        audioDelayMs: _audioDelayMs,
        highContrastSubtitles: _highContrastSubtitles,
        hasAlternateStreams:
            _alternativeIndex < widget.launch.alternatives.length,
      ),
    );
    if (!mounted) return;
    if (result == null) {
      _scheduleControlsHide();
      return;
    }
    switch (result.type) {
      case 'decoder':
        await _switchDecoder(result.value as PlaybackDecoderMode);
      case 'fit':
        setState(() => _videoFit = result.value as BoxFit);
        _showTrackMessage(_fitLabel(_videoFit));
      case 'rate':
        final rate = result.value as double;
        await _player.setRate(rate);
        setState(() => _playbackRate = rate);
        _showTrackMessage('Playback speed ${rate}x');
      case 'subtitleSize':
        setState(() => _subtitleSize = result.value as double);
        _showTrackMessage('Subtitle size ${_subtitleSize.round()}');
      case 'subtitlePosition':
        setState(() => _subtitlePosition = result.value as int);
        _showTrackMessage('Subtitle position $_subtitlePosition%');
      case 'subtitleDelay':
        setState(() => _subtitleDelayMs = result.value as int);
        _showTrackMessage('Subtitle delay ${_subtitleDelayMs}ms');
      case 'audioDelay':
        setState(() => _audioDelayMs = result.value as int);
        _showTrackMessage('Audio delay ${_audioDelayMs}ms');
      case 'contrast':
        setState(() => _highContrastSubtitles = result.value as bool);
        _showTrackMessage(
          _highContrastSubtitles
              ? 'High contrast subtitles on'
              : 'High contrast subtitles off',
        );
      case 'nextStream':
        await _tryNextStream('Stream changed manually.');
      case 'retry':
        await _retryPlayback();
    }
    await _applyPlayerTuning();
    await _saveSeriesPreferences();
    _scheduleControlsHide();
  }

  void _cycleFit() {
    final next = switch (_videoFit) {
      BoxFit.contain => BoxFit.cover,
      BoxFit.cover => BoxFit.fill,
      _ => BoxFit.contain,
    };
    setState(() => _videoFit = next);
    unawaited(_saveSeriesPreferences());
    _showTrackMessage(_fitLabel(next));
  }

  static String _fitLabel(BoxFit fit) => switch (fit) {
    BoxFit.cover => 'Picture: Fill screen',
    BoxFit.fill => 'Picture: Stretch',
    _ => 'Picture: Fit',
  };

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final directionalKey =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final controlsWereHidden = !_controlsVisible;
    _showControls(focusControls: controlsWereHidden && directionalKey);
    if (!node.hasPrimaryFocus &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    if (node.hasPrimaryFocus && directionalKey) {
      _showControls(focusControls: true);
      return KeyEventResult.handled;
    }
    if (playerSeekOffsetForKey(key) case final offset?) {
      _seekBy(offset);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.keyK) {
      _player.playOrPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      _cycleSubtitles();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI && _canSkipNow) {
      _skipCurrentSegment();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM ||
        key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.gameButtonY) {
      unawaited(_openPlaybackMenu());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      if (_softwareFallbackUsed) {
        _showTrackMessage('Compatibility decoder is already enabled');
      } else {
        unawaited(_restartWithSoftwareDecoder());
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.gameButtonX) {
      _cycleFit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _seekBy(Duration offset) async {
    final duration = _player.state.duration;
    final candidate = _player.state.position + offset;
    final target = candidate < Duration.zero
        ? Duration.zero
        : candidate > duration
        ? duration
        : candidate;
    await _player.seek(target);
    unawaited(_captureTrickplay(target));
  }

  Future<void> _captureTrickplay(Duration target) async {
    try {
      final bytes = await _player.screenshot(format: 'image/jpeg');
      if (!mounted || bytes == null || bytes.isEmpty) return;
      _seekPreviewTimer?.cancel();
      setState(() {
        _seekPreview = bytes;
        _seekPreviewPosition = target;
      });
      _seekPreviewTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _seekPreview = null);
      });
    } catch (_) {
      // Some protected video surfaces do not permit screenshots.
    }
  }

  Future<void> _cycleAudio() async {
    final tracks = _player.state.tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
    if (tracks.isEmpty) {
      _showTrackMessage('No alternate audio tracks');
      return;
    }
    final currentId = _player.state.track.audio.id;
    final currentIndex = tracks.indexWhere((track) => track.id == currentId);
    final next = tracks[(currentIndex + 1) % tracks.length];
    await _player.setAudioTrack(next);
    unawaited(_saveSeriesPreferences());
    _showTrackMessage(
      'Audio: ${next.title ?? next.language ?? 'Track ${next.id}'}',
    );
  }

  void _skipCurrentSegment() {
    final posSec = _player.state.position.inMilliseconds / 1000.0;
    for (final skip in _skips) {
      final interval = skip['interval'];
      if (interval is! Map) continue;
      final start = interval['startTime'];
      final end = interval['endTime'];
      if (start is num && end is num && posSec >= start && posSec < end) {
        _player.seek(Duration(milliseconds: (end * 1000).toInt()));
        _showTrackMessage('Skipped intro/credits');
        return;
      }
    }
  }

  Future<void> _cycleSubtitles() async {
    final embedded = _player.state.tracks.subtitle
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
    final tracks = <SubtitleTrack>[SubtitleTrack.no(), ...embedded];
    final currentId = _player.state.track.subtitle.id;
    final currentIndex = tracks.indexWhere((track) => track.id == currentId);
    final next = tracks[(currentIndex + 1) % tracks.length];
    await _player.setSubtitleTrack(next);
    unawaited(_saveSeriesPreferences());
    _showTrackMessage(
      next.id == 'no'
          ? 'Subtitles: Off'
          : 'Subtitles: ${next.title ?? next.language ?? 'Track ${next.id}'}',
    );
  }

  void _showTrackMessage(String message) {
    if (!mounted) return;
    setState(() => _trackMessage = message);
    Timer(const Duration(seconds: 2), () {
      if (mounted && _trackMessage == message) {
        setState(() => _trackMessage = null);
      }
    });
  }

  void _showControls({bool focusControls = false}) {
    if (mounted) setState(() => _controlsVisible = true);
    if (focusControls) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playControlFocus.requestFocus();
      });
    }
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _player.state.playing) {
        setState(() => _controlsVisible = false);
        _playerRootFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_persistPlayback(_player.state.position, force: true));
    unawaited(_saveSeriesPreferences());
    unawaited(AndroidTvBridge.instance.clearPreferredFrameRate());
    _controlsTimer?.cancel();
    _videoWatchdog?.cancel();
    _seekPreviewTimer?.cancel();
    _progressSubscription?.cancel();
    _tracksSubscription?.cancel();
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _playingSubscription?.cancel();
    _mediaActionSubscription?.cancel();
    _playerRootFocus.dispose();
    _playControlFocus.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _playerRootFocus,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _controller,
              controls: NoVideoControls,
              fit: _videoFit,
              subtitleViewConfiguration: SubtitleViewConfiguration(
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _subtitleSize,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 5,
                      offset: Offset(2, 2),
                    ),
                  ],
                  backgroundColor: _highContrastSubtitles
                      ? const Color(0xAA000000)
                      : Colors.transparent,
                ),
              ),
            ),
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              initialData: _player.state.buffering,
              builder: (context, snapshot) {
                if (snapshot.data != true) return const SizedBox.shrink();
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.cyan),
                );
              },
            ),
            ExcludeFocus(
              excluding: !_controlsVisible,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _PlayerChrome(
                    player: _player,
                    title: widget.title,
                    debridService: widget.debridService,
                    decoderMode: _decoderMode,
                    playFocusNode: _playControlFocus,
                    onRewind: () => _seekBy(const Duration(seconds: -10)),
                    onPlayPause: _player.playOrPause,
                    onForward: () => _seekBy(const Duration(seconds: 10)),
                    canSkip: _canSkipNow,
                    onSkip: _skipCurrentSegment,
                    onAudio: _cycleAudio,
                    onSubtitles: _cycleSubtitles,
                    onFit: _cycleFit,
                    onOptions: _openPlaybackMenu,
                  ),
                ),
              ),
            ),
            if (_playbackError case final error?)
              Positioned(
                left: 34,
                right: 34,
                bottom: 110,
                child: _PlaybackError(message: error),
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
                  ),
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            if (_seekPreview case final preview?)
              Positioned(
                left: 0,
                right: 0,
                bottom: 116,
                child: Center(
                  child: Container(
                    width: 210,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accentBright),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.memory(
                            preview,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatPlayerDuration(
                            _seekPreviewPosition ?? Duration.zero,
                          ),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerChrome extends StatelessWidget {
  const _PlayerChrome({
    required this.player,
    required this.title,
    required this.debridService,
    required this.decoderMode,
    required this.playFocusNode,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.canSkip,
    required this.onSkip,
    required this.onAudio,
    required this.onSubtitles,
    required this.onFit,
    required this.onOptions,
  });

  final Player player;
  final String title;
  final DebridService debridService;
  final PlaybackDecoderMode decoderMode;
  final FocusNode playFocusNode;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final bool canSkip;
  final VoidCallback onSkip;
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;
  final VoidCallback onFit;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xAA000000), Colors.transparent, Color(0xCC000000)],
          stops: [0, .38, 1],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${debridService.displayName} stream',
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                _PlayerControl(
                  icon: Icons.replay_10_rounded,
                  label: 'Back 10s',
                  onPressed: onRewind,
                ),
                const SizedBox(width: 8),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: player.state.playing,
                  builder: (context, snapshot) => _PlayerControl(
                    focusNode: playFocusNode,
                    primary: true,
                    icon: snapshot.data == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    label: snapshot.data == true ? 'Pause' : 'Play',
                    onPressed: onPlayPause,
                  ),
                ),
                const SizedBox(width: 8),
                _PlayerControl(
                  icon: Icons.forward_10_rounded,
                  label: 'Forward 10s',
                  onPressed: onForward,
                ),
                if (canSkip) ...[
                  const SizedBox(width: 8),
                  _PlayerControl(
                    icon: Icons.skip_next_rounded,
                    label: 'Skip intro',
                    primary: true,
                    onPressed: onSkip,
                  ),
                ],
                const SizedBox(width: 18),
                _PlayerControl(
                  icon: Icons.audiotrack_rounded,
                  label: 'Audio',
                  onPressed: onAudio,
                ),
                const SizedBox(width: 8),
                _PlayerControl(
                  icon: Icons.subtitles_rounded,
                  label: 'Subtitles',
                  onPressed: onSubtitles,
                ),
                const SizedBox(width: 8),
                _PlayerControl(
                  icon: Icons.aspect_ratio_rounded,
                  label: 'Picture',
                  onPressed: onFit,
                ),
                const Spacer(),
                _PlayerControl(
                  icon: Icons.tune_rounded,
                  label: playbackDecoderLabel(decoderMode),
                  onPressed: onOptions,
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<Duration>(
              stream: player.stream.position,
              initialData: player.state.position,
              builder: (context, positionSnapshot) {
                return StreamBuilder<Duration>(
                  stream: player.stream.duration,
                  initialData: player.state.duration,
                  builder: (context, durationSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    final duration = durationSnapshot.data ?? Duration.zero;
                    final progress = duration.inMilliseconds == 0
                        ? 0.0
                        : (position.inMilliseconds / duration.inMilliseconds)
                              .clamp(0.0, 1.0);
                    return Column(
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: .24),
                          color: AppColors.accentBright,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              '${_format(position)}  /  ${_format(duration)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const Spacer(),
                            Text(
                              'D-pad controls   •   J/L seek   •   '
                              'Menu/Y options   •   C compatibility',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _format(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _PlayerControl extends StatelessWidget {
  const _PlayerControl({
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
        color: primary ? AppColors.accent : const Color(0xDD161616),
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

class _PlaybackOptionsDialog extends StatelessWidget {
  const _PlaybackOptionsDialog({
    required this.decoderMode,
    required this.videoFit,
    required this.playbackRate,
    required this.subtitleSize,
    required this.subtitlePosition,
    required this.subtitleDelayMs,
    required this.audioDelayMs,
    required this.highContrastSubtitles,
    required this.hasAlternateStreams,
  });

  final PlaybackDecoderMode decoderMode;
  final BoxFit videoFit;
  final double playbackRate;
  final double subtitleSize;
  final int subtitlePosition;
  final int subtitleDelayMs;
  final int audioDelayMs;
  final bool highContrastSubtitles;
  final bool hasAlternateStreams;

  void _close(BuildContext context, String type, Object value) {
    Navigator.of(context).pop<_PlaybackMenuResult>((type: type, value: value));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 900,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withValues(alpha: .55)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, color: AppColors.accentBright),
                const SizedBox(width: 9),
                Text(
                  'Playback options',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                const Text(
                  'Changes apply immediately',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _OptionSection(
              title: 'DECODER',
              children: [
                for (final mode in PlaybackDecoderMode.values)
                  _OptionChip(
                    label: playbackDecoderLabel(mode),
                    selected: decoderMode == mode,
                    autofocus: decoderMode == mode,
                    onPressed: () => _close(context, 'decoder', mode),
                  ),
                _OptionChip(
                  label: 'Restart stream',
                  icon: Icons.refresh_rounded,
                  onPressed: () => _close(context, 'retry', true),
                ),
                if (hasAlternateStreams)
                  _OptionChip(
                    label: 'Try next stream',
                    icon: Icons.swap_horiz_rounded,
                    onPressed: () => _close(context, 'nextStream', true),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _OptionSection(
              title: 'PICTURE',
              children: [
                _OptionChip(
                  label: 'Fit',
                  selected: videoFit == BoxFit.contain,
                  onPressed: () => _close(context, 'fit', BoxFit.contain),
                ),
                _OptionChip(
                  label: 'Fill screen',
                  selected: videoFit == BoxFit.cover,
                  onPressed: () => _close(context, 'fit', BoxFit.cover),
                ),
                _OptionChip(
                  label: 'Stretch',
                  selected: videoFit == BoxFit.fill,
                  onPressed: () => _close(context, 'fit', BoxFit.fill),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _OptionSection(
              title: 'SPEED',
              children: [
                for (final rate in const [.75, 1.0, 1.25, 1.5, 2.0])
                  _OptionChip(
                    label: '${rate}x',
                    selected: playbackRate == rate,
                    onPressed: () => _close(context, 'rate', rate),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _OptionSection(
              title: 'SUBTITLE SIZE',
              children: [
                for (final size in const [28.0, 34.0, 42.0, 50.0])
                  _OptionChip(
                    label: switch (size) {
                      28 => 'Small',
                      34 => 'Medium',
                      42 => 'Large',
                      _ => 'Extra large',
                    },
                    selected: subtitleSize == size,
                    onPressed: () => _close(context, 'subtitleSize', size),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _OptionSection(
              title: 'SUBTITLE STYLE',
              children: [
                for (final position in const [78, 90, 100])
                  _OptionChip(
                    label: switch (position) {
                      78 => 'Higher',
                      90 => 'Raised',
                      _ => 'Bottom',
                    },
                    selected: subtitlePosition == position,
                    onPressed: () =>
                        _close(context, 'subtitlePosition', position),
                  ),
                _OptionChip(
                  label: highContrastSubtitles
                      ? 'High contrast on'
                      : 'High contrast off',
                  selected: highContrastSubtitles,
                  onPressed: () =>
                      _close(context, 'contrast', !highContrastSubtitles),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _OptionSection(
              title: 'SYNC',
              children: [
                for (final delay in const [-500, -250, 0, 250, 500])
                  _OptionChip(
                    label: 'Subs ${delay > 0 ? '+' : ''}${delay}ms',
                    selected: subtitleDelayMs == delay,
                    onPressed: () => _close(context, 'subtitleDelay', delay),
                  ),
                for (final delay in const [-250, 0, 250])
                  _OptionChip(
                    label: 'Audio ${delay > 0 ? '+' : ''}${delay}ms',
                    selected: audioDelayMs == delay,
                    onPressed: () => _close(context, 'audioDelay', delay),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionSection extends StatelessWidget {
  const _OptionSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Expanded(child: Wrap(spacing: 7, runSpacing: 7, children: children)),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool selected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed,
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        color: selected ? AppColors.accent : const Color(0xFF1B1B1B),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final value?) ...[
              Icon(value, size: 16),
              const SizedBox(width: 6),
            ],
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

class _NextEpisodeDialog extends StatefulWidget {
  const _NextEpisodeDialog({required this.seconds});

  final int seconds;

  @override
  State<_NextEpisodeDialog> createState() => _NextEpisodeDialogState();
}

class _NextEpisodeDialogState extends State<_NextEpisodeDialog> {
  Timer? _timer;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _remaining--);
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
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withValues(alpha: .6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.skip_next_rounded,
              color: AppColors.accentBright,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'Next episode in $_remaining',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _OptionChip(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 10),
                _OptionChip(
                  label: 'Play now',
                  icon: Icons.play_arrow_rounded,
                  selected: true,
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xEE391D29),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF929B)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFFF929B)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DebridOnlyPlaybackScreen extends StatelessWidget {
  const DebridOnlyPlaybackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 68, color: AppColors.cyan),
            SizedBox(height: 18),
            Text(
              'Playback blocked',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 10),
            SizedBox(
              width: 620,
              child: Text(
                'TetoTV only accepts streams resolved through a connected '
                'Real-Debrid or TorBox account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
