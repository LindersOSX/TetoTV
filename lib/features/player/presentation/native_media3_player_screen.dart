import 'dart:async';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/player/presentation/player_control_overlay.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/streaming/application/debrid_token_service.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_stream_resolver.dart';
import 'package:anime_tv/features/streaming/data/torbox_client.dart';
import 'package:anime_tv/features/streaming/data/torbox_stream_resolver.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/application/tracking_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Orchestrates TetoTV's dedicated native Android player.
///
/// The actual video never enters a Flutter texture. Android Media3 owns a
/// SurfaceView in a separate full-screen activity; this Flutter screen only
/// supplies the debrid URL, restores/saves progress, and handles engine or
/// stream fallback after the native activity returns.
class NativeMedia3PlayerScreen extends ConsumerStatefulWidget {
  const NativeMedia3PlayerScreen({
    required this.source,
    required this.title,
    required this.debridService,
    required this.launch,
    required this.onUseMpv,
    required this.onUseVlc,
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
  final void Function(String source, ReleaseCandidate release) onUseMpv;
  final void Function(String source, ReleaseCandidate release) onUseVlc;

  @override
  ConsumerState<NativeMedia3PlayerScreen> createState() =>
      _NativeMedia3PlayerScreenState();
}

class _NativeMedia3PlayerScreenState
    extends ConsumerState<NativeMedia3PlayerScreen> {
  late String _source;
  late ReleaseCandidate _release;
  SeriesPlaybackPreferences _preferences = const SeriesPlaybackPreferences();
  Duration _resumePosition = Duration.zero;
  DateTime? _resumeUpdatedAt;
  int _alternativeIndex = 0;
  int _automaticStreamAttempts = 0;
  bool _startFromBeginning = false;
  bool _syncHandled = false;
  bool _running = false;
  String _status = 'Opening the native TV player…';
  String? _diagnostic;

  int get _mediaId =>
      widget.anilistMediaId ?? widget.launch.episode.anilistMediaId;
  int get _episodeNumber => widget.episode ?? widget.launch.episode.episode;
  int? get _malMediaId => widget.malMediaId ?? widget.launch.episode.malMediaId;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _release = widget.launch.selectedRelease;
    _startFromBeginning = widget.launch.episode.startFromBeginning;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_running || !mounted) return;
    _running = true;
    try {
      await _loadResumeAndPreferences();
      if (!mounted) return;
      final appearance = ref.read(settingsPreferencesProvider);
      // Media3 intentionally owns the fast hardware-decoding path. Preserve
      // the user's compatibility choice and send known Hi10P or delay-tuned
      // streams straight to MPV, which can software-decode and apply A/V delay.
      if (_preferences.decoder == 'software' ||
          releaseRequiresSoftwareDecoder(_release) ||
          _preferences.subtitleDelayMs != 0 ||
          _preferences.audioDelayMs != 0) {
        if (mounted) widget.onUseMpv(_source, _release);
        return;
      }
      while (mounted) {
        setState(() {
          _status = _automaticStreamAttempts == 0
              ? 'Opening the native TV player…'
              : 'Opening a more compatible stream…';
          _diagnostic = null;
        });
        final result = await AndroidTvBridge.instance.startNativePlayer(
          source: Uri.parse(_source),
          title: widget.title,
          checkpointKey: '$_mediaId:$_episodeNumber',
          releaseName: _release.releaseName,
          resumePosition: _resumePosition,
          resumeUpdatedAt: _resumeUpdatedAt,
          startFromBeginning: _startFromBeginning,
          externalSubtitle:
              widget.launch.stream.externalSubtitle?.toString() ??
              widget.subtitle,
          headers: widget.launch.stream.headers,
          audioLanguage: _preferences.audioLanguage,
          subtitleLanguage: _preferences.subtitleLanguage,
          subtitlesEnabled: _preferences.subtitlePreferenceSet
              ? _preferences.subtitleEnabled
              : subtitlesEnabledByDefault(_release),
          subtitleSize: _preferences.subtitleSize == 34
              ? appearance.captionTextSize
              : _preferences.subtitleSize,
          subtitlePosition: _preferences.subtitlePosition,
          highContrastSubtitles: _preferences.highContrastSubtitles,
          subtitleTextColor: appearance.captionTextColor,
          subtitleBackgroundColor: appearance.captionBackgroundColor,
          seekBackSeconds: appearance.seekBackSeconds,
          seekForwardSeconds: appearance.seekForwardSeconds,
          autoSkipIntros: appearance.autoSkipIntros,
          autoSkipOutros: appearance.autoSkipOutros,
          videoFit: _preferences.videoFit,
          malMediaId: _malMediaId,
          episodeNumber: _episodeNumber,
        );
        if (!mounted) return;
        _startFromBeginning = false;
        _resumePosition = result.position < Duration.zero
            ? Duration.zero
            : result.position;
        _resumeUpdatedAt = DateTime.now();
        await _persistResult(result);
        if (result.firstFrameRendered) {
          final profile = await AndroidTvBridge.instance.getDeviceProfile();
          await ref
              .read(tetoTvDatabaseProvider)
              .recordPlayerSuccess(profile.key, 'media3');
        }
        if (!mounted) return;

        switch (result.status) {
          case 'completed':
          case 'ended':
            await _syncProgress();
            if (!mounted) return;
            await _offerNextEpisode();
            return;
          case 'retry':
            continue;
          case 'next_stream':
            if (await _switchToCompatibleStream('Requested by the player')) {
              continue;
            }
            if (mounted) widget.onUseMpv(_source, _release);
            return;
          case 'use_vlc':
          case 'fallback_vlc':
            if (mounted) widget.onUseVlc(_source, _release);
            return;
          case 'use_mpv':
          case 'fallback_mpv':
            if (mounted) widget.onUseMpv(_source, _release);
            return;
          case 'error':
          case 'no_first_frame':
            await _recordFailure(result);
            if (!mounted) return;
            if (await _switchToCompatibleStream(
              result.error ?? 'Media3 could not render this stream',
            )) {
              continue;
            }
            // MPV keeps libass and unusual-codec support as the second engine.
            // VLC remains available manually from MPV or on a future retry.
            if (mounted) widget.onUseMpv(_source, _release);
            return;
          case 'unsupported':
            if (mounted) widget.onUseMpv(_source, _release);
            return;
          case 'exit':
          case 'cancelled':
          default:
            if (context.canPop()) context.pop();
            return;
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'The native player could not be opened';
        _diagnostic = error.toString();
      });
    } finally {
      _running = false;
    }
  }

