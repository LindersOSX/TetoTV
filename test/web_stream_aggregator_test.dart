import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a failed provider does not hide another provider result', () async {
    const episode = EpisodeReference(
      anilistMediaId: 1,
      title: 'Test',
      episode: 2,
    );
    final result = await aggregateWebStreamingProviders([
      _FakeProvider('broken', 'Broken', () => throw StateError('offline')),
      _FakeProvider(
        'working',
        'Working',
        () async => [
          WebStreamResult(
            providerId: 'working',
            providerName: 'Working',
            title: '1080p',
            uri: Uri.parse('https://cdn.example.com/video.m3u8'),
          ),
        ],
      ),
    ], episode);

    expect(result.streams, hasLength(1));
    expect(result.streams.single.providerName, 'Working');
    expect(result.failures, hasLength(1));
    expect(result.failures.single.providerName, 'Broken');
  });

  test('duplicate stream URLs are collapsed across providers', () async {
    final stream = WebStreamResult(
      providerId: 'one',
      providerName: 'One',
      title: 'Auto',
      uri: Uri.parse('https://cdn.example.com/video.m3u8'),
    );
    final result = await aggregateWebStreamingProviders([
      _FakeProvider('one', 'One', () async => [stream]),
      _FakeProvider('two', 'Two', () async => [stream]),
    ], const EpisodeReference(anilistMediaId: 1, title: 'Test', episode: 1));

    expect(result.streams, hasLength(1));
  });
}

class _FakeProvider implements WebStreamingProvider {
  const _FakeProvider(this.id, this.name, this.callback);

  @override
  final String id;
  @override
  final String name;
  final Future<List<WebStreamResult>> Function() callback;

  @override
  Future<List<WebStreamResult>> streams(EpisodeReference episode) => callback();
}
