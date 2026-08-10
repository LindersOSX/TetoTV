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
      preferredReleaseProvider: 'User source',
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
    expect(restored.preferredReleaseProvider, 'User source');
  });

  test(
    'checkpoint transaction restores a dismissed title atomically',
    () async {
      final database = _CheckpointExecutor();
      final checkpoint = PlaybackCheckpoint(
        anilistMediaId: 42,
        malMediaId: 84,
        episode: 3,
        title: 'Test Show',
        coverImageUrl: 'https://example.test/poster.jpg',
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 24),
        updatedAt: DateTime.utc(2026, 8, 2),
        completed: false,
      );

      await saveCheckpointTransaction(database, checkpoint);

      expect(database.calls, [
        'delete:continue_watching_dismissals:42',
        'insert:playback_history',
      ]);
      expect(database.inserted?['anilist_media_id'], 42);
      expect(database.inserted?['episode'], 3);
      expect(database.conflictAlgorithm, ConflictAlgorithm.replace);
    },
  );

  test('diagnostic text redacts URLs, tokens, magnets, and info hashes', () {
    final redacted = redactDiagnosticValue(
      'Bearer secret https://cdn.example/video magnet:?xt=urn:btih:abc '
      '0123456789abcdef0123456789abcdef01234567 '
      'github_'
      'pat_exampleExampleExample123456 '
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature '
      '{"access_token":"oauth-secret","client_secret":"client-secret"} '
      'http://legacy.example/video',
    );
    expect(redacted, isNot(contains('secret')));
    expect(redacted, isNot(contains('cdn.example')));
    expect(redacted, isNot(contains('legacy.example')));
    expect(redacted, isNot(contains('github_pat_')));
    expect(redacted, isNot(contains('eyJhbGci')));
    expect(redacted, contains('[MAGNET]'));
    expect(redacted, contains('[INFO_HASH]'));
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

class _CheckpointExecutor implements DatabaseExecutor {
  final calls = <String>[];
  Map<String, Object?>? inserted;
  ConflictAlgorithm? conflictAlgorithm;

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    calls.add('delete:$table:${whereArgs?.single}');
    return 1;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    calls.add('insert:$table');
    inserted = values;
    this.conflictAlgorithm = conflictAlgorithm;
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