  Future<void> _retryAfterFailure() async {
    if (mounted) setState(() => _diagnostic = null);
    await _run();
  }

  Future<void> _nextStreamAfterFailure() async {
    final switched = await _switchToCompatibleStream(
      _diagnostic ?? 'Selected after playback failure',
    );
    if (switched) await _run();
  }

  Future<void> _loadResumeAndPreferences() async {
    if (!mounted) return;
    final database = ref.read(tetoTvDatabaseProvider);
    _preferences = await database.seriesPreferences(_mediaId);
    if (!mounted || _startFromBeginning) return;
    final checkpoint = await database.checkpoint(_mediaId, _episodeNumber);
    if (!mounted) return;
    if (checkpoint != null) {
      // Even a completed or intentionally reset checkpoint is authoritative:
      // its timestamp acts as a zero-position tombstone so an older native
      // crash checkpoint cannot resurrect already-cleared progress.
      _resumeUpdatedAt = checkpoint.updatedAt;
      _resumePosition =
          !checkpoint.completed &&
              checkpoint.position > const Duration(seconds: 15) &&
              checkpoint.progress < .95
          ? checkpoint.position
          : Duration.zero;
    }
  }

  Future<void> _persistResult(NativePlaybackResult result) async {
    if (!mounted) return;
    final database = ref.read(tetoTvDatabaseProvider);
    final normalizedSize = result.subtitleSize?.clamp(18, 60).toDouble();
    final audioLanguage = result.audioLanguage == null
        ? null
        : canonicalPlayerLanguage(result.audioLanguage);
    final subtitleLanguage = result.subtitleLanguage == null
        ? null
        : canonicalPlayerLanguage(result.subtitleLanguage);
    var nextPreferences = _preferences;
    if (normalizedSize != null) {
      nextPreferences = nextPreferences.copyWith(subtitleSize: normalizedSize);
    }
    if (audioLanguage != null && audioLanguage.isNotEmpty) {
      nextPreferences = nextPreferences.copyWith(audioLanguage: audioLanguage);
    }
    if (subtitleLanguage != null && subtitleLanguage.isNotEmpty) {
      nextPreferences = nextPreferences.copyWith(
        subtitleLanguage: subtitleLanguage,
      );
    }
    if (result.subtitlesEnabled case final enabled?) {
      nextPreferences = nextPreferences.copyWith(
        subtitleEnabled: enabled,
        subtitlePreferenceSet: true,
      );
    }
    if (nextPreferences.toJson().toString() !=
        _preferences.toJson().toString()) {
      _preferences = nextPreferences;
      await database.saveSeriesPreferences(_mediaId, _preferences);
    }
    if (result.duration <= Duration.zero) {
      return;
    }
    final duration = result.duration;
    final position = result.position < Duration.zero
        ? Duration.zero
        : result.position > duration
        ? duration
        : result.position;
    final completed =
        result.completed ||
        position.inMilliseconds / duration.inMilliseconds >= .93;
    await database.saveCheckpoint(
      PlaybackCheckpoint(
        anilistMediaId: _mediaId,
        malMediaId: _malMediaId,
        episode: _episodeNumber,
        title: widget.launch.episode.title,
        coverImageUrl: widget.coverImageUrl,
        position: completed ? duration : position,
        duration: duration,
        updatedAt: DateTime.now(),
        completed: completed,
      ),
    );
    if (completed) {
      await AndroidTvBridge.instance.removeWatchNext(_mediaId);
    }
    if (!mounted) return;
    ref.invalidate(recentPlaybackProvider);
    if (!completed && position > const Duration(seconds: 30)) {
      await AndroidTvBridge.instance.publishWatchNext(
        mediaId: _mediaId,
        episode: _episodeNumber,
        title: widget.launch.episode.title,
        posterUrl: widget.coverImageUrl,
        position: position,
        duration: duration,
      );
    }
    if (completed) await _syncProgress();
  }

