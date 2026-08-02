import 'package:anime_tv/features/streaming/data/torrentio_release_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Torrentio stream metadata and dub/sub labels', () {
    final releases = TorrentioReleaseSource.parseStreams({
      'streams': [
        {
          'name': 'Torrentio\n1080p HDR',
          'title':
              '[Group] Example Episode 01 HEVC\n'
              '👤 532 💾 647.82 MB ⚙️ NyaaSi\n'
              'Dubbed / Dual Audio / Multi Subs',
          'infoHash': 'f03841b6b24585b1571df6b0c930d9946047058f',
          'fileIdx': 15,
          'behaviorHints': {'filename': 'Example - S01E01.mkv'},
        },
        {
          'name': 'Torrentio\n720p',
          'title':
              '[SubsPlease] Example - 01 (720p)\n'
              '👤 39 💾 771.35 MB ⚙️ NyaaSi',
          'infoHash': 'ab4369b560243237f9371ce896ee02ed00027b95',
          'fileIdx': 0,
        },
      ],
    });

    expect(releases, hasLength(2));
    expect(releases.first.quality, '1080p');
    expect(releases.first.codec, 'HEVC');
    expect(releases.first.isHdr, isTrue);
    expect(releases.first.isDubbed, isTrue);
    expect(releases.first.hasSubtitles, isTrue);
    expect(releases.first.preferredFileIndex, 15);
    expect(releases.first.seeders, 532);
    expect(releases.first.sizeLabel, '647.82 MB');
    expect(releases.first.provider, 'NyaaSi');
    expect(releases.last.isDubbed, isFalse);
    expect(releases.last.hasSubtitles, isTrue);
  });

  test('ignores direct-only and malformed stream entries', () {
    final releases = TorrentioReleaseSource.parseStreams({
      'streams': [
        {'name': 'Direct', 'url': 'https://example.com/video.mp4'},
        {'name': 'Broken', 'infoHash': 'not-a-hash'},
      ],
    });

    expect(releases, isEmpty);
  });
}
