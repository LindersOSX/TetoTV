import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<void> configureTetoTvDatabase(Database db) async {
  // journal_mode returns a result row on Android, so sqflite requires
  // rawQuery rather than execute.
  await db.rawQuery('PRAGMA journal_mode=WAL');
  await db.execute('PRAGMA foreign_keys=ON');
}

class PlaybackCheckpoint {
  const PlaybackCheckpoint({
    required this.anilistMediaId,
    required this.episode,
    required this.title,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.malMediaId,
    this.coverImageUrl,
    this.completed = false,
  });

  final int anilistMediaId;
  final int? malMediaId;
  final int episode;
  final String title;
  final String? coverImageUrl;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  final bool completed;

  double get progress => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  Map<String, Object?> toMap() => {
    'anilist_media_id': anilistMediaId,
    'mal_media_id': malMediaId,
    'episode': episode,
    'title': title,
    'cover_image_url': coverImageUrl,
    'position_ms': position.inMilliseconds,
    'duration_ms': duration.inMilliseconds,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'completed': completed ? 1 : 0,
  };

  factory PlaybackCheckpoint.fromMap(Map<String, Object?> value) =>
      PlaybackCheckpoint(
        anilistMediaId: value['anilist_media_id']! as int,
        malMediaId: value['mal_media_id'] as int?,
        episode: value['episode']! as int,
        title: value['title']! as String,
        coverImageUrl: value['cover_image_url'] as String?,
        position: Duration(milliseconds: value['position_ms']! as int),
        duration: Duration(milliseconds: value['duration_ms']! as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          value['updated_at']! as int,
        ),
        completed: value['completed'] == 1,
      );
}

class SeriesPlaybackPreferences {
  const SeriesPlaybackPreferences({
    this.audioLanguage = 'eng',
    this.subtitleLanguage = 'eng',
    this.subtitleEnabled = true,
    this.subtitlePreferenceSet = false,
    this.subtitleSize = 34,
    this.subtitlePosition = 100,
    this.subtitleDelayMs = 0,
    this.audioDelayMs = 0,
    this.decoder = 'hardware-safe',
    this.videoFit = 'contain',
    this.highContrastSubtitles = false,
    this.autoplayNextEpisode = true,
    this.preferredStreamLanguage = 'dub',
    this.preferredQuality = 'any',
    this.preferredCodec = 'any',
    this.preferredHdrMode = 'any',
    this.allowBatchStreams = true,
    this.streamSortMode = 'compatibility',
    this.preferredReleaseProvider,
  });

  final String audioLanguage;
  final String subtitleLanguage;
  final bool subtitleEnabled;
  final bool subtitlePreferenceSet;
  final double subtitleSize;
  final int subtitlePosition;
  final int subtitleDelayMs;
  final int audioDelayMs;
  final String decoder;
  final String videoFit;
  final bool highContrastSubtitles;
  final bool autoplayNextEpisode;
  final String preferredStreamLanguage;
  final String preferredQuality;
  final String preferredCodec;
  final String preferredHdrMode;
  final bool allowBatchStreams;
  final String streamSortMode;
  final String? preferredReleaseProvider;

