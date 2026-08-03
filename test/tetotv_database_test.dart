import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  test('configures WAL with a query before enabling foreign keys', () async {
    final database = _RecordingDatabase();

    await configureTetoTvDatabase(database);

    expect(database.calls, [
      'query:PRAGMA journal_mode=WAL',
      'execute:PRAGMA foreign_keys=ON',
    ]);
  });

  test('series playback and stream preferences survive JSON storage', () {
    const preferences = SeriesPlaybackPreferences(
      audioLanguage: 'jpn',
      subtitleLanguage: 'eng',
      subtitleEnabled: true,
      subtitlePreferenceSet: true,
      subtitleSize: 42,
      autoplayNextEpisode: true,
      preferredStreamLanguage: 'sub',
      preferredQuality: 'p1080',
      preferredCodec: 'hevc',
      preferredHdrMode: 'sdr',
      allowBatchStreams: false,
      streamSortMode: 'seeders',
      preferredReleaseProvider: 'Torrentio',
    );

    final restored = SeriesPlaybackPreferences.fromJson(preferences.toJson());

    expect(restored.audioLanguage, 'jpn');
    expect(restored.subtitlePreferenceSet, isTrue);
    expect(restored.subtitleSize, 42);
    expect(restored.preferredStreamLanguage, 'sub');
    expect(restored.preferredQuality, 'p1080');
    expect(restored.preferredCodec, 'hevc');
    expect(restored.preferredHdrMode, 'sdr');
    expect(restored.allowBatchStreams, isFalse);
    expect(restored.streamSortMode, 'seeders');
    expect(restored.preferredReleaseProvider, 'Torrentio');
  });
}

class _RecordingDatabase implements Database {
  final calls = <String>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    calls.add('query:$sql');
    return const [
      <String, Object?>{'journal_mode': 'wal'},
    ];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    calls.add('execute:$sql');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
