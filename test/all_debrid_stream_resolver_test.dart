import 'package:anime_tv/features/streaming/data/all_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/all_debrid_models.dart';
import 'package:anime_tv/features/streaming/data/all_debrid_stream_resolver.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reports cache progress then resolves the requested batch episode',
    () async {
      final client = _FakeAllDebridClient();
      final release = ReleaseCandidate(
        infoHash: 'hash',
        magnetUri: 'magnet:?xt=urn:btih:hash',
        releaseName: 'Show batch',
        seeders: 20,
        sourceId: 'test',
        isBatch: true,
      );
      final resolver = AllDebridStreamResolver(
        client,
        SingleReleaseSource(release),
        pollInterval: Duration.zero,
      );

      final states = await resolver
          .resolve(
            const EpisodeReference(
              anilistMediaId: 1,
              title: 'Show',
              episode: 2,
            ),
          )
          .toList();

      expect(states, hasLength(2));
      expect(
        states.first,
        isA<StreamCaching>().having(
          (state) => state.progress,
          'progress',
          closeTo(.5, .001),
        ),
      );
      expect(
        states.last,
        isA<StreamReady>()
            .having(
              (state) => state.debridService,
              'service',
              DebridService.allDebrid,
            )
            .having((state) => state.displayName, 'file', contains('02')),
      );
    },
  );

  test('file selection honors an addon file index', () {
    final selected = selectAllDebridEpisodeFile(
      const [
        AllDebridTorrentFile(
          name: 'Episode 01.mkv',
          size: 100,
          link: 'https://redirect.test/1',
        ),
        AllDebridTorrentFile(
          name: 'Episode 02.mkv',
          size: 200,
          link: 'https://redirect.test/2',
        ),
      ],
      1,
      preferredFileIndex: 1,
    );

    expect(selected.name, 'Episode 02.mkv');
  });
}

class _FakeAllDebridClient extends AllDebridClient {
  _FakeAllDebridClient() : super(token: 'test');

  int _statusCalls = 0;

  @override
  Future<AllDebridMagnetUpload> uploadMagnet(String magnetUri) async =>
      const AllDebridMagnetUpload(id: 42, ready: false);

  @override
  Future<AllDebridMagnetStatus> magnetStatus(int id) async {
    _statusCalls++;
    return AllDebridMagnetStatus(
      id: id,
      status: _statusCalls == 1 ? 'Downloading' : 'Ready',
      statusCode: _statusCalls == 1 ? 1 : 4,
      downloaded: _statusCalls == 1 ? 100 : 200,
      size: 200,
    );
  }

  @override
  Future<List<AllDebridTorrentFile>> magnetFiles(int id) async => const [
    AllDebridTorrentFile(
      name: 'Show - 01.mkv',
      size: 100,
      link: 'https://redirect.test/1',
    ),
    AllDebridTorrentFile(
      name: 'Show - 02.mkv',
      size: 200,
      link: 'https://redirect.test/2',
    ),
  ];

  @override
  Future<Uri> unlock(String link) async =>
      Uri.parse('https://cdn.alldebrid.test/02.mkv');
}