  Future<void> _recordFailure(NativePlaybackResult result) async {
    try {
      if (!mounted) return;
      final database = ref.read(tetoTvDatabaseProvider);
      final infoHash = _release.infoHash;
      final profile = await AndroidTvBridge.instance.getDeviceProfile();
      final details = <String>[
        result.error ?? 'Native playback failed',
        if (result.decoder?.isNotEmpty == true) 'decoder=${result.decoder}',
        'firstFrame=${result.firstFrameRendered}',
        'droppedFrames=${result.droppedFrames}',
        for (final entry in result.diagnostics.entries)
          '${entry.key}=${entry.value}',
      ].join('; ');
      await database.recordStreamFailure(
        deviceKey: profile.key,
        infoHash: infoHash,
        reason: details,
      );
      await database.recordPlayerFailure(profile.key, 'media3');
      await database.recordDiagnosticEvent(
        category: 'player-media3',
        message: details,
      );
    } catch (_) {
      // Failure history improves future ranking but must never block fallback.
    }
  }

  Future<bool> _switchToCompatibleStream(String reason) async {
    if (_automaticStreamAttempts >= 2) return false;
    while (_alternativeIndex < widget.launch.alternatives.length) {
      final candidate = widget.launch.alternatives[_alternativeIndex++];
      // Do not burn CPU on H.264 Hi10P during automatic Fire TV recovery.
      // MPV software mode remains available when the user explicitly wants it.
      if (releaseRequiresSoftwareDecoder(candidate)) continue;
      if (mounted) {
        setState(() {
          _status = 'Resolving a more compatible debrid stream…';
          _diagnostic = reason;
        });
      }
      final ready = await _resolveRelease(candidate);
      if (!mounted) return false;
      if (ready == null) continue;
      _source = ready.uri.toString();
      _release = candidate;
      _automaticStreamAttempts++;
      return true;
    }
    return false;
  }

