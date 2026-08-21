import 'dart:async';

import 'package:flutter/foundation.dart';

typedef LibraryPlaybackProgressCallback =
    FutureOr<void> Function(LibraryPlaybackProgress progress);
typedef LibraryPlaybackStartedCallback =
    FutureOr<void> Function(Duration position);
typedef LibraryPlaybackFinishedCallback =
    FutureOr<void> Function(LibraryPlaybackResult result);

/// The anime-only effects which are deliberately unavailable to library media.
///
/// This is a fixed policy, not a caller preference. Plex, Jellyfin, and local
/// files do not have a trustworthy AniList episode identity, so treating one as
/// an anime launch could update an unrelated tracker entry or home checkpoint.
@immutable
class LibraryPlaybackIsolationPolicy {
  const LibraryPlaybackIsolationPolicy._();

  static const isolated = LibraryPlaybackIsolationPolicy._();

  bool get animeTrackingEnabled => false;
  bool get animeCheckpointEnabled => false;
  bool get aniSkipEnabled => false;
  bool get fillerNavigationEnabled => false;
  bool get nextEpisodeEnabled => false;
}

/// A capability kept entirely inside the app's playback route.
///
/// [source], [headers], and [timelineIdentity] are never copied into Watch
/// Together state. The party layer receives only a one-way timeline digest.
/// Progress callbacks are best effort and serialized by the player session.
@immutable
class LibraryPlaybackRequest {
  LibraryPlaybackRequest({
    required this.source,
    required String title,
    required String releaseName,
    required String streamLabel,
    required String checkpointKey,
    required String timelineIdentity,
    Map<String, String> headers = const {},
    this.artworkUrl,
    this.externalSubtitle,
    this.mediaContentType,
    this.subtitleContentType,
    this.initialPosition = Duration.zero,
    this.onStarted,
    this.onProgress,
    this.onFinished,
    this.watchPartyDisplayTitle = 'Private media',
  }) : title = _requiredLabel(title, 'title'),
       releaseName = _requiredLabel(releaseName, 'releaseName'),
       streamLabel = _requiredLabel(streamLabel, 'streamLabel'),
       checkpointKey = _requiredLabel(checkpointKey, 'checkpointKey'),
       timelineIdentity = _requiredLabel(timelineIdentity, 'timelineIdentity'),
       headers = Map.unmodifiable(headers) {
    if (!isSupportedLibraryPlaybackUri(source)) {
      throw ArgumentError.value(
        source,
        'source',
        'Library playback accepts only HTTP(S) or Android content URIs.',
      );
    }
  }

  final Uri source;
  final String title;
  final String releaseName;
  final String streamLabel;
  final String checkpointKey;

  /// Stable local preimage used only to calculate a party timeline digest.
  /// This may be an already-hashed local checkpoint ID or a media-server item
  /// identity. It never leaves the playback coordinator.
  final String timelineIdentity;
  final Map<String, String> headers;
  final String? artworkUrl;
  final String? externalSubtitle;
  final String? mediaContentType;
  final String? subtitleContentType;
  final Duration initialPosition;
  final LibraryPlaybackStartedCallback? onStarted;
  final LibraryPlaybackProgressCallback? onProgress;
  final LibraryPlaybackFinishedCallback? onFinished;

  /// The only private-media label eligible to enter room state. Callers must
  /// opt in to sharing a real title; local filenames stay private by default.
  final String watchPartyDisplayTitle;

  LibraryPlaybackIsolationPolicy get isolation =>
      LibraryPlaybackIsolationPolicy.isolated;

  bool get isContentUri => source.scheme.toLowerCase() == 'content';

  /// Android document-provider URIs and authenticated server streams are
  /// intentionally Media3-only.
  ///
  /// Native Media3 scopes request headers to the original server and strips
  /// them on cross-origin redirects. The Flutter VLC/MPV transports cannot
  /// currently prove that boundary, so only header-free HTTP(S) media may
  /// move among engines.
  bool get allowsFlutterEngines => !isContentUri && headers.isEmpty;
}

@immutable
class LibraryPlaybackProgress {
  const LibraryPlaybackProgress({
    required this.position,
    required this.duration,
    required this.playing,
    required this.sampledAt,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final DateTime sampledAt;

  double get fraction => duration <= Duration.zero
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
}

enum LibraryPlaybackEndReason { completed, exited, failed }

@immutable
class LibraryPlaybackResult {
  const LibraryPlaybackResult({
    required this.position,
    required this.duration,
    required this.reason,
    required this.started,
    this.error,
  });

  final Duration position;
  final Duration duration;
  final LibraryPlaybackEndReason reason;
  final bool started;
  final String? error;

  bool get completed => reason == LibraryPlaybackEndReason.completed;
  bool get failed => reason == LibraryPlaybackEndReason.failed;
}

bool isSupportedLibraryPlaybackUri(Uri source) {
  final scheme = source.scheme.toLowerCase();
  if (!const {'http', 'https', 'content'}.contains(scheme) ||
      source.userInfo.isNotEmpty ||
      source.hasFragment) {
    return false;
  }
  if (scheme == 'content') {
    return source.hasAuthority && source.authority.trim().isNotEmpty;
  }
  return source.hasAuthority && source.host.trim().isNotEmpty;
}

String _requiredLabel(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, name, 'is empty');
  return normalized;
}
