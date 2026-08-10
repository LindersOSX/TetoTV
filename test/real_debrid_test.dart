import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Real-Debrid torrent selection', () {
    test('selects the video matching the requested episode in a batch', () {
      final selected = selectEpisodeFile(const [
        RealDebridTorrentFile(
          id: 1,
          path: '/Show - 01.mkv',
          bytes: 900,
          selected: false,
        ),
        RealDebridTorrentFile(
          id: 2,
          path: '/Show - 02.mkv',
          bytes: 950,
          selected: false,
        ),
        RealDebridTorrentFile(
          id: 3,
          path: '/cover.jpg',
          bytes: 20,
          selected: false,
        ),
      ], 2);

      expect(selected.id, 2);
    });

    test('falls back to the largest playable file', () {
      final selected = selectEpisodeFile(const [
        RealDebridTorrentFile(
          id: 10,
          path: '/feature-a.mkv',
          bytes: 400,
          selected: false,
        ),
        RealDebridTorrentFile(
          id: 11,
          path: '/feature-b.mp4',
          bytes: 800,
          selected: false,
        ),
      ], 12);

      expect(selected.id, 11);
    });

    test('honors a Stremio file index', () {
      final selected = selectEpisodeFile(
        const [
          RealDebridTorrentFile(
            id: 1,
            path: '/Episode 01.mkv',
            bytes: 900,
            selected: false,
          ),
          RealDebridTorrentFile(
            id: 2,
            path: '/Episode 02.mkv',
            bytes: 1000,
            selected: false,
          ),
        ],
        1,
        preferredFileIndex: 1,
      );

      expect(selected.id, 2);
    });

    test('maps a downloaded batch episode to its corresponding link', () {
      final link = selectEpisodeDownloadLink(
        const RealDebridTorrentInfo(
          id: 'batch',
          filename: 'Show batch',
          status: 'downloaded',
          progress: 100,
          files: [
            RealDebridTorrentFile(
              id: 10,
              path: '/Show - 01.mkv',
              bytes: 900,
              selected: true,
            ),
            RealDebridTorrentFile(
              id: 11,
              path: '/cover.jpg',
              bytes: 20,
              selected: false,
            ),
            RealDebridTorrentFile(
              id: 12,
              path: '/Show - 02.mkv',
              bytes: 950,
              selected: true,
            ),
          ],
          links: [
            'https://rd.example/episode-1',
            'https://rd.example/episode-2',
          ],
        ),
        2,
      );

      expect(link, 'https://rd.example/episode-2');
    });
  });

  group('Real-Debrid API failures', () {
    test('classifies code 35 as a safe release-specific failure', () {
      final error = RealDebridException.fromApi(code: 35, httpStatus: 403);

      expect(error.kind, RealDebridFailureKind.releaseUnavailable);
      expect(error.isCandidateSpecific, isTrue);
      expect(error.isTerminalAccountFailure, isFalse);
      expect(error.toString(), isNot(contains('infringing_file')));
      expect(error.toString(), contains('different release'));
    });

    test('classifies invalid authorization as terminal', () {
      final error = RealDebridException.fromApi(code: 8, httpStatus: 401);

      expect(error.kind, RealDebridFailureKind.authorization);
      expect(error.isTerminalAccountFailure, isTrue);
      expect(error.toString(), contains('Reconnect'));
    });

    test('does not fan out account-capacity or rate-limit failures', () {
      final activeDownloads = RealDebridException.fromApi(code: 21);
      final tooManyRequests = RealDebridException.fromApi(code: 34);

      expect(activeDownloads.kind, RealDebridFailureKind.account);
      expect(activeDownloads.isTerminalAccountFailure, isTrue);
      expect(activeDownloads.canTryAnotherRelease, isFalse);
      expect(tooManyRequests.kind, RealDebridFailureKind.rateLimited);
      expect(tooManyRequests.canTryAnotherRelease, isFalse);
    });
  });

  test('parses premium account state', () {
    final account = RealDebridAccount.fromJson({
      'id': 42,
      'username': 'tv-user',
      'type': 'premium',
      'expiration': DateTime.now()
          .add(const Duration(days: 10))
          .toUtc()
          .toIso8601String(),
    });

    expect(account.username, 'tv-user');
    expect(account.isPremium, isTrue);
  });
}
