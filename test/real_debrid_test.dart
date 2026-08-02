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
