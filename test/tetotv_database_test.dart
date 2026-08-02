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
