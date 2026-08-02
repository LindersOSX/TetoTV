import 'dart:async';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

class CompositeReleaseSource implements ReleaseSource {
  const CompositeReleaseSource(this.sources);

  final List<ReleaseSource> sources;

  @override
  String get id => 'composite';

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) async {
    final futures = sources.map((source) async {
      try {
        return await source.search(episode);
      } catch (e) {
        // A single provider failure should not fail the entire search
        return <ReleaseCandidate>[];
      }
    });

    final results = await Future.wait(futures);
    final allCandidates = results.expand((x) => x).toList();

    // Deduplicate by infoHash
    final uniqueMap = <String, ReleaseCandidate>{};
    for (final candidate in allCandidates) {
      final hash = candidate.infoHash.toLowerCase();
      if (!uniqueMap.containsKey(hash)) {
        uniqueMap[hash] = candidate;
      } else {
        // Merge seeders or pick the one with better metadata if already exists
        final existing = uniqueMap[hash]!;
        if (candidate.seeders > existing.seeders ||
            (candidate.provider != null && existing.provider == null)) {
          uniqueMap[hash] = candidate;
        }
      }
    }

    final deduplicated = uniqueMap.values.toList();

    // Rank intelligently
    deduplicated.sort((a, b) {
      // 1. Prefer batches or single depending on if we just need one episode (assuming single is better for single ep search unless batch is all we have)
      // We will let the resolver handle the batch vs single bias, but we can do some basic ranking here.
      // 2. Resolution
      final resScoreA = _resolutionScore(a.quality);
      final resScoreB = _resolutionScore(b.quality);
      if (resScoreA != resScoreB) return resScoreB.compareTo(resScoreA);

      // 3. Codec preference (HEVC/AV1 is better if device supports it, but for ranking just prefer modern codecs)
      final codecScoreA = _codecScore(a.codec);
      final codecScoreB = _codecScore(b.codec);
      if (codecScoreA != codecScoreB) return codecScoreB.compareTo(codecScoreA);

      // 4. Seeders
      return b.seeders.compareTo(a.seeders);
    });

    return deduplicated;
  }

  int _resolutionScore(String? quality) {
    if (quality == null) return 0;
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('2160')) return 4;
    if (q.contains('1080')) return 3;
    if (q.contains('720')) return 2;
    if (q.contains('480')) return 1;
    return 0;
  }

  int _codecScore(String? codec) {
    if (codec == null) return 0;
    final c = codec.toLowerCase();
    if (c.contains('hevc') || c.contains('265') || c.contains('av1')) return 2;
    if (c.contains('264') || c.contains('avc')) return 1;
    return 0;
  }
}
