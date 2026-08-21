import 'dart:async';
import 'dart:convert';

import 'package:anime_tv/features/player/application/library_playback_session.dart';
import 'package:anime_tv/features/player/domain/library_playback_request.dart';
import 'package:anime_tv/features/player/presentation/tv_player_screen.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';

/// Full-screen playback for local files and private Plex/Jellyfin libraries.
///
/// This typed route deliberately does not accept an [EpisodeReference]. That
/// makes it impossible for library playback to write anime tracking progress,
/// AniList checkpoints, filler state, AniSkip requests, or next-episode state.
class LibraryTvPlayerScreen extends StatefulWidget {
  const LibraryTvPlayerScreen({required this.request, super.key});

  final LibraryPlaybackRequest request;

  @override
  State<LibraryTvPlayerScreen> createState() => _LibraryTvPlayerScreenState();
}

class _LibraryTvPlayerScreenState extends State<LibraryTvPlayerScreen> {
  late LibraryPlaybackSession _session;

  @override
  void initState() {
    super.initState();
    _session = LibraryPlaybackSession(widget.request);
  }

  @override
  void didUpdateWidget(covariant LibraryTvPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.request, widget.request)) return;
    unawaited(_session.finish());
    _session = LibraryPlaybackSession(widget.request);
  }

  @override
  void dispose() {
    unawaited(_session.finish());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final launch = libraryPlaybackLaunchForRequest(request);
    return TvPlayerScreen(
      key: ValueKey('library-player-${request.checkpointKey}'),
      source: request.source.toString(),
      title: request.title,
      // Library mode never invokes a debrid resolver. This value exists only
      // for the legacy anime-player constructor while the typed session is the
      // authoritative capability boundary.
      debridService: DebridService.realDebrid,
      launch: launch,
      subtitle: request.externalSubtitle,
      coverImageUrl: request.artworkUrl,
      libraryPlayback: _session,
    );
  }
}

@visibleForTesting
PlaybackLaunch libraryPlaybackLaunchForRequest(LibraryPlaybackRequest request) {
  final digest = sha256
      .convert(
        utf8.encode(
          'tetotv-library-launch-v1\u001f${request.timelineIdentity}',
        ),
      )
      .toString();
  final stream = StreamReady(
    uri: request.source,
    displayName: request.releaseName,
    headers: request.headers,
    externalSubtitle: request.externalSubtitle == null
        ? null
        : Uri.tryParse(request.externalSubtitle!),
    mediaContentType: request.mediaContentType,
    subtitleContentType: request.subtitleContentType,
    providerId: 'library',
    providerName: request.streamLabel,
  );
  return PlaybackLaunch(
    stream: stream,
    episode: EpisodeReference(
      anilistMediaId: 0,
      title: request.title,
      episode: 1,
      coverImageUrl: request.artworkUrl,
      startFromBeginning: true,
    ),
    selectedRelease: ReleaseCandidate(
      infoHash: digest,
      magnetUri: '',
      releaseName: request.releaseName,
      seeders: 0,
      sourceId: 'library',
      provider: request.streamLabel,
    ),
  );
}
