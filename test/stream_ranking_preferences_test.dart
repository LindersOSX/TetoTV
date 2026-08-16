import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_ranking_preferences.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReleaseCandidate release({
    required String id,
    required String quality,
    required int seeders,
    required String size,
    bool dubbed = true,
    String? name,
  }) => ReleaseCandidate(
    infoHash: id.padRight(40, id),
    magnetUri: 'magnet:?xt=urn:btih:${id.padRight(40, id)}',
    releaseName: name ?? '$quality release $id',
    seeders: seeders,
    sourceId: 'source',
    quality: quality,
    sizeLabel: size,
    isDubbed: dubbed,
  );

  WebStreamResult web({
    required String id,
    required String quality,
    bool dubbed = true,
  }) => WebStreamResult(
    providerId: 'provider-$id',
    providerName: 'Provider $id',
    title: '$quality stream $id',
    uri: Uri.parse('https://example.com/$id.m3u8'),
    quality: quality,
    isDubbed: dubbed,
  );

  test(
    'debrid modes rank quality, seeders, and known size deterministically',
    () {
      final small1080 = release(
        id: 'a',
        quality: '1080p',
        seeders: 50,
        size: '800 MB',
      );
      final large4k = release(id: 'b', quality: '4K', seeders: 2, size: '8 GB');
      final popular720 = release(
        id: 'c',
        quality: '720p',
        seeders: 500,
        size: '1.5 GB',
      );
      final candidates = [small1080, large4k, popular720];

      expect(
        rankReleaseCandidates(
          candidates,
          sort: DebridStreamSort.bestQuality,
          preferredAudio: PlaybackAudioPreference.dub,
        ).first,
        same(large4k),
      );
      expect(
        rankReleaseCandidates(
          candidates,
          sort: DebridStreamSort.mostSeeded,
          preferredAudio: PlaybackAudioPreference.dub,
        ).first,
        same(popular720),
      );
      expect(
        rankReleaseCandidates(
          candidates,
          sort: DebridStreamSort.largestSize,
          preferredAudio: PlaybackAudioPreference.dub,
        ).first,
        same(large4k),
      );
      expect(
        rankReleaseCandidates(
          candidates,
          sort: DebridStreamSort.smallestSize,
          preferredAudio: PlaybackAudioPreference.dub,
        ).first,
        same(small1080),
      );
    },
  );

  test('unknown release sizes stay after known sizes in either size mode', () {
    final known = release(id: 'a', quality: '720p', seeders: 1, size: '700 MB');
    final unknown = release(
      id: 'b',
      quality: '4K',
      seeders: 999,
      size: 'Unknown',
    );

    for (final mode in [
      DebridStreamSort.largestSize,
      DebridStreamSort.smallestSize,
    ]) {
      expect(
        rankReleaseCandidates(
          [unknown, known],
          sort: mode,
          preferredAudio: PlaybackAudioPreference.dub,
        ),
        [known, unknown],
      );
    }
  });

  test('audio safety remains ahead of every debrid ranking preference', () {
    final dub = release(id: 'd', quality: '480p', seeders: 1, size: '200 MB');
    final sub = release(
      id: 's',
      quality: '4K',
      seeders: 10000,
      size: '20 GB',
      dubbed: false,
    );

    for (final mode in DebridStreamSort.values) {
      expect(
        rankReleaseCandidates(
          [sub, dub],
          sort: mode,
          preferredAudio: PlaybackAudioPreference.dub,
        ).first,
        same(dub),
      );
    }
  });

  test(
    'preferred Web quality is exact-first without filtering alternatives',
    () {
      final p4k = web(id: '4k', quality: '2160p');
      final p1080 = web(id: '1080', quality: '1080p');
      final p720 = web(id: '720', quality: '720p');
      final ranked = rankWebStreamCandidates(
        [p4k, p720, p1080],
        quality: WebStreamQualityPreference.p1080,
        preferredAudio: PlaybackAudioPreference.dub,
      );

      expect(ranked.first, same(p1080));
      expect(ranked, hasLength(3));
    },
  );

  test('Web audio safety outranks a closer quality preference', () {
    final dub720 = web(id: 'dub', quality: '720p');
    final sub1080 = web(id: 'sub', quality: '1080p', dubbed: false);

    expect(
      rankWebStreamCandidates(
        [sub1080, dub720],
        quality: WebStreamQualityPreference.p1080,
        preferredAudio: PlaybackAudioPreference.dub,
      ).first,
      same(dub720),
    );
  });

  test('source class preference is explicit and reversible', () {
    expect(
      compareStreamSourceClasses(
        StreamSourceClass.web,
        StreamSourceClass.debrid,
        StreamSourcePriority.webFirst,
      ),
      lessThan(0),
    );
    expect(
      compareStreamSourceClasses(
        StreamSourceClass.web,
        StreamSourceClass.debrid,
        StreamSourcePriority.debridFirst,
      ),
      greaterThan(0),
    );
    expect(
      compareStreamSourceClasses(
        StreamSourceClass.web,
        StreamSourceClass.debrid,
        StreamSourcePriority.webFirst,
        leftAudioRank: 2,
        rightAudioRank: 0,
      ),
      greaterThan(0),
      reason: 'source priority cannot override the preferred audio class',
    );
  });
}
