import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_playback_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const episode = EpisodeReference(
    anilistMediaId: 154587,
    title: 'Frieren',
    episode: 2,
    titleEnglish: 'Frieren: Beyond Journey’s End',
  );
  const release = ReleaseCandidate(
    infoHash: '0123456789abcdef0123456789abcdef01234567',
    magnetUri:
        'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=secret',
    releaseName: '[Group] Frieren - 02 [1080p]',
    seeders: 20,
    sourceId: 'nyaa',
    preferredFileIndex: 2,
    quality: '1080p',
  );

  test('engine generations reject stale progress and route commands', () async {
    final coordinator = WatchPartyPlaybackCoordinator(
      episode: episode,
      release: release,
    );
    addTearDown(coordinator.dispose);
    var mpvPlays = 0;
    var vlcPlays = 0;
    final mpv = coordinator.bindEngine(
      engine: 'mpv',
      play: () async => mpvPlays++,
      pause: () async {},
      seekTo: (_) async {},
    );
    final vlc = coordinator.bindEngine(
      engine: 'vlc',
      play: () async => vlcPlays++,
      pause: () async {},
      seekTo: (_) async {},
    );
    final samples = <Duration>[];
    final subscription = coordinator.snapshots.listen(
      (sample) => samples.add(sample.position),
    );
    addTearDown(subscription.cancel);

    coordinator.publish(
      mpv,
      position: const Duration(seconds: 5),
      duration: const Duration(minutes: 24),
      playing: true,
      ready: true,
    );
    coordinator.publish(
      vlc,
      position: const Duration(seconds: 6),
      duration: const Duration(minutes: 24),
      playing: true,
      ready: true,
    );
    await coordinator.play();

    expect(vlc.generation, greaterThan(mpv.generation));
    expect(samples, [const Duration(seconds: 6)]);
    expect(mpvPlays, 0);
    expect(vlcPlays, 1);
  });

  test('party media exposes only a digest, never playback capabilities', () {
    final coordinator = WatchPartyPlaybackCoordinator(
      episode: episode,
      release: release,
    );
    addTearDown(coordinator.dispose);

    final serialized = coordinator.media.toJson().toString();

    expect(coordinator.media.timelineFingerprint, hasLength(64));
    expect(serialized, isNot(contains('magnet:?')));
    expect(serialized, isNot(contains(release.infoHash)));
    expect(serialized, isNot(contains('secret')));
    expect(serialized, isNot(contains('headers')));
    expect(serialized, isNot(contains('stream_url')));
  });

  test('known duration contributes to the hashed timeline identity', () async {
    final coordinator = WatchPartyPlaybackCoordinator(
      episode: episode,
      release: release,
    );
    addTearDown(coordinator.dispose);
    final handle = coordinator.bindEngine(
      engine: 'mpv',
      play: () async {},
      pause: () async {},
      seekTo: (_) async {},
    );
    final sampleFuture = coordinator.snapshots.first;

    coordinator.publish(
      handle,
      position: Duration.zero,
      duration: const Duration(minutes: 24),
      playing: false,
      ready: true,
    );
    final sample = await sampleFuture;

    expect(
      sample.media.timelineFingerprint,
      isNot(coordinator.media.timelineFingerprint),
    );
  });

  test('private media publishes only a one-way timeline digest', () {
    const privateIdentity = 'server-token:item-42:https://private.example';
    final coordinator = WatchPartyPlaybackCoordinator.privateMedia(
      checkpointKey: 'local:0123456789abcdef',
      timelineIdentity: privateIdentity,
    );
    addTearDown(coordinator.dispose);

    final serialized = coordinator.media.toJson().toString();

    expect(coordinator.media.kind, 'private');
    expect(coordinator.media.title, 'Private media');
    expect(coordinator.media.timelineFingerprint, hasLength(64));
    expect(serialized, isNot(contains(privateIdentity)));
    expect(serialized, isNot(contains('server-token')));
    expect(serialized, isNot(contains('https://')));
    expect(serialized, isNot(contains('headers')));
  });
}
