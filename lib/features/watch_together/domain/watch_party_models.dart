import 'package:flutter/foundation.dart';

enum WatchPartyRole { host, guest }

@immutable
class WatchPartyMedia {
  const WatchPartyMedia({
    required this.kind,
    required this.title,
    this.anilistId,
    this.episode,
    this.titleEnglish,
    this.titleRomaji,
    this.year,
    this.coverUrl,
    this.timelineFingerprint,
  });

  final String kind;
  final String title;
  final int? anilistId;
  final int? episode;
  final String? titleEnglish;
  final String? titleRomaji;
  final int? year;
  final String? coverUrl;
  final String? timelineFingerprint;

  bool get isCatalogEpisode =>
      kind == 'anilist' && anilistId != null && episode != null;

  Map<String, Object> toJson() {
    final value = <String, Object>{'kind': kind, 'title': title};
    void add(String key, Object? item) {
      if (item != null) value[key] = item;
    }

    add('anilist_id', anilistId);
    add('episode', episode);
    add('title_english', titleEnglish);
    add('title_romaji', titleRomaji);
    add('year', year);
    add('cover_url', coverUrl);
    add('timeline_fingerprint', timelineFingerprint);
    return value;
  }

  factory WatchPartyMedia.fromJson(Map<String, Object?> value) =>
      WatchPartyMedia(
        kind: value['kind'] as String? ?? 'private',
        title: value['title'] as String? ?? 'Watch Together',
        anilistId: (value['anilist_id'] as num?)?.toInt(),
        episode: (value['episode'] as num?)?.toInt(),
        titleEnglish: value['title_english'] as String?,
        titleRomaji: value['title_romaji'] as String?,
        year: (value['year'] as num?)?.toInt(),
        coverUrl: value['cover_url'] as String?,
        timelineFingerprint: value['timeline_fingerprint'] as String?,
      );

  bool sameTimeline(WatchPartyMedia other) =>
      kind == other.kind &&
      anilistId == other.anilistId &&
      episode == other.episode &&
      (timelineFingerprint == null ||
          other.timelineFingerprint == null ||
          timelineFingerprint == other.timelineFingerprint);

  @override
  bool operator ==(Object other) =>
      other is WatchPartyMedia &&
      kind == other.kind &&
      title == other.title &&
      anilistId == other.anilistId &&
      episode == other.episode &&
      titleEnglish == other.titleEnglish &&
      titleRomaji == other.titleRomaji &&
      year == other.year &&
      coverUrl == other.coverUrl &&
      timelineFingerprint == other.timelineFingerprint;

  @override
  int get hashCode => Object.hash(
    kind,
    title,
    anilistId,
    episode,
    titleEnglish,
    titleRomaji,
    year,
    coverUrl,
    timelineFingerprint,
  );
}

@immutable
class WatchPartySnapshot {
  const WatchPartySnapshot({
    required this.roomCode,
    required this.role,
    required this.revision,
    required this.playing,
    required this.position,
    required this.effectiveAt,
    required this.serverTime,
    this.receivedAt,
    required this.participantCount,
    required this.readyCount,
    required this.expiresAt,
    this.media,
  });

  final String roomCode;
  final WatchPartyRole role;
  final int revision;
  final WatchPartyMedia? media;
  final bool playing;
  final Duration position;
  final DateTime effectiveAt;
  final DateTime serverTime;

  /// Local clock anchor captured when this snapshot was received.
  ///
  /// The server offset must remain fixed after receipt. Recomputing it from
  /// every later [localNow] pins server time to this snapshot and repeatedly
  /// seeks a playing guest backward.
  final DateTime? receivedAt;
  final int participantCount;
  final int readyCount;
  final DateTime expiresAt;

  Duration expectedPositionAt(DateTime localNow) {
    final clockOffset = serverTime.difference(receivedAt ?? serverTime);
    final serverNow = localNow.add(clockOffset);
    final elapsed = playing ? serverNow.difference(effectiveAt) : Duration.zero;
    final value = position + elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  factory WatchPartySnapshot.fromJson(
    Map<String, Object?> value, {
    DateTime? receivedAt,
  }) {
    final media = value['media'];
    return WatchPartySnapshot(
      roomCode: value['room_code'] as String? ?? '',
      role: value['role'] == 'host'
          ? WatchPartyRole.host
          : WatchPartyRole.guest,
      revision: (value['revision'] as num?)?.toInt() ?? 0,
      media: media is Map
          ? WatchPartyMedia.fromJson(
              media.map((key, value) => MapEntry(key.toString(), value)),
            )
          : null,
      playing: value['playing'] as bool? ?? false,
      position: Duration(
        milliseconds: (value['position_ms'] as num?)?.toInt() ?? 0,
      ),
      effectiveAt: DateTime.fromMillisecondsSinceEpoch(
        (value['effective_at_ms'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      serverTime: DateTime.fromMillisecondsSinceEpoch(
        (value['server_time_ms'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      receivedAt: (receivedAt ?? DateTime.now()).toUtc(),
      participantCount: (value['participant_count'] as num?)?.toInt() ?? 0,
      readyCount: (value['ready_count'] as num?)?.toInt() ?? 0,
      expiresAt:
          DateTime.tryParse(value['expires_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

@immutable
class WatchPartySession {
  const WatchPartySession({
    required this.roomCode,
    required this.token,
    required this.role,
    required this.expiresAt,
    required this.watchUrl,
  });

  final String roomCode;
  final String token;
  final WatchPartyRole role;
  final DateTime expiresAt;
  final Uri watchUrl;
}

@immutable
class WatchPartyPlaybackSample {
  const WatchPartyPlaybackSample({
    required this.media,
    required this.position,
    required this.duration,
    required this.playing,
    required this.ready,
    required this.sampledAt,
  });

  final WatchPartyMedia media;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool ready;
  final DateTime sampledAt;
}

abstract interface class WatchPartyPlaybackPort {
  Stream<WatchPartyPlaybackSample> get snapshots;

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);
}
