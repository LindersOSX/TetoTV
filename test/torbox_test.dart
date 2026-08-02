import 'package:anime_tv/features/streaming/data/torbox_models.dart';
import 'package:anime_tv/features/streaming/data/torbox_stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a ready TorBox torrent and its playable files', () {
    final torrent = TorBoxTorrent.fromJson({
      'id': 42,
      'name': 'Example',
      'download_state': 'cached',
      'progress': 100,
      'download_finished': true,
      'cached': true,
      'files': [
        {'id': 10, 'short_name': 'Example - 01.mkv', 'size': 900},
        {'id': 11, 'short_name': 'Example - 02.mkv', 'size': 950},
        {'id': 12, 'short_name': 'cover.jpg', 'size': 20},
      ],
    });

    expect(torrent.isReady, isTrue);
    expect(torrent.progress, 1);
    expect(torrent.files.where((file) => file.isPlayable), hasLength(2));
  });

  test('honors the Stremio file index for TorBox batches', () {
    const files = [
      TorBoxFile(id: 10, name: 'Example - 01.mkv', size: 900),
      TorBoxFile(id: 11, name: 'Example - 02.mkv', size: 950),
    ];

    final selected = selectTorBoxEpisodeFile(files, 1, preferredFileIndex: 1);

    expect(selected.id, 11);
  });

  test('falls back to episode matching for TorBox batches', () {
    const files = [
      TorBoxFile(id: 10, name: 'Example - 01.mkv', size: 900),
      TorBoxFile(id: 11, name: 'Example - 02.mkv', size: 950),
    ];

    expect(selectTorBoxEpisodeFile(files, 2).id, 11);
  });
}