  Future<StreamReady?> _resolveRelease(ReleaseCandidate release) async {
    if (!mounted) return null;
    final tokenService = ref.read(debridTokenServiceProvider);
    final debridService = widget.debridService;
    final episode = widget.launch.episode;
    final token = await tokenService.accessToken(debridService);
    if (!mounted) return null;
    if (token == null || token.isEmpty) return null;
    final source = SingleReleaseSource(release);
    final resolver = switch (debridService) {
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
      if (!mounted) return null;
      if (resolution is StreamReady) return resolution;
    }
    return null;
  }

  Future<void> _syncProgress() async {
    if (_syncHandled || !mounted) return;
    _syncHandled = true;
    final syncService = ref.read(trackingSyncServiceProvider);
    final completedEpisodes = _episodeNumber;
    final anilistMediaId = _mediaId;
    final malMediaId = _malMediaId;
    try {
      await syncService.syncEpisode(
        completedEpisodes: completedEpisodes,
        anilistMediaId: anilistMediaId,
        malMediaId: malMediaId,
      );
      if (mounted) ref.invalidate(trackingHomeProvider);
    } catch (_) {
      // The tracking service queues/retries independently of video playback.
    }
  }

  Future<void> _offerNextEpisode() async {
    if (!mounted) return;
    final playNext = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _NativeNextEpisodeDialog(),
    );
    if (!mounted) return;
    if (playNext == true) {
      await _playNextEpisode();
    } else if (context.canPop()) {
      context.pop();
    }
  }

  Future<void> _playNextEpisode() async {
    try {
      if (!mounted) return;
      final catalog = ref.read(catalogClientProvider);
      final details = await catalog.details(_mediaId);
      final nextEpisode = _episodeNumber + 1;
      if (details.episodes != null && nextEpisode > details.episodes!) {
        if (mounted && context.canPop()) context.pop();
        return;
      }
      if (!mounted) return;
      context.pushReplacement(
        Uri(
          path: '/resolve',
          queryParameters: {
            'anilistId': _mediaId.toString(),
            'title': details.title,
            'synonyms': details.synonyms.join('|'),
            'episode': nextEpisode.toString(),
            'autoplay': '1',
            if (details.coverImageUrl != null) 'cover': details.coverImageUrl!,
            if (_malMediaId != null) 'malId': _malMediaId.toString(),
          },
        ).toString(),
      );
    } catch (_) {
      if (mounted && context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_diagnostic == null)
                  const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      color: Color(0xFFE63B55),
                      strokeWidth: 4,
                    ),
                  )
                else
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFFF929B),
                    size: 46,
                  ),
                const SizedBox(height: 22),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_diagnostic != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _diagnostic!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF9B9BA5)),
                  ),
                ],
                const SizedBox(height: 24),
                if (_diagnostic != null) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        autofocus: true,
                        onPressed: _retryAfterFailure,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry stream'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _nextStreamAfterFailure,
                        icon: const Icon(Icons.skip_next_rounded),
                        label: const Text('Try another stream'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (context.canPop()) context.pop();
                        },
                        icon: const Icon(Icons.list_rounded),
                        label: const Text('Choose stream'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton(
                  onPressed: () => widget.onUseMpv(_source, _release),
                  child: const Text('Use MPV compatibility player'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => widget.onUseVlc(_source, _release),
                  child: const Text('Use VLC software player'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _NativeNextEpisodeDialog extends StatefulWidget {
  const _NativeNextEpisodeDialog();

  @override
  State<_NativeNextEpisodeDialog> createState() =>
      _NativeNextEpisodeDialogState();
}

class _NativeNextEpisodeDialogState extends State<_NativeNextEpisodeDialog> {
  Timer? _timer;
  int _seconds = 8;

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
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF0B0B0D),
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
        child: const Text('Play now'),
      ),
    ],
  );
}