  SeriesPlaybackPreferences copyWith({
    String? audioLanguage,
    String? subtitleLanguage,
    bool? subtitleEnabled,
    bool? subtitlePreferenceSet,
    double? subtitleSize,
    int? subtitlePosition,
    int? subtitleDelayMs,
    int? audioDelayMs,
    String? decoder,
    String? videoFit,
    bool? highContrastSubtitles,
    bool? autoplayNextEpisode,
    String? preferredStreamLanguage,
    String? preferredQuality,
    String? preferredCodec,
    String? preferredHdrMode,
    bool? allowBatchStreams,
    String? streamSortMode,
    String? preferredReleaseProvider,
    bool clearPreferredReleaseProvider = false,
  }) => SeriesPlaybackPreferences(
    audioLanguage: audioLanguage ?? this.audioLanguage,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    subtitleEnabled: subtitleEnabled ?? this.subtitleEnabled,
    subtitlePreferenceSet: subtitlePreferenceSet ?? this.subtitlePreferenceSet,
    subtitleSize: subtitleSize ?? this.subtitleSize,
    subtitlePosition: subtitlePosition ?? this.subtitlePosition,
    subtitleDelayMs: subtitleDelayMs ?? this.subtitleDelayMs,
    audioDelayMs: audioDelayMs ?? this.audioDelayMs,
    decoder: decoder ?? this.decoder,
    videoFit: videoFit ?? this.videoFit,
    highContrastSubtitles: highContrastSubtitles ?? this.highContrastSubtitles,
    autoplayNextEpisode: autoplayNextEpisode ?? this.autoplayNextEpisode,
    preferredStreamLanguage:
        preferredStreamLanguage ?? this.preferredStreamLanguage,
    preferredQuality: preferredQuality ?? this.preferredQuality,
    preferredCodec: preferredCodec ?? this.preferredCodec,
    preferredHdrMode: preferredHdrMode ?? this.preferredHdrMode,
    allowBatchStreams: allowBatchStreams ?? this.allowBatchStreams,
    streamSortMode: streamSortMode ?? this.streamSortMode,
    preferredReleaseProvider: clearPreferredReleaseProvider
        ? null
        : preferredReleaseProvider ?? this.preferredReleaseProvider,
  );

  Map<String, Object?> toJson() => {
    'audioLanguage': audioLanguage,
    'subtitleLanguage': subtitleLanguage,
    'subtitleEnabled': subtitleEnabled,
    'subtitlePreferenceSet': subtitlePreferenceSet,
    'subtitleSize': subtitleSize,
    'subtitlePosition': subtitlePosition,
    'subtitleDelayMs': subtitleDelayMs,
    'audioDelayMs': audioDelayMs,
    'decoder': decoder,
    'videoFit': videoFit,
    'highContrastSubtitles': highContrastSubtitles,
    'autoplayNextEpisode': autoplayNextEpisode,
    'preferredStreamLanguage': preferredStreamLanguage,
    'preferredQuality': preferredQuality,
    'preferredCodec': preferredCodec,
    'preferredHdrMode': preferredHdrMode,
    'allowBatchStreams': allowBatchStreams,
    'streamSortMode': streamSortMode,
    'preferredReleaseProvider': preferredReleaseProvider,
  };

  factory SeriesPlaybackPreferences.fromJson(Map<String, dynamic> json) =>
      SeriesPlaybackPreferences(
        audioLanguage: json['audioLanguage'] as String? ?? 'eng',
        subtitleLanguage: json['subtitleLanguage'] as String? ?? 'eng',
        subtitleEnabled: json['subtitleEnabled'] as bool? ?? true,
        subtitlePreferenceSet: json['subtitlePreferenceSet'] as bool? ?? false,
        subtitleSize: (json['subtitleSize'] as num?)?.toDouble() ?? 34,
        subtitlePosition: json['subtitlePosition'] as int? ?? 100,
        subtitleDelayMs: json['subtitleDelayMs'] as int? ?? 0,
        audioDelayMs: json['audioDelayMs'] as int? ?? 0,
        decoder: json['decoder'] as String? ?? 'hardware-safe',
        videoFit: json['videoFit'] as String? ?? 'contain',
        highContrastSubtitles: json['highContrastSubtitles'] as bool? ?? false,
        autoplayNextEpisode: json['autoplayNextEpisode'] as bool? ?? true,
        preferredStreamLanguage:
            json['preferredStreamLanguage'] as String? ?? 'dub',
        preferredQuality: json['preferredQuality'] as String? ?? 'any',
        preferredCodec: json['preferredCodec'] as String? ?? 'any',
        preferredHdrMode: json['preferredHdrMode'] as String? ?? 'any',
        allowBatchStreams: json['allowBatchStreams'] as bool? ?? true,
        streamSortMode: json['streamSortMode'] as String? ?? 'compatibility',
        preferredReleaseProvider: json['preferredReleaseProvider'] as String?,
      );
}

