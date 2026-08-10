import 'dart:async';

import 'package:anime_tv/features/streaming/data/all_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/all_debrid_models.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

class AllDebridStreamResolver implements StreamResolver {
  AllDebridStreamResolver(
    this._client,
    this._releaseSource, {
    this.pollInterval = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 30),
  });

  final AllDebridClient _client;
  final ReleaseSource _releaseSource;
  final Duration pollInterval;
  final Duration timeout;

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    final releases = await _releaseSource.search(episode);
    if (releases.isEmpty) {
      throw StateError('No releases found for episode ${episode.episode}.');
    }
    final ranked = [...releases]
      ..sort((a, b) {
        if (a.isBatch != b.isBatch) return a.isBatch ? 1 : -1;
        return b.seeders.compareTo(a.seeders);
      });
    final release = ranked.first;
    final upload = await _client.uploadMagnet(release.magnetUri);
    var status = await _client.magnetStatus(upload.id);
    final deadline = DateTime.now().add(timeout);

    while (!status.isReady && DateTime.now().isBefore(deadline)) {
      if (status.hasFailed) {
        throw StateError('AllDebrid torrent failed: ${status.status}.');
      }
      yield StreamCaching(torrentId: '${upload.id}', progress: status.progress);
      await Future<void>.delayed(pollInterval);
      status = await _client.magnetStatus(upload.id);
    }
    if (!status.isReady) {
      throw TimeoutException(
        'AllDebrid did not finish the torrent before the timeout.',
        timeout,
      );
    }

    final files = await _client.magnetFiles(upload.id);
    final selected = selectAllDebridEpisodeFile(
      files,
      episode.episode,
      preferredFileIndex: release.preferredFileIndex,
    );
    final uri = await _client.unlock(selected.link);
    yield StreamReady(
      uri: uri,
      displayName: selected.name,
      debridService: DebridService.allDebrid,
    );
  }
}

AllDebridTorrentFile selectAllDebridEpisodeFile(
  List<AllDebridTorrentFile> files,
  int episode, {
  int? preferredFileIndex,
}) {
  final playable = files.where((file) => file.isPlayable).toList();
  if (playable.isEmpty) {
    throw StateError(
      'The AllDebrid torrent contains no supported video files.',
    );
  }
  if (preferredFileIndex != null &&
      preferredFileIndex >= 0 &&
      preferredFileIndex < files.length &&
      files[preferredFileIndex].isPlayable) {
    return files[preferredFileIndex];
  }
  if (playable.length == 1) return playable.single;

  final padded = episode.toString().padLeft(2, '0');
  final patterns = [
    RegExp('(?:^|[^0-9])E$padded(?:[^0-9]|\$)', caseSensitive: false),
    RegExp('(?:^|[^0-9])EP?\\s*0*$episode(?:[^0-9]|\$)', caseSensitive: false),
    RegExp('(?:^|[^0-9])0*$episode(?:[^0-9]|\$)'),
  ];
  for (final pattern in patterns) {
    final matches = playable.where((file) => pattern.hasMatch(file.name));
    if (matches.isNotEmpty) {
      return matches.reduce((a, b) => a.size >= b.size ? a : b);
    }
  }
  return playable.reduce((a, b) => a.size >= b.size ? a : b);
}
