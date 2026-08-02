// ignore_for_file: avoid_print

import 'package:anime_tv/features/streaming/data/torrentio_release_source.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

Future<void> main() async {
  final source = TorrentioReleaseSource(
    manifestUrl: 'https://torrentio.strem.fun/manifest.json',
  );
  final releases = await source.search(
    const EpisodeReference(
      anilistMediaId: 154587,
      malMediaId: 52991,
      title: 'Frieren: Beyond Journey’s End',
      episode: 1,
      alternativeTitles: ['Sousou no Frieren'],
    ),
  );
  final dubbed = releases.where((release) => release.isDubbed).length;
  final subbed = releases.where((release) => !release.isDubbed).length;
  print(
    'Torrentio smoke test: ${releases.length} streams '
    '($subbed sub, $dubbed dub/dual).',
  );
}