class TetoTvDatabase {
  TetoTvDatabase._();

  static final instance = TetoTvDatabase._();
  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    final openDatabase = _database;
    if (openDatabase != null) return openDatabase;

    // Several providers can request the database during the same frame. Keep
    // one shared open operation so Android never races multiple connections to
    // the same file.
    final opening = _opening ??= _open();
    try {
      final database = await opening;
      _database = database;
      return database;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(
      path.join(root, 'tetotv.db'),
      version: 2,
      onConfigure: configureTetoTvDatabase,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE playback_history (
            anilist_media_id INTEGER NOT NULL,
            mal_media_id INTEGER,
            episode INTEGER NOT NULL,
            title TEXT NOT NULL,
            cover_image_url TEXT,
            position_ms INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            completed INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (anilist_media_id, episode)
          )
        ''');
        await db.execute('''
          CREATE INDEX playback_history_updated
          ON playback_history(updated_at DESC)
        ''');
        await db.execute('''
          CREATE TABLE series_preferences (
            anilist_media_id INTEGER PRIMARY KEY,
            preferences_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE stream_failures (
            device_key TEXT NOT NULL,
            info_hash TEXT NOT NULL,
            reason TEXT,
            failure_count INTEGER NOT NULL DEFAULT 1,
            last_failed_at INTEGER NOT NULL,
            PRIMARY KEY (device_key, info_hash)
          )
        ''');
        await db.execute('''
          CREATE TABLE catalog_cache (
            cache_key TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            expires_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE performance_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            duration_us INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await _createContinueDismissalsTable(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createContinueDismissalsTable(db);
      },
    );
  }

  Future<void> saveCheckpoint(PlaybackCheckpoint checkpoint) async {
    final db = await database;
    await db.transaction((txn) => saveCheckpointTransaction(txn, checkpoint));
  }

  Future<PlaybackCheckpoint?> checkpoint(int mediaId, int episode) async {
    final db = await database;
    final rows = await db.query(
      'playback_history',
      where: 'anilist_media_id = ? AND episode = ?',
      whereArgs: [mediaId, episode],
      limit: 1,
    );
    return rows.isEmpty ? null : PlaybackCheckpoint.fromMap(rows.first);
  }

  Future<PlaybackCheckpoint?> latestCheckpoint(int mediaId) async {
    final db = await database;
    final rows = await db.query(
      'playback_history',
      where: 'anilist_media_id = ?',
      whereArgs: [mediaId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : PlaybackCheckpoint.fromMap(rows.first);
  }

  Future<List<PlaybackCheckpoint>> recentHistory({int limit = 20}) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT h.* FROM playback_history h
      INNER JOIN (
        SELECT anilist_media_id, MAX(updated_at) AS latest
        FROM playback_history
        GROUP BY anilist_media_id
      ) grouped
      ON h.anilist_media_id = grouped.anilist_media_id
      AND h.updated_at = grouped.latest
      ORDER BY h.updated_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(PlaybackCheckpoint.fromMap).toList(growable: false);
  }

  Future<void> removeLocalHistory(int mediaId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'playback_history',
        where: 'anilist_media_id = ?',
        whereArgs: [mediaId],
      );
      await txn.insert(
        'continue_watching_dismissals',
        {
          'anilist_media_id': mediaId,
          'dismissed_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Set<int>> dismissedContinueWatchingIds() async {
    final db = await database;
    final rows = await db.query(
      'continue_watching_dismissals',
      columns: ['anilist_media_id'],
    );
    return rows.map((row) => row['anilist_media_id']! as int).toSet();
  }

  Future<SeriesPlaybackPreferences> seriesPreferences(int mediaId) async {
    final db = await database;
    final rows = await db.query(
      'series_preferences',
      columns: ['preferences_json'],
      where: 'anilist_media_id = ?',
      whereArgs: [mediaId],
      limit: 1,
    );
    if (rows.isEmpty) return const SeriesPlaybackPreferences();
    return SeriesPlaybackPreferences.fromJson(
      jsonDecode(rows.first['preferences_json']! as String)
          as Map<String, dynamic>,
    );
  }

  Future<void> saveSeriesPreferences(
    int mediaId,
    SeriesPlaybackPreferences preferences,
  ) async {
    final db = await database;
    await db.insert('series_preferences', {
      'anilist_media_id': mediaId,
      'preferences_json': jsonEncode(preferences.toJson()),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> recordStreamFailure({
    required String deviceKey,
    required String infoHash,
    required String reason,
  }) async {
    final db = await database;
    await db.rawInsert(
      '''
      INSERT INTO stream_failures
        (device_key, info_hash, reason, failure_count, last_failed_at)
      VALUES (?, ?, ?, 1, ?)
      ON CONFLICT(device_key, info_hash) DO UPDATE SET
        reason = excluded.reason,
        failure_count = failure_count + 1,
        last_failed_at = excluded.last_failed_at
      ''',
      [
        deviceKey,
        infoHash.toLowerCase(),
        reason,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<Map<String, int>> failureCounts(String deviceKey) async {
    final db = await database;
    final rows = await db.query(
      'stream_failures',
      columns: ['info_hash', 'failure_count'],
      where: 'device_key = ?',
      whereArgs: [deviceKey],
    );
    return {
      for (final row in rows)
        row['info_hash']! as String: row['failure_count']! as int,
    };
  }

  Future<void> recordPerformance(String name, Duration duration) async {
    final db = await database;
    await db.insert('performance_events', {
      'name': name,
      'duration_us': duration.inMicroseconds,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.delete(
      'performance_events',
      where:
          'id NOT IN (SELECT id FROM performance_events ORDER BY id DESC LIMIT 500)',
    );
  }

  Future<void> cacheJson(
    String key,
    Map<String, dynamic> payload, {
    Duration maxAge = const Duration(minutes: 30),
  }) async {
    final db = await database;
    final now = DateTime.now();
    await db.insert('catalog_cache', {
      'cache_key': key,
      'payload_json': jsonEncode(payload),
      'expires_at': now.add(maxAge).millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> cachedJson(
    String key, {
    bool allowExpired = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      'catalog_cache',
      where: allowExpired
          ? 'cache_key = ?'
          : 'cache_key = ? AND expires_at > ?',
      whereArgs: allowExpired
          ? [key]
          : [key, DateTime.now().millisecondsSinceEpoch],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['payload_json']! as String)
        as Map<String, dynamic>;
  }

  Future<Map<String, Object?>> diagnosticsSnapshot() async {
    final db = await database;
    final playback = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM playback_history'),
    );
    final failures = await db.rawQuery('''
      SELECT info_hash, reason, failure_count, last_failed_at
      FROM stream_failures ORDER BY last_failed_at DESC LIMIT 25
    ''');
    final timings = await db.rawQuery('''
      SELECT name, duration_us, created_at
      FROM performance_events ORDER BY created_at DESC LIMIT 100
    ''');
    return {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'playbackEntryCount': playback ?? 0,
      'recentStreamFailures': failures,
      'recentFrameTimings': timings,
    };
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _opening = null;
  }
}

Future<void> saveCheckpointTransaction(
  DatabaseExecutor database,
  PlaybackCheckpoint checkpoint,
) async {
  await database.delete(
    'continue_watching_dismissals',
    where: 'anilist_media_id = ?',
    whereArgs: [checkpoint.anilistMediaId],
  );
  await database.insert(
    'playback_history',
    checkpoint.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _createContinueDismissalsTable(DatabaseExecutor db) =>
    db.execute('''
  CREATE TABLE IF NOT EXISTS continue_watching_dismissals (
    anilist_media_id INTEGER PRIMARY KEY,
    dismissed_at INTEGER NOT NULL
  )
''');
