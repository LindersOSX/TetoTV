import 'dart:async';

import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

class RealDebridStreamResolver implements StreamResolver {
  RealDebridStreamResolver(
    this._client,
    this._releaseSource, {
    this.pollInterval = const Duration(seconds: 2),
    this.timeout = const Duration(minutes: 30),
  });

  final RealDebridClient _client;
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
        final singleEpisodeBias = a.isBatch == b.isBatch
            ? 0
            : a.isBatch
            ? 1
            : -1;
        return singleEpisodeBias != 0
            ? singleEpisodeBias
            : b.seeders.compareTo(a.seeders);
      });

    final selectedRelease = ranked.first;
    final torrentId = await _client.addMagnet(selectedRelease.magnetUri);
    var info = await _client.torrentInfo(torrentId);

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      info = await _client.torrentInfo(torrentId);
      if (info.needsFileSelection) {
        final file = selectEpisodeFile(
          info.files,
          episode.episode,
          preferredFileIndex: selectedRelease.preferredFileIndex,
        );
        await _client.selectFiles(torrentId, [file.id]);
        yield StreamCaching(torrentId: torrentId, progress: 0);
        await Future<void>.delayed(pollInterval);
        continue;
      }
      if (info.hasFailed) {
        throw RealDebridException(
          'This release could not be prepared by Real-Debrid. TetoTV can try '
          'a different release.',
          kind: RealDebridFailureKind.releaseUnavailable,
        );
      }
      if (info.isDownloaded) break;
      yield StreamCaching(
        torrentId: torrentId,
        progress: (info.progress / 100).clamp(0, 1),
      );
      await Future<void>.delayed(pollInterval);
    }

    if (!info.isDownloaded) {
      throw TimeoutException(
        'Real-Debrid did not finish the torrent before the timeout.',
        timeout,
      );
    }
    if (info.links.isEmpty) {
      throw StateError('Real-Debrid returned no downloadable video link.');
    }

    final link = selectEpisodeDownloadLink(
      info,
      episode.episode,
      preferredFileIndex: selectedRelease.preferredFileIndex,
    );
    final unrestricted = await _client.unrestrict(link);
    yield StreamReady(
      uri: unrestricted.download,
      displayName: unrestricted.filename,
      debridService: DebridService.realDebrid,
    );
  }
}

/// Maps the episode file selected from a downloaded batch to the matching
/// Real-Debrid link. The API returns links in the same order as selected
/// files, which is not necessarily the order of all files in the torrent.
String selectEpisodeDownloadLink(
  RealDebridTorrentInfo info,
  int episode, {
  int? preferredFileIndex,
}) {
  if (info.links.isEmpty) {
    throw StateError('Real-Debrid returned no downloadable video link.');
  }
  if (info.links.length == 1) return info.links.single;

  final episodeFile = selectEpisodeFile(
    info.files,
    episode,
    preferredFileIndex: preferredFileIndex,
  );
  final selectedFiles = info.files.where((file) => file.selected).toList();
  final selectedIndex = selectedFiles.indexWhere(
    (file) => file.id == episodeFile.id,
  );
  if (selectedIndex >= 0 && selectedIndex < info.links.length) {
    return info.links[selectedIndex];
  }

  // Some older API responses omit the selected flag while returning one link
  // per torrent file. Preserve correct batch mapping in that representation.
  if (info.links.length == info.files.length) {
    final fileIndex = info.files.indexWhere(
      (file) => file.id == episodeFile.id,
    );
    if (fileIndex >= 0) return info.links[fileIndex];
  }

  throw const RealDebridException(
    'Real-Debrid did not identify which download belongs to this episode. '
    'Choose another release.',
    kind: RealDebridFailureKind.releaseUnavailable,
  );
}

RealDebridTorrentFile selectEpisodeFile(
  List<RealDebridTorrentFile> files,
  int episode, {
  int? preferredFileIndex,
}) {
  final playable = files.where((file) => file.isPlayable).toList();
  if (playable.isEmpty) {
    throw StateError('The torrent contains no supported video files.');
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
    final matches = playable.where((file) => pattern.hasMatch(file.path));
    if (matches.isNotEmpty) {
      return matches.reduce((a, b) => a.bytes >= b.bytes ? a : b);
    }
  }
  return playable.reduce((a, b) => a.bytes >= b.bytes ? a : b);
}
