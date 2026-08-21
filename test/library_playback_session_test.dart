import 'dart:async';

import 'package:anime_tv/features/player/application/library_playback_session.dart';
import 'package:anime_tv/features/player/domain/library_playback_request.dart';
import 'package:anime_tv/features/player/presentation/library_tv_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library request is isolated from every anime-only side effect', () {
    final request = _request();

    expect(request.isolation.animeTrackingEnabled, isFalse);
    expect(request.isolation.animeCheckpointEnabled, isFalse);
    expect(request.isolation.aniSkipEnabled, isFalse);
    expect(request.isolation.fillerNavigationEnabled, isFalse);
    expect(request.isolation.nextEpisodeEnabled, isFalse);

    final launch = libraryPlaybackLaunchForRequest(request);
    expect(launch.episode.anilistMediaId, 0);
    expect(launch.episode.malMediaId, isNull);
    expect(launch.selectedRelease.magnetUri, isEmpty);
    expect(launch.alternatives, isEmpty);
    expect(launch.directAlternatives, isEmpty);
  });

  test('only header-free HTTP sources allow cross-engine handoff', () {
    final local = _request(
      source: Uri.parse('content://media/external/video/media/7'),
    );
    final authenticatedServer = _request(
      source: Uri.parse('https://media.example/video/7'),
    );
    final publicServer = _request(
      source: Uri.parse('https://media.example/public/7'),
      headers: const {},
    );

    expect(local.allowsFlutterEngines, isFalse);
    expect(authenticatedServer.allowsFlutterEngines, isFalse);
    expect(publicServer.allowsFlutterEngines, isTrue);
    expect(
      () => _request(source: Uri.parse('file:///storage/emulated/0/a.mkv')),
      throwsArgumentError,
    );
  });

  test(
    'slow progress callbacks keep only one in-flight and latest pending',
    () async {
      final firstCallbackGate = Completer<void>();
      final delivered = <Duration>[];
      LibraryPlaybackResult? finished;
      final request = _request(
        onProgress: (progress) async {
          delivered.add(progress.position);
          if (delivered.length == 1) await firstCallbackGate.future;
        },
        onFinished: (result) => finished = result,
      );
      final session = LibraryPlaybackSession(request);
      final sampledAt = DateTime.utc(2026, 8, 20, 12);

      session.report(
        position: Duration.zero,
        duration: const Duration(minutes: 20),
        playing: true,
        sampledAt: sampledAt,
        force: true,
      );
      for (var second = 1; second <= 40; second++) {
        session.report(
          position: Duration(seconds: second),
          duration: const Duration(minutes: 20),
          playing: true,
          sampledAt: sampledAt.add(Duration(seconds: second)),
          force: true,
        );
      }
      session.markCompleted(
        position: const Duration(seconds: 40),
        duration: const Duration(seconds: 40),
      );
      final finishing = session.finish();
      await Future<void>.delayed(Duration.zero);

      expect(delivered, [Duration.zero]);
      expect(finished, isNull);

      firstCallbackGate.complete();
      await finishing;

      expect(delivered, [Duration.zero, const Duration(seconds: 40)]);
      expect(finished?.completed, isTrue);
      expect(finished?.position, const Duration(seconds: 40));
      expect(finished?.started, isTrue);
    },
  );

  test('player start is delivered once and before queued progress', () async {
    final startGate = Completer<void>();
    final events = <String>[];
    final request = _request(
      onStarted: (position) async {
        events.add('start:${position.inSeconds}');
        await startGate.future;
      },
      onProgress: (progress) {
        events.add('progress:${progress.position.inSeconds}');
      },
    );
    final session = LibraryPlaybackSession(request);

    expect(events, isEmpty, reason: 'constructing a request is not playback');
    session.report(
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 20),
      playing: true,
      force: true,
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, ['start:0']);
    startGate.complete();
    await session.start();
    await session.finish();

    expect(events.first, 'start:0');
    expect(events.where((event) => event.startsWith('start:')), ['start:0']);
    expect(
      events.skip(1),
      isNotEmpty,
      reason: 'the final checkpoint may intentionally repeat the last sample',
    );
    expect(events.skip(1), everyElement('progress:12'));
  });

  test('finish before a playback sample skips remote lifecycle', () async {
    final events = <String>[];
    LibraryPlaybackResult? finished;
    final session = LibraryPlaybackSession(
      _request(
        onStarted: (_) => events.add('started'),
        onFinished: (result) {
          events.add('finished');
          finished = result;
        },
      ),
    );

    await session.finish();

    expect(events, ['finished']);
    expect(finished?.started, isFalse);
    expect(finished?.reason, LibraryPlaybackEndReason.exited);
  });
}

LibraryPlaybackRequest _request({
  Uri? source,
  Map<String, String> headers = const {'Authorization': 'secret-token'},
  LibraryPlaybackStartedCallback? onStarted,
  LibraryPlaybackProgressCallback? onProgress,
  LibraryPlaybackFinishedCallback? onFinished,
}) => LibraryPlaybackRequest(
  source: source ?? Uri.parse('https://media.example/video/7'),
  title: 'Private episode',
  releaseName: 'Private episode.mkv',
  streamLabel: 'Jellyfin',
  checkpointKey: 'local:0123456789abcdef',
  timelineIdentity: 'private-server-item-7',
  headers: headers,
  onStarted: onStarted,
  onProgress: onProgress,
  onFinished: onFinished,
);
