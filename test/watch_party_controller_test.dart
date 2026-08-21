import 'dart:async';

import 'package:anime_tv/features/watch_together/application/watch_party_controller.dart';
import 'package:anime_tv/features/watch_together/data/watch_party_client.dart';
import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('room codes normalize separators but accept only digits 2-9', () {
    expect(normalizeWatchPartyCode('2345-6789'), '23456789');
    expect(normalizeWatchPartyCode(' 2345 6789 '), '23456789');
    expect(normalizeWatchPartyCode('ABCD2345'), isNull);
    expect(normalizeWatchPartyCode('12345678'), isNull);
    expect(normalizeWatchPartyCode('short'), isNull);
    expect(
      watchPartyFriendlyError(
        const WatchPartyClientException('invalid_room_code'),
      ),
      'Enter the eight-digit room code using numbers 2-9 only.',
    );
  });

  test('client requires one root HTTPS origin', () {
    for (final value in const [
      'http://tetotv.example',
      'https://user:pass@tetotv.example',
      'https://tetotv.example/prefix',
      'https://tetotv.example?token=secret',
    ]) {
      expect(
        () => WatchPartyClient(baseUrl: value),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test('only an attached guest yields playback authority to the host', () {
    final guestLobby = WatchPartyState(session: _session(WatchPartyRole.guest));
    final attachedGuest = guestLobby.copyWith(attachedMedia: _media);
    final attachedHost = WatchPartyState(
      session: _session(WatchPartyRole.host),
      attachedMedia: _media,
    );

    expect(guestLobby.guestPlaybackControlsLocked, isFalse);
    expect(attachedGuest.guestPlaybackControlsLocked, isTrue);
    expect(attachedHost.guestPlaybackControlsLocked, isFalse);
    expect(const WatchPartyState().guestPlaybackControlsLocked, isFalse);
  });

  test(
    'client keeps the room capability in the Authorization header',
    () async {
      RequestOptions? recorded;
      final dio = Dio(BaseOptions(baseUrl: 'https://tetotv.example'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              recorded = options;
              handler.resolve(
                Response<Object?>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _snapshotJson(role: 'guest'),
                ),
              );
            },
          ),
        );
      final client = WatchPartyClient(
        baseUrl: 'https://tetotv.example',
        dio: dio,
      );
      final session = _session(WatchPartyRole.guest);

      final snapshot = await client.snapshot(session);

      expect(snapshot.roomCode, '23456789');
      expect(recorded?.path, '/v1/watch-parties/23456789');
      expect(recorded?.uri.query, isEmpty);
      expect(recorded?.headers['Authorization'], 'Bearer ${session.token}');
      expect(recorded?.data, isNull);
    },
  );

  test('client strips broker query data from the public room URL', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://tetotv.example'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 201,
              data: {
                'room_code': '23456789',
                'host_token': List.filled(48, 'a').join(),
                'expires_at': '2030-01-01T00:00:00Z',
                'watch_url':
                    '/watch?room=23456789&host_token=must-not-be-shared',
              },
            ),
          ),
        ),
      );
    final client = WatchPartyClient(
      baseUrl: 'https://tetotv.example',
      dio: dio,
    );

    final created = await client.create();

    expect(
      created.session.watchUrl.toString(),
      'https://tetotv.example/watch?room=23456789',
    );
    expect(created.session.watchUrl.queryParameters.keys, {'room'});
  });

  test(
    'host publishes public media identity but never a playback URL',
    () async {
      final client = _FakeWatchPartyClient();
      final controller = WatchPartyController(client);
      addTearDown(controller.dispose);
      expect(await controller.create(), isTrue);
      final port = _FakePlaybackPort();
      addTearDown(port.dispose);
      const media = WatchPartyMedia(
        kind: 'anilist',
        title: 'Frieren',
        anilistId: 154587,
        episode: 2,
        timelineFingerprint: 'abcdef0123456789',
      );
      await controller.attachPlayback(port: port, media: media);

      port.emit(
        WatchPartyPlaybackSample(
          media: media,
          position: const Duration(seconds: 31),
          duration: const Duration(minutes: 24),
          playing: true,
          ready: true,
          sampledAt: DateTime.now().toUtc(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(client.lastPublishedMedia, media);
      expect(
        client.lastPublishedMedia?.toJson(),
        isNot(contains('stream_url')),
      );
      expect(client.lastPublishedMedia?.toJson(), isNot(contains('headers')));
      expect(controller.state.snapshot?.playing, isTrue);
    },
  );

  test(
    'attached guest rejects local play but applies queued host play and seek',
    () async {
      final client = _FakeWatchPartyClient()
        ..joinSnapshot = _snapshot(
          role: WatchPartyRole.guest,
          revision: 4,
          playing: true,
          position: const Duration(seconds: 45),
          media: _media,
        );
      final controller = WatchPartyController(client);
      addTearDown(controller.dispose);
      expect(await controller.join('23456789'), isTrue);
      final port = _FakePlaybackPort();
      addTearDown(port.dispose);
      await controller.attachPlayback(port: port, media: _media);
      expect(controller.state.guestPlaybackControlsLocked, isTrue);
      if (!controller.state.guestPlaybackControlsLocked) {
        await port.play();
      }
      expect(port.playCalls, 0, reason: 'guest-local Play is rejected');
      expect(client.readyValues, [false]);
      port.emit(
        WatchPartyPlaybackSample(
          media: _media,
          position: const Duration(seconds: 4),
          duration: const Duration(minutes: 24),
          playing: false,
          ready: true,
          sampledAt: DateTime.now().toUtc(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(port.seekTargets.single, greaterThan(const Duration(seconds: 40)));
      expect(
        port.playCalls,
        1,
        reason: 'the coordinator-originated host Play bypasses the local lock',
      );
      expect(client.updateCalls, 0);
      expect(client.readyValues, [false, true]);
    },
  );

  test(
    'old episode readiness cannot control or ready a new host episode',
    () async {
      const oldMedia = WatchPartyMedia(
        kind: 'anilist',
        title: 'Frieren',
        anilistId: 154587,
        episode: 1,
      );
      final client = _FakeWatchPartyClient()
        ..joinSnapshot = _snapshot(
          role: WatchPartyRole.guest,
          revision: 7,
          playing: true,
          position: const Duration(seconds: 50),
          media: _media,
        );
      final controller = WatchPartyController(client);
      addTearDown(controller.dispose);
      expect(await controller.join('23456789'), isTrue);
      final port = _FakePlaybackPort();
      addTearDown(port.dispose);
      await controller.attachPlayback(port: port, media: oldMedia);

      port.emit(_readySample(media: oldMedia));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(client.readyValues, [false]);
      expect(client.remoteReady, isFalse);
      expect(port.seekTargets, isEmpty);
      expect(port.playCalls, 0);
      expect(controller.state.attachedMedia, oldMedia);
    },
  );

  test('guest reconciliation serializes duplicate playback samples', () async {
    final client = _FakeWatchPartyClient()
      ..joinSnapshot = _snapshot(
        role: WatchPartyRole.guest,
        revision: 9,
        playing: true,
        position: const Duration(seconds: 50),
        media: _media,
      );
    final controller = WatchPartyController(client);
    addTearDown(controller.dispose);
    expect(await controller.join('23456789'), isTrue);
    final seekGate = Completer<void>();
    final port = _FakePlaybackPort()..seekGate = seekGate;
    addTearDown(port.dispose);
    await controller.attachPlayback(port: port, media: _media);
    final behind = WatchPartyPlaybackSample(
      media: _media,
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 24),
      playing: false,
      ready: true,
      sampledAt: DateTime.now().toUtc(),
    );

    port.emit(behind);
    port.emit(behind);
    port.emit(behind);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(port.seekTargets, hasLength(1));
    expect(port.playCalls, 0);

    seekGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(port.seekTargets, hasLength(1));
    expect(port.playCalls, 1);
    expect(client.updateCalls, 0, reason: 'guests never echo host state');
  });

  test(
    'guest playback command failures are nonfatal and retry later',
    () async {
      final client = _FakeWatchPartyClient()
        ..joinSnapshot = _snapshot(
          role: WatchPartyRole.guest,
          revision: 12,
          playing: true,
          position: const Duration(seconds: 40),
          media: _media,
        );
      final controller = WatchPartyController(client);
      addTearDown(controller.dispose);
      expect(await controller.join('23456789'), isTrue);
      final port = _FakePlaybackPort()..seekError = StateError('decoder busy');
      addTearDown(port.dispose);
      await controller.attachPlayback(port: port, media: _media);
      final behind = WatchPartyPlaybackSample(
        media: _media,
        position: const Duration(seconds: 2),
        duration: const Duration(minutes: 24),
        playing: false,
        ready: true,
        sampledAt: DateTime.now().toUtc(),
      );

      port.emit(behind);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(port.seekTargets, hasLength(1));
      expect(port.playCalls, 0);
      expect(controller.state.message, contains('Retrying shortly'));

      await Future<void>.delayed(const Duration(milliseconds: 680));
      port.seekError = null;
      port.emit(behind);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(port.seekTargets, hasLength(2));
      expect(port.playCalls, 1);
      expect(client.updateCalls, 0, reason: 'a guest retry never echoes state');
    },
  );

  test(
    'website private room controls explicitly attached guest media',
    () async {
      const websiteMedia = WatchPartyMedia(
        kind: 'private',
        title: 'Private media',
      );
      final client = _FakeWatchPartyClient()
        ..joinSnapshot = _snapshot(
          role: WatchPartyRole.guest,
          revision: 14,
          playing: true,
          position: const Duration(seconds: 30),
          media: websiteMedia,
        );
      final controller = WatchPartyController(client);
      addTearDown(controller.dispose);
      expect(await controller.join('23456789'), isTrue);
      final port = _FakePlaybackPort();
      addTearDown(port.dispose);
      await controller.attachPlayback(port: port, media: _media);

      port.emit(
        WatchPartyPlaybackSample(
          media: _media,
          position: const Duration(seconds: 2),
          duration: const Duration(minutes: 24),
          playing: false,
          ready: true,
          sampledAt: DateTime.now().toUtc(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(port.seekTargets, hasLength(1));
      expect(port.playCalls, 1);
      expect(controller.state.timelineMismatch, isTrue);
      expect(controller.state.message, contains('same video as the host'));
      expect(client.updateCalls, 0);
    },
  );

  test('late playback detach is inert after controller disposal', () async {
    final controller = WatchPartyController(_FakeWatchPartyClient());
    final port = _FakePlaybackPort();
    addTearDown(port.dispose);
    await controller.attachPlayback(port: port, media: _media);

    controller.dispose();

    await expectLater(controller.detachPlayback(port), completes);
  });

  test('detach compensates for delayed guest ready attach', () async {
    final readyTrueGate = Completer<void>();
    final readyTrueStarted = Completer<void>();
    final client = _FakeWatchPartyClient()
      ..joinSnapshot = _snapshot(
        role: WatchPartyRole.guest,
        revision: 1,
        media: _media,
      )
      ..readyTrueGate = readyTrueGate
      ..readyTrueStarted = readyTrueStarted;
    final controller = WatchPartyController(client);
    addTearDown(controller.dispose);
    expect(await controller.join('23456789'), isTrue);
    final port = _FakePlaybackPort();
    addTearDown(port.dispose);

    await controller.attachPlayback(port: port, media: _media);
    port.emit(_readySample(media: _media));
    await readyTrueStarted.future;
    final detach = controller.detachPlayback(port);
    await Future<void>.delayed(Duration.zero);

    expect(client.readyCompletionOrder, [false]);
    readyTrueGate.complete();
    await detach;

    expect(client.readyValues, [false, true, false]);
    expect(client.readyCompletionOrder, [false, true, false]);
    expect(client.remoteReady, isFalse);
    expect(controller.state.attachedMedia, isNull);
  });

  test('dispose compensates for delayed guest ready attach', () async {
    final readyTrueGate = Completer<void>();
    final readyTrueStarted = Completer<void>();
    final readyFalseCompleted = Completer<void>();
    final client = _FakeWatchPartyClient()
      ..joinSnapshot = _snapshot(
        role: WatchPartyRole.guest,
        revision: 1,
        media: _media,
      )
      ..readyTrueGate = readyTrueGate
      ..readyTrueStarted = readyTrueStarted;
    final controller = WatchPartyController(client);
    expect(await controller.join('23456789'), isTrue);
    final port = _FakePlaybackPort();
    addTearDown(port.dispose);

    await controller.attachPlayback(port: port, media: _media);
    port.emit(_readySample(media: _media));
    await readyTrueStarted.future;
    client.readyFalseCompleted = readyFalseCompleted;
    controller.dispose();
    readyTrueGate.complete();

    await readyFalseCompleted.future.timeout(const Duration(seconds: 1));
    expect(client.readyValues, [false, true, false]);
    expect(client.readyCompletionOrder, [false, true, false]);
    expect(client.remoteReady, isFalse);
  });

  test('detach cancels an attachment before its port is installed', () async {
    final controller = WatchPartyController(_FakeWatchPartyClient());
    addTearDown(controller.dispose);
    final cancelGate = Completer<void>();
    final previousPort = _FakePlaybackPort(cancelGate: cancelGate);
    final pendingPort = _FakePlaybackPort();
    addTearDown(previousPort.dispose);
    addTearDown(pendingPort.dispose);
    await controller.attachPlayback(port: previousPort, media: _media);

    final attach = controller.attachPlayback(port: pendingPort, media: _media);
    await Future<void>.delayed(Duration.zero);
    final detach = controller.detachPlayback(pendingPort);
    cancelGate.complete();
    await Future.wait([attach, detach]);

    expect(controller.state.attachedMedia, isNull);
  });

  test('snapshot calculates host position with server clock offset', () {
    final snapshot = _snapshot(
      role: WatchPartyRole.guest,
      playing: true,
      position: const Duration(seconds: 10),
      effectiveAt: DateTime.utc(2026, 8, 20, 12),
      serverTime: DateTime.utc(2026, 8, 20, 12, 0, 2),
      receivedAt: DateTime.utc(2026, 8, 20, 11, 59, 57),
    );
    expect(
      snapshot.expectedPositionAt(DateTime.utc(2026, 8, 20, 11, 59, 57)),
      const Duration(seconds: 12),
    );
    expect(
      snapshot.expectedPositionAt(DateTime.utc(2026, 8, 20, 11, 59, 59)),
      const Duration(seconds: 14),
      reason: 'the host timeline advances after the snapshot is received',
    );
  });
}

const _media = WatchPartyMedia(
  kind: 'anilist',
  title: 'Frieren',
  anilistId: 154587,
  episode: 2,
);

WatchPartySession _session(WatchPartyRole role) => WatchPartySession(
  roomCode: '23456789',
  token: List.filled(43, 'a').join(),
  role: role,
  expiresAt: DateTime.utc(2026, 8, 21),
  watchUrl: Uri.parse('https://tetotv.example/watch?room=23456789'),
);

WatchPartySnapshot _snapshot({
  required WatchPartyRole role,
  int revision = 0,
  bool playing = false,
  Duration position = Duration.zero,
  WatchPartyMedia? media,
  DateTime? effectiveAt,
  DateTime? serverTime,
  DateTime? receivedAt,
}) => WatchPartySnapshot(
  roomCode: '23456789',
  role: role,
  revision: revision,
  media: media,
  playing: playing,
  position: position,
  effectiveAt: effectiveAt ?? DateTime.now().toUtc(),
  serverTime: serverTime ?? DateTime.now().toUtc(),
  receivedAt: receivedAt,
  participantCount: 1,
  readyCount: 1,
  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 6)),
);

WatchPartyPlaybackSample _readySample({required WatchPartyMedia media}) =>
    WatchPartyPlaybackSample(
      media: media,
      position: const Duration(seconds: 3),
      duration: const Duration(minutes: 24),
      playing: false,
      ready: true,
      sampledAt: DateTime.now().toUtc(),
    );

Map<String, Object?> _snapshotJson({required String role}) => {
  'room_code': '23456789',
  'role': role,
  'revision': 1,
  'media': null,
  'playing': false,
  'position_ms': 0,
  'effective_at_ms': 0,
  'server_time_ms': 0,
  'participant_count': 1,
  'ready_count': 0,
  'expires_at': '2026-08-21T00:00:00Z',
};

class _FakeWatchPartyClient extends WatchPartyClient {
  _FakeWatchPartyClient()
    : super(baseUrl: 'https://tetotv.example', dio: Dio());

  WatchPartySnapshot joinSnapshot = _snapshot(role: WatchPartyRole.guest);
  WatchPartyMedia? lastPublishedMedia;
  int updateCalls = 0;
  final readyValues = <bool>[];
  final readyCompletionOrder = <bool>[];
  bool remoteReady = false;
  Completer<void>? readyTrueGate;
  Completer<void>? readyTrueStarted;
  Completer<void>? readyFalseCompleted;

  @override
  Future<WatchPartyCreated> create() async =>
      WatchPartyCreated(session: _session(WatchPartyRole.host));

  @override
  Future<WatchPartyJoined> join(String rawCode) async => WatchPartyJoined(
    session: _session(WatchPartyRole.guest),
    snapshot: joinSnapshot,
  );

  @override
  Future<WatchPartySnapshot> snapshot(WatchPartySession session) async =>
      session.role == WatchPartyRole.host
      ? _snapshot(role: WatchPartyRole.host)
      : joinSnapshot;

  @override
  Future<WatchPartySnapshot> updateState({
    required WatchPartySession session,
    required int baseRevision,
    required WatchPartyMedia? media,
    required bool playing,
    required Duration position,
  }) async {
    updateCalls += 1;
    lastPublishedMedia = media;
    return _snapshot(
      role: WatchPartyRole.host,
      revision: baseRevision + 1,
      playing: playing,
      position: position,
      media: media,
    );
  }

  @override
  Future<WatchPartySnapshot> setReady({
    required WatchPartySession session,
    required bool ready,
  }) async {
    readyValues.add(ready);
    if (ready) {
      final started = readyTrueStarted;
      if (started != null && !started.isCompleted) started.complete();
      await readyTrueGate?.future;
    }
    remoteReady = ready;
    readyCompletionOrder.add(ready);
    if (!ready) {
      final completed = readyFalseCompleted;
      if (completed != null && !completed.isCompleted) completed.complete();
    }
    return joinSnapshot;
  }

  @override
  Future<void> leave(WatchPartySession session) async {}
}

class _FakePlaybackPort implements WatchPartyPlaybackPort {
  _FakePlaybackPort({this.cancelGate}) {
    _controller = StreamController<WatchPartyPlaybackSample>.broadcast(
      onCancel: () => cancelGate?.future,
    );
  }

  final Completer<void>? cancelGate;
  late final StreamController<WatchPartyPlaybackSample> _controller;
  final seekTargets = <Duration>[];
  int playCalls = 0;
  int pauseCalls = 0;
  Completer<void>? seekGate;
  Object? seekError;

  @override
  Stream<WatchPartyPlaybackSample> get snapshots => _controller.stream;

  void emit(WatchPartyPlaybackSample sample) => _controller.add(sample);

  @override
  Future<void> pause() async => pauseCalls += 1;

  @override
  Future<void> play() async => playCalls += 1;

  @override
  Future<void> seekTo(Duration position) async {
    seekTargets.add(position);
    if (seekError case final error?) throw error;
    await seekGate?.future;
  }

  void dispose() => unawaited(_controller.close());
}
