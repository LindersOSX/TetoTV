import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_controller.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_media_follower.dart';
import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same attached episode never navigates', () {
    final planner = WatchPartyGuestMediaFollowPlanner();
    final state = _guestState(
      revision: 4,
      media: _media(anilistId: 100, episode: 2),
      attachedMedia: _media(anilistId: 100, episode: 2),
    );

    expect(planner.evaluate(state), isNull);
    expect(
      planner.evaluate(_copyState(state, revision: 5, playing: true)),
      isNull,
    );
  });

  test('new episode navigates once despite repeated playback revisions', () {
    final planner = WatchPartyGuestMediaFollowPlanner();
    const nativeSession = WatchPartyNativePlayerSession(
      checkpointKey: '100:1',
      playbackSessionGeneration: 7,
    );
    final initial = _guestState(
      revision: 10,
      media: _media(anilistId: 100, episode: 2),
      attachedMedia: _media(anilistId: 100, episode: 1),
    );

    final request = planner.evaluate(
      initial,
      nativePlayerSession: nativeSession,
    );
    expect(request?.anilistId, 100);
    expect(request?.episode, 2);
    expect(request?.nativePlayerSession, same(nativeSession));
    expect(planner.evaluate(initial), isNull);
    expect(
      planner.evaluate(_copyState(initial, revision: 11, playing: true)),
      isNull,
    );
  });

  test('rapid E2 to E3 queue keeps only newest revision', () {
    final planner = WatchPartyGuestMediaFollowPlanner();
    final queue = WatchPartyMediaFollowQueue();
    final e2 = planner.evaluate(
      _guestState(
        revision: 20,
        media: _media(anilistId: 100, episode: 2),
        attachedMedia: _media(anilistId: 100, episode: 1),
      ),
    );
    final e3 = planner.evaluate(
      _guestState(
        revision: 21,
        media: _media(anilistId: 100, episode: 3),
        attachedMedia: _media(anilistId: 100, episode: 1),
      ),
    );

    queue.add(e2!);
    queue.add(e3!);
    expect(queue.hasPending, isTrue);
    expect(queue.takeLatest()?.episode, 3);
    expect(queue.hasPending, isFalse);
    expect(queue.takeLatest(), isNull);
  });

  test('different catalog show produces a bounded autoplay resolver route', () {
    final planner = WatchPartyGuestMediaFollowPlanner();
    final request = planner.evaluate(
      _guestState(
        revision: 30,
        media: _media(anilistId: 222, episode: 7),
        attachedMedia: _media(anilistId: 111, episode: 7),
      ),
      affinity: const WatchPartyPlaybackAffinity(
        preferredProvider: ' Provider\nName ',
        preferredAuthor: 'group',
        preferredSourceId: 'source',
        preferredWebProviderId: 'web-provider',
        preferredQualityHeight: 1080,
        preferredAudio: PlaybackAudioPreference.dub,
      ),
    );

    final uri = Uri.parse(request!.location);
    expect(uri.path, '/resolve');
    expect(uri.queryParameters['anilistId'], '222');
    expect(uri.queryParameters['episode'], '7');
    expect(uri.queryParameters['autoplay'], '1');
    expect(uri.queryParameters['watchPartyFollow'], '1');
    expect(uri.queryParameters['preferredProvider'], 'Provider Name');
    expect(uri.queryParameters['preferredQualityHeight'], '1080');
    expect(uri.queryParameters['preferredAudio'], 'dub');
  });

  test('private and local media can never trigger automatic routing', () {
    final planner = WatchPartyGuestMediaFollowPlanner();
    expect(
      planner.evaluate(
        _guestState(
          revision: 1,
          media: const WatchPartyMedia(
            kind: 'private',
            title: 'Private media',
            timelineFingerprint: 'opaque',
          ),
        ),
      ),
      isNull,
    );

    expect(
      planner.evaluate(
        _guestState(
          revision: 2,
          media: _media(anilistId: 100, episode: 2),
          attachedMedia: const WatchPartyMedia(
            kind: 'private',
            title: 'Local file',
            timelineFingerprint: 'opaque-local',
          ),
        ),
      ),
      isNull,
    );
  });

  test(
    'route contains public catalog metadata but no room capability data',
    () {
      const media = WatchPartyMedia(
        kind: 'anilist',
        title: 'Safe Show',
        anilistId: 444,
        episode: 9,
        coverUrl: 'https://images.example/cover.jpg',
        timelineFingerprint: 'must-not-leak',
      );
      final request = WatchPartyGuestMediaFollowPlanner().evaluate(
        _guestState(revision: 8, media: media),
      );

      expect(request, isNotNull);
      expect(request!.location, isNot(contains('must-not-leak')));
      expect(request.location, isNot(contains('guest-token')));
      expect(request.location, isNot(contains('24682468')));
      expect(request.location, isNot(contains('roomCode')));
      expect(
        Uri.parse(request.location).queryParameters['cover'],
        media.coverUrl,
      );
    },
  );

  test('stale media revision cannot replace a newer target', () {
    final planner = WatchPartyGuestMediaFollowPlanner();
    final session = _guestSession();
    expect(
      planner
          .evaluate(
            _guestState(
              revision: 42,
              media: _media(anilistId: 100, episode: 3),
              session: session,
            ),
          )
          ?.episode,
      3,
    );
    expect(
      planner.evaluate(
        _guestState(
          revision: 41,
          media: _media(anilistId: 100, episode: 2),
          session: session,
        ),
      ),
      isNull,
    );
  });
}

WatchPartyState _guestState({
  required int revision,
  required WatchPartyMedia media,
  WatchPartyMedia? attachedMedia,
  bool playing = false,
  WatchPartySession? session,
}) {
  final now = DateTime.utc(2026, 8, 20);
  return WatchPartyState(
    connection: WatchPartyConnection.connected,
    session: session ?? _guestSession(),
    snapshot: WatchPartySnapshot(
      roomCode: '24682468',
      role: WatchPartyRole.guest,
      revision: revision,
      playing: playing,
      position: const Duration(seconds: 15),
      effectiveAt: now,
      serverTime: now,
      receivedAt: now,
      participantCount: 2,
      readyCount: 1,
      expiresAt: now.add(const Duration(hours: 1)),
      media: media,
    ),
    attachedMedia: attachedMedia,
  );
}

WatchPartySession _guestSession() {
  final now = DateTime.utc(2026, 8, 20);
  return WatchPartySession(
    roomCode: '24682468',
    token: 'guest-token',
    role: WatchPartyRole.guest,
    expiresAt: now.add(const Duration(hours: 1)),
    watchUrl: Uri.parse('https://watch.example/watch?room=24682468'),
  );
}

WatchPartyState _copyState(
  WatchPartyState value, {
  required int revision,
  bool? playing,
}) {
  final snapshot = value.snapshot!;
  return value.copyWith(
    snapshot: WatchPartySnapshot(
      roomCode: snapshot.roomCode,
      role: snapshot.role,
      revision: revision,
      playing: playing ?? snapshot.playing,
      position: snapshot.position,
      effectiveAt: snapshot.effectiveAt,
      serverTime: snapshot.serverTime,
      receivedAt: snapshot.receivedAt,
      participantCount: snapshot.participantCount,
      readyCount: snapshot.readyCount,
      expiresAt: snapshot.expiresAt,
      media: snapshot.media,
    ),
  );
}

WatchPartyMedia _media({required int anilistId, required int episode}) =>
    WatchPartyMedia(
      kind: 'anilist',
      title: 'Show $anilistId',
      anilistId: anilistId,
      episode: episode,
      year: 2026,
    );
