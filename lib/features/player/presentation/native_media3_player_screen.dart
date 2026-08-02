import 'dart:async';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      await _loadResumeAndPreferences();
      // Media3 intentionally owns the fast hardware-decoding path. Preserve
      // the user's compatibility choice and send known Hi10P or delay-tuned
      // streams straight to MPV, which can software-decode and apply A/V delay.
      if (_preferences.decoder == 'software' ||
          releaseRequiresSoftwareDecoder(_release) ||
          _preferences.subtitleDelayMs != 0 ||
          _preferences.audioDelayMs != 0) {
        widget.onUseMpv(_source, _release);
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
          externalSubtitle: widget.subtitle,
          audioLanguage: _preferences.audioLanguage,
          subtitleLanguage: _preferences.subtitleLanguage,
          subtitlesEnabled: _preferences.subtitleEnabled,
          subtitleSize: _preferences.subtitleSize,
          subtitlePosition: _preferences.subtitlePosition,
          highContrastSubtitles: _preferences.highContrastSubtitles,
          videoFit: _preferences.videoFit,
        );
        if (!mounted) return;
        _startFromBeginning = false;
        _resumePosition = result.position < Duration.zero
            ? Duration.zero
            : result.position;
        _resumeUpdatedAt = DateTime.now();
        await _persistResult(result);
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
            widget.onUseMpv(_source, _release);
            return;
          case 'use_vlc':
          case 'fallback_vlc':
            widget.onUseVlc(_source, _release);
            return;
          case 'use_mpv':
          case 'fallback_mpv':
            widget.onUseMpv(_source, _release);
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
            widget.onUseMpv(_source, _release);
            return;
          case 'unsupported':
            widget.onUseMpv(_source, _release);
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

  Future<void> _loadResumeAndPreferences() async {
    final database = ref.read(tetoTvDatabaseProvider);
    _preferences = await database.seriesPreferences(_mediaId);
    if (_startFromBeginning) return;
    final checkpoint = await database.checkpoint(_mediaId, _episodeNumber);
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
    await ref
        .read(tetoTvDatabaseProvider)
        .saveCheckpoint(
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
      final profile = await AndroidTvBridge.instance.getDeviceProfile();
      final details = <String>[
        result.error ?? 'Native playback failed',
        if (result.decoder?.isNotEmpty == true) 'decoder=${result.decoder}',
        'firstFrame=${result.firstFrameRendered}',
        'droppedFrames=${result.droppedFrames}',
        for (final entry in result.diagnostics.entries)
          '${entry.key}=${entry.value}',
      ].join('; ');
      await ref
          .read(tetoTvDatabaseProvider)
          .recordStreamFailure(
            deviceKey: profile.key,
            infoHash: _release.infoHash,
            reason: details,
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
      if (ready == null) continue;
      _source = ready.uri.toString();
      _release = candidate;
      _automaticStreamAttempts++;
      return true;
    }
    return false;
  }

  Future<StreamReady?> _resolveRelease(ReleaseCandidate release) async {
    final token = await ref
        .read(debridTokenServiceProvider)
        .accessToken(widget.debridService);
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
    await for (final resolution in resolver.resolve(widget.launch.episode)) {
      if (resolution is StreamReady) return resolution;
    }
    return null;
  }

  Future<void> _syncProgress() async {
    if (_syncHandled) return;
    _syncHandled = true;
    try {
      await ref
          .read(trackingSyncServiceProvider)
          .syncEpisode(
            completedEpisodes: _episodeNumber,
            anilistMediaId: _mediaId,
            malMediaId: _malMediaId,
          );
      ref.invalidate(trackingHomeProvider);
    } catch (_) {
      // The tracking service queues/retries independently of video playback.
    }
  }

  Future<void> _offerNextEpisode() async {
    if (!mounted) return;
    final playNext = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B0B0D),
        title: const Text('Episode complete'),
        content: const Text('Play the next episode?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Play next'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back to show'),
          ),
        ],
      ),
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
      final details = await ref.read(catalogClientProvider).details(_mediaId);
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
                const SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    color: Color(0xFFE63B55),
                    strokeWidth: 4,
                  ),
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
