import 'package:anime_tv/features/streaming/data/stremio_torrent_release_source.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses generic Stremio torrent metadata and dub/sub labels', () {
    final releases = StremioTorrentReleaseSource.parseStreams({
      'streams': [
        {
          'name': 'User source\n1080p HDR',
          'title':
              '[Group] Example Episode 01 HEVC\n'
              '👤 532 💾 647.82 MB ⚙️ UserProvider\n'
              'Dubbed / Dual Audio / Multi Subs',
          'infoHash': 'f03841b6b24585b1571df6b0c930d9946047058f',
          'fileIdx': 15,
          'behaviorHints': {'filename': 'Example - S01E01.mkv'},
        },
        {
          'name': 'User source\n720p',
          'title':
              '[SubsPlease] Example - 01 (720p)\n'
              '👤 39 💾 771.35 MB ⚙️ UserProvider',
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
    expect(releases.first.provider, 'UserProvider');
    expect(releases.last.isDubbed, isFalse);
    expect(releases.last.hasSubtitles, isTrue);
  });

  test('ignores direct-only and malformed stream entries', () {
    final releases = StremioTorrentReleaseSource.parseStreams({
      'streams': [
        {'name': 'Direct', 'url': 'https://example.com/video.mp4'},
        {'name': 'Broken', 'infoHash': 'not-a-hash'},
      ],
    });

    expect(releases, isEmpty);
  });

  test('rejects redirects instead of following them to another host', () async {
    final addonDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 302,
              headers: Headers.fromMap({
                'location': ['https://127.0.0.1/private'],
              }),
            ),
          ),
        ),
      );
    final kitsuDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                'data': [
                  {
                    'relationships': {
                      'item': {
                        'data': {'id': '42'},
                      },
                    },
                  },
                ],
              },
            ),
          ),
        ),
      );
    final source = StremioTorrentReleaseSource(
      manifestUrl: 'https://example.com/addon/manifest.json',
      addonDio: addonDio,
      kitsuDio: kitsuDio,
      targetValidator: (_) async {},
    );

    await expectLater(
      source.search(
        const EpisodeReference(
          anilistMediaId: 1,
          malMediaId: 2,
          title: 'Example',
          episode: 1,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an oversized untrusted stream response', () async {
    final addonDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data:
                  '{"streams":[],"padding":"'
                  '${List.filled(2049, List.filled(1024, 'x').join()).join()}"}',
            ),
          ),
        ),
      );
    final kitsuDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                'data': [
                  {
                    'relationships': {
                      'item': {
                        'data': {'id': '42'},
                      },
                    },
                  },
                ],
              },
            ),
          ),
        ),
      );
    final source = StremioTorrentReleaseSource(
      manifestUrl: 'https://example.com/addon/manifest.json',
      addonDio: addonDio,
      kitsuDio: kitsuDio,
      targetValidator: (_) async {},
    );

    await expectLater(
      source.search(
        const EpisodeReference(
          anilistMediaId: 1,
          malMediaId: 2,
          title: 'Example',
          episode: 1,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
