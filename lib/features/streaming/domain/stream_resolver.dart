import 'package:anime_tv/features/streaming/domain/debrid_service.dart';

class EpisodeReference {
  const EpisodeReference({
    required this.anilistMediaId,
    required this.title,
    required this.episode,
    this.malMediaId,
    this.alternativeTitles = const [],
    this.coverImageUrl,
    this.startFromBeginning = false,
  });

  final int anilistMediaId;
  final int? malMediaId;
  final String title;
  final int episode;
  final List<String> alternativeTitles;
  final String? coverImageUrl;
  final bool startFromBeginning;
}

class ReleaseCandidate {
  const ReleaseCandidate({
    required this.infoHash,
    required this.magnetUri,
    required this.releaseName,
    required this.seeders,
    required this.sourceId,
    this.isBatch = false,
    this.preferredFileIndex,
    this.quality,
    this.codec,
    this.sizeLabel,
    this.provider,
    this.isDubbed = false,
    this.hasSubtitles = false,
    this.isHdr = false,
  });

  final String infoHash;
  final String magnetUri;
  final String releaseName;
  final int seeders;
  final String sourceId;
  final bool isBatch;
  final int? preferredFileIndex;
  final String? quality;
  final String? codec;
  final String? sizeLabel;
  final String? provider;
  final bool isDubbed;
  final bool hasSubtitles;
  final bool isHdr;
}

sealed class StreamResolution {
  const StreamResolution();
}

class StreamReady extends StreamResolution {
  const StreamReady({
    required this.uri,
    required this.displayName,
    required this.debridService,
  });

  final Uri uri;
  final String displayName;
  final DebridService debridService;
}

class StreamCaching extends StreamResolution {
  const StreamCaching({required this.torrentId, required this.progress});

  final String torrentId;
  final double progress;
}

/// Everything the player needs to recover from a bad host without exposing
/// an unrestricted URL to arbitrary navigation or accepting non-debrid media.
class PlaybackLaunch {
  const PlaybackLaunch({
    required this.stream,
    required this.episode,
    required this.selectedRelease,
    this.alternatives = const [],
  });

  final StreamReady stream;
  final EpisodeReference episode;
  final ReleaseCandidate selectedRelease;
  final List<ReleaseCandidate> alternatives;
}

abstract interface class ReleaseSource {
  String get id;

  Future<List<ReleaseCandidate>> search(EpisodeReference episode);
}

abstract interface class StreamResolver {
  Stream<StreamResolution> resolve(EpisodeReference episode);
}

class SingleReleaseSource implements ReleaseSource {
  const SingleReleaseSource(this.release);

  final ReleaseCandidate release;

  @override
  String get id => release.sourceId;

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) async => [
    release,
  ];
}
