import 'dart:async';

import 'package:anime_tv/features/streaming/data/torbox_client.dart';
import 'package:anime_tv/features/streaming/data/torbox_models.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

class TorBoxStreamResolver implements StreamResolver {
  TorBoxStreamResolver(
    this._client,
    this._releaseSource, {
    this.pollInterval = const Duration(seconds: 2),
    this.timeout = const Duration(minutes: 30),
  });

  final TorBoxClient _client;
  final ReleaseSource _releaseSource;
  final Duration pollInterval;
  final Duration timeout;

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    final releases = await _releaseSource.search(episode);
    if (releases.isEmpty) {
      throw StateError('No releases found for episode ${episode.episode}.');
    }
    final release = releases.first;
    final torrentId = await _client.createTorrent(release.magnetUri);
    final deadline = DateTime.now().add(timeout);
    TorBoxTorrent? torrent;

    while (DateTime.now().isBefore(deadline)) {
      torrent = await _client.torrentInfo(torrentId);
      if (torrent.hasFailed) {
        throw StateError('TorBox torrent failed: ${torrent.downloadState}.');
      }
      if (torrent.isReady) break;
      yield StreamCaching(torrentId: '$torrentId', progress: torrent.progress);
      await Future<void>.delayed(pollInterval);
    }

    if (torrent == null || !torrent.isReady) {
      throw TimeoutException(
        'TorBox did not finish the torrent before the timeout.',
        timeout,
      );
    }
    final file = selectTorBoxEpisodeFile(
      torrent.files,
      episode.episode,
      preferredFileIndex: release.preferredFileIndex,
    );
    final uri = await _client.requestDownloadLink(
      torrentId: torrentId,
      fileId: file.id,
    );
    yield StreamReady(
      uri: uri,
      displayName: file.name,
      debridService: DebridService.torBox,
    );
  }
}

TorBoxFile selectTorBoxEpisodeFile(
  List<TorBoxFile> files,
  int episode, {
  int? preferredFileIndex,
}) {
  final playable = files.where((file) => file.isPlayable).toList();
  if (playable.isEmpty) {
    throw StateError('The TorBox torrent contains no supported video files.');
  }
  if (preferredFileIndex != null &&
      preferredFileIndex >= 0 &&
      preferredFileIndex < files.length &&
      files[preferredFileIndex].isPlayable) {
    return files[preferredFileIndex];
  }
  if (playable.length == 1) return playable.single;

  final episodeNumber = episode.toString().padLeft(2, '0');
  final patterns = [
    RegExp('(?:^|[^0-9])E$episodeNumber(?:[^0-9]|\\\$)', caseSensitive: false),
    RegExp(
      '(?:^|[^0-9])EP?\\s*0*$episode(?:[^0-9]|\\\$)',
      caseSensitive: false,
    ),
    RegExp('(?:^|[^0-9])0*$episode(?:[^0-9]|\\\$)'),
  ];
  for (final pattern in patterns) {
    final matches = playable.where((file) => pattern.hasMatch(file.name));
    if (matches.isNotEmpty) {
      return matches.reduce((a, b) => a.size >= b.size ? a : b);
    }
  }
  return playable.reduce((a, b) => a.size >= b.size ? a : b);
}
