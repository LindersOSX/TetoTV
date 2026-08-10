import 'dart:async';
import 'dart:collection';

import 'package:anime_tv/features/streaming/data/premiumize_client.dart';
import 'package:anime_tv/features/streaming/data/premiumize_models.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

class PremiumizeStreamResolver implements StreamResolver {
  PremiumizeStreamResolver(
    this._client,
    this._releaseSource, {
    this.pollInterval = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 30),
  });

  final PremiumizeClient _client;
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

    try {
      final files = await _client.directDownload(release.magnetUri);
      final selected = selectPremiumizeEpisodeFile(
        files,
        episode.episode,
        preferredFileIndex: release.preferredFileIndex,
      );
      yield StreamReady(
        uri: selected.link,
        displayName: selected.name,
        debridService: DebridService.premiumize,
      );
      return;
    } on PremiumizeException catch (error) {
      if (!_canQueueAfterDirectFailure(error)) rethrow;
    }

    final creation = await _client.createTransfer(release.magnetUri);
    final deadline = DateTime.now().add(timeout);
    PremiumizeTransfer? transfer;

    while (DateTime.now().isBefore(deadline)) {
      final transfers = await _client.transfers();
      transfer = _findTransfer(transfers, creation.id);
      if (transfer?.hasFailed == true) {
        final detail = transfer!.message.trim();
        throw StateError(
          detail.isEmpty
              ? 'Premiumize transfer failed.'
              : 'Premiumize transfer failed: $detail',
        );
      }
      if (transfer?.isReady == true) break;
      yield StreamCaching(
        torrentId: creation.id,
        progress: transfer?.progress ?? 0,
      );
      await Future<void>.delayed(pollInterval);
    }

    if (transfer == null || !transfer.isReady) {
      throw TimeoutException(
        'Premiumize did not finish the transfer before the timeout.',
        timeout,
      );
    }

    final files = await _transferFiles(transfer);
    final selected = selectPremiumizeEpisodeFile(
      files,
      episode.episode,
      preferredFileIndex: release.preferredFileIndex,
    );
    yield StreamReady(
      uri: selected.link,
      displayName: selected.name,
      debridService: DebridService.premiumize,
    );
  }

  Future<List<PremiumizeFile>> _transferFiles(
    PremiumizeTransfer transfer,
  ) async {
    final fileId = transfer.fileId;
    if (fileId != null) return [await _client.itemDetails(fileId)];

    final folderId = transfer.folderId;
    if (folderId == null) {
      throw StateError(
        'Premiumize finished the transfer without a playable cloud file.',
      );
    }

    final files = <PremiumizeFile>[];
    final pending = Queue<_PendingFolder>()..add(_PendingFolder(folderId, ''));
    final visited = <String>{};
    while (pending.isNotEmpty) {
      if (visited.length >= 100) {
        throw StateError('Premiumize returned too many nested folders.');
      }
      final folder = pending.removeFirst();
      if (!visited.add(folder.id)) continue;
      final entries = await _client.folderContents(folder.id);
      for (final entry in entries) {
        final path = folder.path.isEmpty
            ? entry.name
            : '${folder.path}/${entry.name}';
        if (entry.isFolder) {
          pending.add(_PendingFolder(entry.id, path));
        } else if (entry.link case final link?) {
          files.add(
            PremiumizeFile(
              id: entry.id,
              name: path,
              size: entry.size,
              link: link,
            ),
          );
        }
      }
    }
    return files;
  }
}

class _PendingFolder {
  const _PendingFolder(this.id, this.path);

  final String id;
  final String path;
}

PremiumizeTransfer? _findTransfer(
  List<PremiumizeTransfer> transfers,
  String id,
) {
  for (final transfer in transfers) {
    if (transfer.id == id) return transfer;
  }
  return null;
}

bool _canQueueAfterDirectFailure(PremiumizeException error) =>
    !error.isAuthenticationFailure &&
    error.code != 'invalid_request' &&
    error.code != 'account_limit_reached' &&
    error.code != 'service_limit_reached' &&
    error.code != 'rate_limit_reached';

PremiumizeFile selectPremiumizeEpisodeFile(
  List<PremiumizeFile> files,
  int episode, {
  int? preferredFileIndex,
}) {
  final playable = files.where((file) => file.isPlayable).toList();
  if (playable.isEmpty) {
    throw StateError('The Premiumize transfer contains no supported videos.');
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
