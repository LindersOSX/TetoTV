import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final webStreamAggregatorProvider = Provider<WebStreamAggregator>(
  (ref) => WebStreamAggregator(ref.watch(addonStoreProvider)),
);

class WebStreamAggregator {
  const WebStreamAggregator(this._store);

  final AddonStore _store;

  Future<WebStreamAggregation> search(EpisodeReference episode) async {
    final addons = (await _store.installedAddons())
        .where((addon) => addon.enabled && addon.manifest.isCompatible)
        .toList(growable: false);
    if (addons.isEmpty) return const WebStreamAggregation();
    return aggregateWebStreamingProviders(
      addons.map(SeanimeJavascriptProvider.new).toList(growable: false),
      episode,
    );
  }
}

Future<WebStreamAggregation> aggregateWebStreamingProviders(
  List<WebStreamingProvider> providers,
  EpisodeReference episode,
) async {
  final outcomes = await Future.wait(
    providers.map((provider) async {
      try {
        final streams = await provider.streams(episode);
        return (streams: streams, failure: null as WebProviderFailure?);
      } catch (error) {
        return (
          streams: const <WebStreamResult>[],
          failure: WebProviderFailure(
            providerName: provider.name,
            message: _shortMessage(error),
          ),
        );
      }
    }),
  );
  final unique = <String, WebStreamResult>{};
  final failures = <WebProviderFailure>[];
  for (final outcome in outcomes) {
    if (outcome.failure != null) failures.add(outcome.failure!);
    for (final stream in outcome.streams) {
      unique.putIfAbsent(stream.uri.toString(), () => stream);
    }
  }
  final streams = unique.values.toList()
    ..sort((a, b) {
      final provider = a.providerName.compareTo(b.providerName);
      return provider != 0 ? provider : a.title.compareTo(b.title);
    });
  return WebStreamAggregation(streams: streams, failures: failures);
}

String _shortMessage(Object error) {
  final value = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
  return value.length > 160 ? '${value.substring(0, 160)}…' : value;
}
