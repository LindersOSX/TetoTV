import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/marketplace/data/public_https_dio.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';

abstract interface class WebStreamingProvider {
  String get id;
  String get name;
  Future<List<WebStreamResult>> streams(
    EpisodeReference episode, {
    WebProviderCancellation? cancellation,
  });
}

class WebProviderSearchCancelled implements Exception {
  const WebProviderSearchCancelled();

  @override
  String toString() => 'Web provider search cancelled.';
}

/// Cooperative cancellation shared by the provider worker pool and the
/// isolate-backed Seanime runtime. Listeners run synchronously so navigation
/// can request a graceful QuickJS shutdown before another screen starts
/// discovery.
class WebProviderCancellation {
  final Set<void Function()> _listeners = {};
  final Completer<void> _cancelledSignal = Completer<void>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _cancelledSignal.future;

  void throwIfCancelled() {
    if (_cancelled) throw const WebProviderSearchCancelled();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelledSignal.complete();
    final listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void Function() addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

class SeanimeJavascriptProvider implements WebStreamingProvider {
  const SeanimeJavascriptProvider(this.addon);

  static Future<String>? _domRuntimeSource;

  final InstalledStreamingAddon addon;

  @override
  String get id => addon.manifest.id;

  @override
  String get name => addon.manifest.name;

  @override
  Future<List<WebStreamResult>> streams(
    EpisodeReference episode, {
    WebProviderCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final domRuntime = await (_domRuntimeSource ??= rootBundle.loadString(
      'assets/addon_runtime/linkedom.js',
      cache: true,
    ));
    cancellation?.throwIfCancelled();
    final raw = await _runProviderIsolate(
      {
        'id': addon.manifest.id,
        'name': addon.manifest.name,
        'payload': addon.payload,
        'domRuntime': domRuntime,
        'title': episode.title,
        'titles': episode.alternativeTitles,
        'episode': episode.episode,
        'anilistId': episode.anilistMediaId,
        'malId': episode.malMediaId,
        'year': episode.year,
      },
      timeout: const Duration(seconds: 19),
      cancellation: cancellation,
    );
    cancellation?.throwIfCancelled();
    final expandedRaw = await _expandHlsVariants(raw, cancellation);
    cancellation?.throwIfCancelled();
    final results = <WebStreamResult>[];
    final publicHosts = <String, bool>{};
    Future<bool> allowed(Uri uri) async {
      cancellation?.throwIfCancelled();
      final known = publicHosts[uri.host];
      if (known != null) return known;
      try {
        await validatePublicNetworkTarget(uri);
        cancellation?.throwIfCancelled();
        publicHosts[uri.host] = true;
        return true;
      } catch (_) {
        publicHosts[uri.host] = false;
        return false;
      }
    }

    for (final item in expandedRaw) {
      cancellation?.throwIfCancelled();
      final uri = safePublicHttpsUri(item['url']);
      if (uri == null || !await allowed(uri)) continue;
      final candidateSubtitle = safePublicHttpsUri(item['subtitleUrl']);
      final subtitle =
          candidateSubtitle != null && await allowed(candidateSubtitle)
          ? candidateSubtitle
          : null;
      final headers = sanitizeAddonHeaders(
        item['headers'],
        maximumValueLength: 1024,
      );
      results.add(
        WebStreamResult(
          providerId: id,
          providerName: name,
          title: '${item['title'] ?? name}',
          uri: uri,
          quality: item['quality']?.toString(),
          headers: headers,
          subtitleUri: subtitle,
          subtitleLanguage: item['subtitleLanguage'] as String?,
          isDubbed: item['isDubbed'] == true,
        ),
      );
    }
    if (results.isEmpty && raw.isNotEmpty) {
      throw StateError(
        'NO_STREAM: Provider streams failed URL or network safety validation.',
      );
    }
    return results;
  }
}

bool isSeanimeProviderNoMatch(Object error) =>
    error.toString().contains('NO_MATCH:');

class HlsStreamVariant {
  const HlsStreamVariant({
    required this.uri,
    required this.quality,
    this.bandwidth,
  });

  final Uri uri;
  final String quality;
  final int? bandwidth;
}

List<HlsStreamVariant> parseHlsMasterPlaylist(String source, Uri masterUri) {
  if (!source.contains('#EXT-X-STREAM-INF')) return const [];
  final lines = const LineSplitter().convert(source);
  final variants = <String, HlsStreamVariant>{};
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
    final attributes = _hlsAttributes(
      line.substring('#EXT-X-STREAM-INF:'.length),
    );
    String? location;
    while (++index < lines.length) {
      final candidate = lines[index].trim();
      if (candidate.isEmpty) continue;
      if (candidate.startsWith('#')) break;
      location = candidate;
      break;
    }
    if (location == null) continue;
    final uri = safePublicHttpsUri(masterUri.resolve(location).toString());
    if (uri == null) continue;
    final resolution = attributes['RESOLUTION'];
    final height = resolution == null
        ? null
        : int.tryParse(resolution.split('x').last);
    final bandwidth = int.tryParse(
      attributes['AVERAGE-BANDWIDTH'] ?? attributes['BANDWIDTH'] ?? '',
    );
    final name = attributes['NAME']?.trim();
    final quality = height != null && height > 0
        ? '${height}p'
        : name?.isNotEmpty == true
        ? name!
        : bandwidth != null
        ? '${(bandwidth / 1000000).toStringAsFixed(1)} Mbps'
        : 'Variant';
    variants.putIfAbsent(
      uri.toString(),
      () => HlsStreamVariant(uri: uri, quality: quality, bandwidth: bandwidth),
    );
    if (variants.length >= 20) break;
  }
  final result = variants.values.toList();
  result.sort((left, right) {
    final leftHeight = int.tryParse(
      RegExp(r'\d+').firstMatch(left.quality)?.group(0) ?? '',
    );
    final rightHeight = int.tryParse(
      RegExp(r'\d+').firstMatch(right.quality)?.group(0) ?? '',
    );
    final resolution = (rightHeight ?? 0).compareTo(leftHeight ?? 0);
    if (resolution != 0) return resolution;
    return (right.bandwidth ?? 0).compareTo(left.bandwidth ?? 0);
  });
  return result;
}

List<Map<String, dynamic>> expandHlsResultVariants(
  Map<String, dynamic> item,
  String playlist,
  Uri masterUri,
) {
  final title = '${item['title'] ?? 'Auto'}';
  return [
    for (final variant in parseHlsMasterPlaylist(playlist, masterUri))
      {
        ...item,
        'url': variant.uri.toString(),
        'quality': variant.quality,
        'title': _variantTitle(title, variant.quality),
      },
  ];
}

Map<String, String> _hlsAttributes(String value) {
  final result = <String, String>{};
  final expression = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
  for (final match in expression.allMatches(value)) {
    var attribute = match.group(2)?.trim() ?? '';
    if (attribute.length >= 2 &&
        attribute.startsWith('"') &&
        attribute.endsWith('"')) {
      attribute = attribute.substring(1, attribute.length - 1);
    }
    result[match.group(1)!] = attribute;
  }
  return result;
}

Future<List<Map<String, dynamic>>> _expandHlsVariants(
  List<Map<String, dynamic>> raw,
  WebProviderCancellation? cancellation,
) async {
  final result = raw.toList(growable: true);
  final adaptive = raw.where(_isAdaptiveHlsCandidate).take(6).toList();
  for (var offset = 0; offset < adaptive.length; offset += 2) {
    cancellation?.throwIfCancelled();
    final end = (offset + 2).clamp(0, adaptive.length);
    final groups = await Future.wait(
      adaptive
          .sublist(offset, end)
          .map((item) => _hlsVariantsForItem(item, cancellation)),
    );
    for (final variants in groups) {
      result.addAll(variants);
    }
  }
  final unique = <String, Map<String, dynamic>>{};
  for (final item in result) {
    final url = '${item['url'] ?? ''}';
    final quality = '${item['quality'] ?? ''}';
    unique.putIfAbsent('$url|$quality', () => item);
  }
  return unique.values.take(120).toList(growable: false);
}

bool _isAdaptiveHlsCandidate(Map<String, dynamic> item) {
  final url = '${item['url'] ?? ''}'.toLowerCase();
  final quality = '${item['quality'] ?? item['title'] ?? ''}'.toLowerCase();
  return url.contains('.m3u8') &&
      (quality.isEmpty ||
          quality.contains('auto') ||
          quality.contains('adaptive') ||
          quality.contains('unknown'));
}

Future<List<Map<String, dynamic>>> _hlsVariantsForItem(
  Map<String, dynamic> item,
  WebProviderCancellation? cancellation,
) async {
  cancellation?.throwIfCancelled();
  final uri = safePublicHttpsUri(item['url']);
  if (uri == null) return const [];
  try {
    final response = await _safeAddonRequest(
      {
        'url': uri.toString(),
        'options': {
          'method': 'GET',
          'headers': item['headers'] is Map ? item['headers'] : const {},
        },
      },
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      overallTimeout: const Duration(seconds: 6),
      maximumResponseBytes: 512 * 1024,
      cancellation: cancellation,
    );
    final status = response['status'] as int? ?? 0;
    if (status < 200 || status >= 300) return const [];
    final effectiveHeaders = response['requestHeaders'];
    return expandHlsResultVariants(
      {...item, if (effectiveHeaders is Map) 'headers': effectiveHeaders},
      '${response['body'] ?? ''}',
      Uri.parse('${response['url'] ?? uri}'),
    );
  } catch (_) {
    // A media playlist, unavailable master, or failed variant lookup leaves
    // the original Auto stream intact and selectable.
    return const [];
  }
}

String _variantTitle(String original, String quality) {
  final auto = RegExp(r'\b(auto|adaptive|unknown)\b', caseSensitive: false);
  return auto.hasMatch(original)
      ? original.replaceFirst(auto, quality)
      : '$original / $quality';
}

Future<List<Map<String, dynamic>>> _runProviderIsolate(
  Map<String, Object?> input, {
  required Duration timeout,
  WebProviderCancellation? cancellation,
}) async {
  cancellation?.throwIfCancelled();
  final responses = ReceivePort();
  final errors = ReceivePort();
  final completed = Completer<List<Map<String, dynamic>>>();
  final isolateStopped = Completer<void>();
  Isolate? isolate;
  SendPort? controlPort;
  var cancellationRequested = false;
  StreamSubscription<dynamic>? responseSubscription;
  StreamSubscription<dynamic>? errorSubscription;
  Timer? deadline;
  void Function()? removeCancellationListener;
  try {
    removeCancellationListener = cancellation?.addListener(() {
      cancellationRequested = true;
      controlPort?.send('cancel');
      if (!completed.isCompleted) {
        completed.completeError(const WebProviderSearchCancelled());
      }
    });
    isolate = await Isolate.spawn<List<Object?>>(
      _providerIsolateEntry,
      [responses.sendPort, input],
      onError: errors.sendPort,
      onExit: responses.sendPort,
      errorsAreFatal: true,
      paused: true,
      debugName: 'TetoTV provider ${input['id']}',
    );
    responseSubscription = responses.listen((dynamic message) {
      if (message == null) {
        if (!isolateStopped.isCompleted) isolateStopped.complete();
        if (!completed.isCompleted) {
          completed.completeError(
            StateError('Provider worker exited before returning a result.'),
          );
        }
        return;
      }
      if (message is! Map) return;
      final workerControl = message['control'];
      if (workerControl is SendPort) {
        controlPort = workerControl;
        if (cancellationRequested) controlPort!.send('cancel');
        return;
      }
      if (completed.isCompleted) return;
      if (message['cancelled'] == true) {
        completed.completeError(const WebProviderSearchCancelled());
        return;
      }
      if (message['ok'] != true) {
        completed.completeError(
          StateError('${message['error'] ?? 'Provider failed'}'),
        );
        return;
      }
      final raw = message['result'];
      final result = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            result.add(item.map((key, value) => MapEntry('$key', value)));
          }
        }
      }
      completed.complete(result);
    });
    errorSubscription = errors.listen((dynamic message) {
      if (completed.isCompleted) return;
      final error = message is List && message.isNotEmpty
          ? message.first
          : message;
      completed.completeError(StateError('$error'));
    });
    deadline = Timer(timeout, () {
      if (!completed.isCompleted) {
        cancellationRequested = true;
        controlPort?.send('cancel');
        completed.completeError(
          TimeoutException(
            'Provider exceeded its ${timeout.inSeconds}-second runtime limit.',
            timeout,
          ),
        );
      }
    });
    final pauseCapability = isolate.pauseCapability;
    if (pauseCapability != null) isolate.resume(pauseCapability);
    return await completed.future;
  } finally {
    removeCancellationListener?.call();
    deadline?.cancel();
    // Let the worker unwind _executeProvider's finally block and free its
    // native QuickJS heap. A forced kill remains a bounded fallback for a
    // wedged native call, but is no longer the normal cancellation path.
    if (!isolateStopped.isCompleted) {
      cancellationRequested = true;
      controlPort?.send('cancel');
      try {
        // The native bytecode deadline is six seconds. Waiting beyond it lets
        // even a worker currently stuck in synchronous JavaScript unwind and
        // dispose its 48 MiB-bounded heap before forced termination.
        await isolateStopped.future.timeout(const Duration(milliseconds: 7500));
      } on TimeoutException {
        isolate?.kill(priority: Isolate.immediate);
        try {
          await isolateStopped.future.timeout(
            const Duration(milliseconds: 250),
          );
        } on TimeoutException {
          // The isolate is already kill-requested; closing local ports below
          // prevents this search from retaining any Dart-side resources.
        }
      }
    }
    await responseSubscription?.cancel();
    await errorSubscription?.cancel();
    responses.close();
    errors.close();
  }
}

void _providerIsolateEntry(List<Object?> message) {
  final port = message[0] as SendPort;
  final rawInput = message[1] as Map;
  final input = rawInput.map<String, Object?>(
    (key, value) => MapEntry('$key', value),
  );
  final cancellation = WebProviderCancellation();
  final controls = ReceivePort();
  final controlSubscription = controls.listen((dynamic command) {
    if (command == 'cancel') cancellation.cancel();
  });
  port.send({'control': controls.sendPort});
  unawaited(() async {
    try {
      final result = await _executeProvider(input, cancellation: cancellation);
      if (cancellation.isCancelled) {
        port.send({'cancelled': true});
      } else {
        port.send({'ok': true, 'result': result});
      }
    } on WebProviderSearchCancelled {
      port.send({'cancelled': true});
    } catch (error) {
      port.send({'ok': false, 'error': error.toString()});
    } finally {
      await controlSubscription.cancel();
      controls.close();
    }
  }());
}

Future<List<Map<String, dynamic>>> _executeProvider(
  Map<String, Object?> input, {
  required WebProviderCancellation cancellation,
}) async {
  final runtime = QuickJsRuntime2(
    timeout: 6000,
    memoryLimit: 48 * 1024 * 1024,
    stackSize: 512 * 1024,
  );
  var disposed = false;
  final completed = Completer<List<Map<String, dynamic>>>();
  final networkBudget = AddonRuntimeNetworkBudget();

  runtime.onMessage('TetoNetwork', (dynamic request) {
    unawaited(() async {
      final id = request is Map ? '${request['id'] ?? ''}' : '';
      var acquired = false;
      try {
        await networkBudget.acquire();
        acquired = true;
        final response = await _safeAddonRequest(
          request,
          cancellation: cancellation,
        );
        networkBudget.recordResponse('${response['body'] ?? ''}');
        if (!disposed) {
          runtime.evaluate(
            '__tetoNetworkFinish(${jsonEncode(id)}, ${jsonEncode(response)});',
          );
          await runtime.dispatch();
        }
      } catch (error) {
        if (!disposed) {
          runtime.evaluate(
            '__tetoNetworkFail(${jsonEncode(id)}, ${jsonEncode(_safeError(error))});',
          );
          await runtime.dispatch();
        }
      } finally {
        if (acquired) networkBudget.release();
      }
    }());
  });
  runtime.onMessage('TetoDone', (dynamic value) {
    if (completed.isCompleted) return;
    if (value is! Map || value['ok'] != true) {
      completed.completeError(
        StateError(
          value is Map
              ? '${value['error'] ?? 'Provider failed'}'
              : 'Provider failed',
        ),
      );
      return;
    }
    final data = value['result'];
    final streams = <Map<String, dynamic>>[];
    if (data is List) {
      for (final item in data.take(80)) {
        if (item is Map) {
          streams.add(item.map((key, value) => MapEntry('$key', value)));
        }
      }
    }
    completed.complete(streams);
  });

  try {
    cancellation.throwIfCancelled();
    final bootstrap = runtime.evaluate(_networkBootstrap);
    if (bootstrap.isError) throw StateError(bootstrap.stringResult);
    cancellation.throwIfCancelled();
    final domRuntime = runtime.evaluate(
      input['domRuntime']! as String,
      sourceUrl: 'asset://linkedom.js',
    );
    if (domRuntime.isError) throw StateError(domRuntime.stringResult);
    cancellation.throwIfCancelled();
    final compatibility = runtime.evaluate(_seanimeCompatibilityBootstrap);
    if (compatibility.isError) throw StateError(compatibility.stringResult);
    cancellation.throwIfCancelled();
    final payload = input['payload']! as String;
    final provider = runtime.evaluate(
      payload,
      sourceUrl: 'addon://${input['id']}/provider.js',
    );
    if (provider.isError) throw StateError(provider.stringResult);
    cancellation.throwIfCancelled();
    final invocation = runtime.evaluate('''
      (async function() {
        try {
          const provider = new Provider();
          const settings = typeof provider.getSettings === 'function'
            ? ((await provider.getSettings()) || {}) : {};
          const titles = ${jsonEncode([input['title'], ...((input['titles'] as List?) ?? const [])])}
            .filter(Boolean).filter((title, index, all) =>
              all.findIndex(other => String(other).toLowerCase() === String(title).toLowerCase()) === index
            ).slice(0, 5);
          const episodeNumber = ${input['episode']};
          const media = {
            id: ${input['anilistId']},
            idMal: ${input['malId'] ?? 'null'},
            englishTitle: titles[0] || '',
            romajiTitle: titles[1] || titles[0] || '',
            nativeTitle: titles[2] || '',
            synonyms: titles.slice(1),
            startDate: {year: ${input['year'] ?? 'null'}, month: null, day: null},
            seasonYear: ${input['year'] ?? 'null'},
          };
          const modes = settings.supportsDub ? [false, true] : [false];
          const output = [];
          const errors = [];
          let foundTitle = false;
          let foundEpisode = false;
          const normalize = value => String(value || '').toLowerCase()
            .normalize('NFKD').replace(/[^a-z0-9]+/g, ' ').trim();
          const score = (candidate, query) => {
            const a = normalize(candidate); const b = normalize(query);
            if (a === b) return 1000;
            if (a.startsWith(b) || b.startsWith(a)) return 700;
            if (a.includes(b) || b.includes(a)) return 500;
            const words = new Set(b.split(' ').filter(x => x.length > 1));
            return a.split(' ').reduce((sum, word) => sum + (words.has(word) ? 20 : 0), 0);
          };
          const listFrom = (value, keys) => {
            if (Array.isArray(value)) return value;
            if (!value || typeof value !== 'object') return [];
            for (const key of keys) {
              if (Array.isArray(value[key])) return value[key];
            }
            if (value.data && typeof value.data === 'object') {
              for (const key of keys) {
                if (Array.isArray(value.data[key])) return value.data[key];
              }
            }
            return [];
          };
          const episodeNumberOf = item => {
            const raw = item && (item.number != null ? item.number :
              (item.episodeNumber != null ? item.episodeNumber :
              (item.episode != null ? item.episode : item.num)));
            const direct = Number(raw);
            if (Number.isFinite(direct)) return direct;
            const match = String(raw || (item && (item.title || item.id)) || '').match(/(?:episode|ep)?\\s*([0-9]+(?:\\.[0-9]+)?)/i);
            return match ? Number(match[1]) : NaN;
          };
          const toHttps = (value, bases) => {
            if (typeof value !== 'string' || !value.trim()) return null;
            const raw = value.trim();
            try {
              const direct = new URL(raw);
              if (direct.protocol === 'https:') return direct.toString();
            } catch (_) {}
            for (const base of bases) {
              if (typeof base !== 'string' || !base.startsWith('https://')) continue;
              try {
                const absolute = new URL(raw, base);
                if (absolute.protocol === 'https:') return absolute.toString();
              } catch (_) {}
            }
            return null;
          };
          const englishTrack = tracks => {
            if (!tracks.length) return null;
            return tracks.find(track => {
              const value = normalize(track && (track.language || track.lang || track.label || track.name));
              return value === 'en' || value === 'eng' || value.includes('english');
            }) || tracks[0];
          };
          for (const dub of modes) {
            let selected = null;
            for (const title of titles) {
              try {
                const searchInput = {
                  query: title,
                  dub,
                  year: ${input['year'] ?? 'null'},
                  media,
                  opts: {dub, year: ${input['year'] ?? 'null'}, media},
                };
                let rawMatches = await provider.search(searchInput);
                let matches = listFrom(rawMatches, ['results', 'items', 'data']);
                if (!matches.length) {
                  try {
                    rawMatches = await provider.search(title, {dub, year: ${input['year'] ?? 'null'}, media});
                    matches = listFrom(rawMatches, ['results', 'items', 'data']);
                  } catch (error) { errors.push(String(error && error.message || error)); }
                }
                const ranked = matches.slice(0, 40).map(item => ({item, points: score(item.title, title)}))
                  .sort((a, b) => b.points - a.points);
                if (ranked.length && (!selected || ranked[0].points > selected.points)) {
                  selected = ranked[0];
                }
                // A provider's own ordered search result is usually more
                // useful than repeatedly querying every title alias. Continue
                // only when the match is weak enough to justify another call.
                if (selected && selected.points >= 500) break;
              } catch (error) { errors.push(String(error && error.message || error)); }
            }
            if (!selected) continue;
            foundTitle = true;
            let episodes = [];
            try {
              const rawEpisodes = await provider.findEpisodes(
                selected.item.id || selected.item.url || selected.item.slug
              );
              episodes = listFrom(rawEpisodes, ['episodes', 'items', 'results']);
            } catch (error) {
              errors.push(String(error && error.message || error));
            }
            let episode = episodes.find(item => Math.abs(episodeNumberOf(item) - episodeNumber) < 0.01);
            if (!episode && episodes.length === 1 && episodeNumber === 1) episode = episodes[0];
            if (!episode) continue;
            foundEpisode = true;
            let servers = Array.isArray(settings.episodeServers) && settings.episodeServers.length
              ? settings.episodeServers.slice(0, 6) : ['default'];
            const serverName = server => server && typeof server === 'object'
              ? String(server.name || server.label || server.id || server.value || 'Default')
              : String(server || 'Default');
            const serverValue = server => server && typeof server === 'object'
              ? (server.value || server.id || server.name || server.label) : server;
            const dubbedServers = servers.filter(server => /dub/i.test(serverName(server)));
            if (settings.supportsDub && dubbedServers.length) {
              servers = dub ? dubbedServers : servers.filter(server => !/dub/i.test(serverName(server)));
            }
            // Resolve independent servers together. A dead mirror must not
            // prevent a healthy mirror later in the provider's server list
            // from being discovered before the provider deadline.
            await Promise.all(servers.map(async server => {
              try {
                let resolved = null;
                try {
                  resolved = await provider.findEpisodeServer(episode, serverValue(server));
                } catch (error) {
                  const message = String(error && error.message || error);
                  errors.push(message);
                  // Seanime's current contract passes the episode object. A
                  // small number of legacy providers expect its ID instead;
                  // retry only argument-shape errors so network failures are
                  // not repeated three times.
                  if (/argument|undefined|null|property|\\bid\\b|object/i.test(message)) {
                    try {
                      resolved = await provider.findEpisodeServer(
                        episode.id || episode.url || episode,
                        serverValue(server),
                      );
                    } catch (fallbackError) {
                      errors.push(String(fallbackError && fallbackError.message || fallbackError));
                    }
                  }
                }
                if (!resolved) return;
                const serverHeaders = resolved && resolved.headers && typeof resolved.headers === 'object'
                  ? resolved.headers : {};
                let sources = listFrom(resolved, ['videoSources', 'sources', 'streams']);
                if (!sources.length && (typeof resolved === 'string' || resolved.url || resolved.file || resolved.src)) {
                  sources = [resolved];
                }
                for (const rawSource of sources.slice(0, 20)) {
                  const source = typeof rawSource === 'string' ? {url: rawSource} : rawSource;
                  if (!source || typeof source !== 'object') continue;
                  const bases = [source.baseUrl, resolved.baseUrl, resolved.url, episode.url, selected.item.url];
                  const url = toHttps(
                    source.url || source.file || source.src || source.link || source.manifest,
                    bases,
                  );
                  if (!url) continue;
                  const subtitles = listFrom(source.subtitles || source.tracks, ['subtitles', 'tracks'])
                    .concat(listFrom(resolved.subtitles || resolved.tracks, ['subtitles', 'tracks']));
                  const english = englishTrack(subtitles);
                  const subtitleUrl = english && toHttps(
                    english.url || english.file || english.src || english.link,
                    bases,
                  );
                  output.push({
                    title: serverName(server || resolved.server) + ' / ' +
                      String(source.quality || source.label || 'Auto'),
                    quality: String(source.quality || source.label || 'Auto'),
                    url,
                    headers: Object.assign({}, serverHeaders, source.headers || {}),
                    subtitleUrl,
                    subtitleLanguage: english && String(english.language || english.lang || english.label || ''),
                    isDubbed: dub || /dub/i.test(String(selected.item.subOrDub || serverName(server))),
                  });
                }
              } catch (error) { errors.push(String(error && error.message || error)); }
            }));
          }
          if (!output.length) {
            const detail = errors.length ? ' Last error: ' + errors[errors.length - 1] : '';
            if (!foundTitle) throw new Error('NO_MATCH: This provider has no matching title.' + detail);
            if (!foundEpisode) throw new Error('NO_MATCH: This provider has no matching episode.' + detail);
            throw new Error('NO_STREAM: The provider found the episode but returned no compatible stream.' + detail);
          }
          sendMessage('TetoDone', JSON.stringify({ok: true, result: output}));
        } catch (error) {
          sendMessage('TetoDone', JSON.stringify({ok: false, error: String(error && error.message || error)}));
        }
      })();
    ''', sourceUrl: 'tetotv://provider-runner.js');
    if (invocation.isError) throw StateError(invocation.stringResult);
    await runtime.dispatch();
    return await Future.any<List<Map<String, dynamic>>>([
      completed.future,
      cancellation.whenCancelled.then<List<Map<String, dynamic>>>(
        (_) => throw const WebProviderSearchCancelled(),
      ),
    ]).timeout(const Duration(seconds: 18));
  } finally {
    disposed = true;
    runtime.dispose();
  }
}

class AddonRuntimeNetworkBudget {
  AddonRuntimeNetworkBudget({
    this.maximumRequests = 64,
    this.maximumConcurrentRequests = 8,
    this.maximumResponseBytes = 16 * 1024 * 1024,
  });

  final int maximumRequests;
  final int maximumConcurrentRequests;
  final int maximumResponseBytes;

  final List<Completer<void>> _waiters = [];
  var _requestCount = 0;
  var _activeRequests = 0;
  var _responseBytes = 0;

  Future<void> acquire() async {
    _requestCount++;
    if (_requestCount > maximumRequests) {
      throw const FormatException(
        'Provider exceeded its network request limit.',
      );
    }
    if (_responseBytes >= maximumResponseBytes) {
      throw const FormatException(
        'Provider exceeded its total response limit.',
      );
    }
    if (_activeRequests < maximumConcurrentRequests) {
      _activeRequests++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
    if (_responseBytes >= maximumResponseBytes) {
      release();
      throw const FormatException(
        'Provider exceeded its total response limit.',
      );
    }
  }

  void recordResponse(String value) {
    _responseBytes += utf8.encode(value).length;
    if (_responseBytes > maximumResponseBytes) {
      throw const FormatException(
        'Provider exceeded its total response limit.',
      );
    }
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      return;
    }
    if (_activeRequests > 0) _activeRequests--;
  }
}

const _forbiddenAddonHeaders = {
  'connection',
  'content-length',
  'host',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
};

// Cross-origin redirects must not forward arbitrary addon-supplied headers.
// API credentials use many non-standard names (X-Api-Key, X-Auth-Token,
// provider-specific headers, and so on), so a credential denylist will always
// be incomplete. Keep only the small set needed for ordinary media requests.
const _crossOriginSafeAddonHeaders = {
  'accept',
  'accept-language',
  'content-type',
  'range',
  'referer',
  'user-agent',
};

/// Sanitizes headers originating in untrusted add-on code before either the
/// Dart HTTP stack or a native player sees them. Hop-by-hop framing headers
/// and control characters are never forwarded.
Map<String, String> sanitizeAddonHeaders(
  Object? raw, {
  String? defaultUserAgent,
  bool stripCredentials = false,
  int maximumValueLength = 4096,
}) {
  final result = <String, String>{};
  final seen = <String>{};
  if (defaultUserAgent != null) {
    result['User-Agent'] = defaultUserAgent;
    seen.add('user-agent');
  }
  if (raw is! Map) return Map.unmodifiable(result);
  var totalLength = defaultUserAgent?.length ?? 0;
  for (final entry in raw.entries.take(24)) {
    final key = '${entry.key}'.trim();
    final lower = key.toLowerCase();
    final value = '${entry.value}'.trim();
    if (key.isEmpty ||
        key.length > 80 ||
        !RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(key) ||
        _forbiddenAddonHeaders.contains(lower) ||
        (stripCredentials && !_crossOriginSafeAddonHeaders.contains(lower)) ||
        seen.contains(lower) ||
        value.length > maximumValueLength ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      continue;
    }
    totalLength += key.length + value.length;
    if (totalLength > 16 * 1024) break;
    seen.add(lower);
    result[key] = value;
  }
  return Map.unmodifiable(result);
}

bool _sameOrigin(Uri left, Uri right) =>
    left.scheme == right.scheme &&
    left.host.toLowerCase() == right.host.toLowerCase() &&
    left.port == right.port;

Future<Map<String, Object?>> _safeAddonRequest(
  dynamic raw, {
  Duration connectTimeout = const Duration(seconds: 6),
  Duration receiveTimeout = const Duration(seconds: 8),
  Duration? overallTimeout,
  int maximumResponseBytes = 2 * 1024 * 1024,
  WebProviderCancellation? cancellation,
}) async {
  cancellation?.throwIfCancelled();
  if (raw is! Map) throw const FormatException('Invalid provider request.');
  final uri = safePublicHttpsUri(raw['url']);
  if (uri == null) {
    throw const FormatException('Provider requests must use public HTTPS.');
  }
  var currentUri = uri;
  await validatePublicNetworkTarget(currentUri);
  cancellation?.throwIfCancelled();
  final options = raw['options'] is Map ? raw['options'] as Map : const {};
  final method = '${options['method'] ?? 'GET'}'.toUpperCase();
  if (method != 'GET' && method != 'POST' && method != 'HEAD') {
    throw const FormatException(
      'Only GET, POST, and HEAD requests are permitted.',
    );
  }
  var headers = sanitizeAddonHeaders(
    options['headers'],
    defaultUserAgent: 'TetoTV addon runtime',
  );
  var body = options['body'] == null ? null : '${options['body']}';
  if (body != null && utf8.encode(body).length > 128 * 1024) {
    throw const FormatException('Provider request body is too large.');
  }
  final dio = createPinnedPublicHttpsDio(
    BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
      followRedirects: false,
    ),
  );
  final cancelToken = CancelToken();
  final removeCancellationListener = cancellation?.addListener(
    () => cancelToken.cancel(const WebProviderSearchCancelled()),
  );
  final overallDeadline = overallTimeout == null
      ? null
      : Timer(
          overallTimeout,
          () => cancelToken.cancel('Provider request deadline exceeded.'),
        );
  Response<ResponseBody>? response;
  String responseText = '';
  var currentMethod = method;
  try {
    for (var redirect = 0; redirect < 4; redirect++) {
      cancellation?.throwIfCancelled();
      response = await dio.request<ResponseBody>(
        currentUri.toString(),
        data: body,
        cancelToken: cancelToken,
        options: Options(
          method: currentMethod,
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );
      responseText = await _boundedResponseText(
        response.data,
        maximumResponseBytes,
      );
      final status = response.statusCode ?? 0;
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (status < 300 || status >= 400 || location == null) break;
      final redirectUri = safePublicHttpsUri(
        currentUri.resolve(location).toString(),
      );
      if (redirectUri == null) {
        throw const FormatException('Provider redirect was not public HTTPS.');
      }
      if (!_sameOrigin(currentUri, redirectUri)) {
        headers = sanitizeAddonHeaders(
          headers,
          defaultUserAgent: 'TetoTV addon runtime',
          stripCredentials: true,
        );
      }
      if (status == 303 ||
          ((status == 301 || status == 302) && currentMethod == 'POST')) {
        currentMethod = 'GET';
        body = null;
      }
      currentUri = redirectUri;
      await validatePublicNetworkTarget(currentUri);
      cancellation?.throwIfCancelled();
    }
  } finally {
    overallDeadline?.cancel();
    removeCancellationListener?.call();
    dio.close(force: true);
  }
  if (response == null) throw const HttpException('No provider response.');
  return {
    'status': response.statusCode ?? 0,
    'statusText': response.statusMessage ?? '',
    'url': response.realUri.toString(),
    'body': responseText,
    // HLS expansion must reuse the post-redirect header set. In particular,
    // credentials supplied for one origin cannot follow a master-playlist
    // redirect and then leak to that other origin's variant URLs.
    'requestHeaders': headers,
    'headers': sanitizeAddonHeaders({
      for (final entry in response.headers.map.entries)
        entry.key: entry.value.join(', '),
    }),
  };
}

Future<String> _boundedResponseText(
  ResponseBody? body,
  int maximumBytes,
) async {
  if (body == null) return '';
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in body.stream) {
    length += chunk.length;
    if (length > maximumBytes) {
      throw const FormatException('Provider response is too large.');
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes(), allowMalformed: true);
}

String _safeError(Object error) {
  final value = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
  return value.length > 180 ? '${value.substring(0, 180)}…' : value;
}

const _networkBootstrap = r'''
  const __tetoPending = Object.create(null);
  let __tetoRequestId = 0;
  function fetch(url, options) {
    return new Promise((resolve, reject) => {
      const id = String(++__tetoRequestId);
      __tetoPending[id] = {resolve, reject};
      let requestUrl = String(url);
      const seanimeProxy = 'http://127.0.0.1:43211/api/v1/proxy?url=';
      if (requestUrl.startsWith(seanimeProxy)) {
        try { requestUrl = decodeURIComponent(requestUrl.slice(seanimeProxy.length)); } catch (_) {}
      }
      sendMessage('TetoNetwork', JSON.stringify({id, url: requestUrl, options: options || {}}));
    });
  }
  function __tetoNetworkFinish(id, response) {
    const pending = __tetoPending[id]; if (!pending) return;
    delete __tetoPending[id];
    const headers = response.headers || {};
    pending.resolve({
      ok: response.status >= 200 && response.status < 300,
      status: response.status,
      statusText: response.statusText,
      url: response.url,
      headers: {get: name => headers[String(name).toLowerCase()] || headers[String(name)] || null},
      text: () => Promise.resolve(response.body || ''),
      json: () => Promise.resolve(JSON.parse(response.body || 'null')),
    });
  }
  function __tetoNetworkFail(id, message) {
    const pending = __tetoPending[id]; if (!pending) return;
    delete __tetoPending[id]; pending.reject(new Error(message));
  }
  function atob(value) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let output = '', buffer = 0, bits = 0;
    value = String(value).replace(/[^A-Za-z0-9+/=]/g, '');
    for (let i = 0; i < value.length; i++) {
      const n = chars.indexOf(value[i]); if (n < 0 || n === 64) break;
      buffer = (buffer << 6) | n; bits += 6;
      if (bits >= 8) { bits -= 8; output += String.fromCharCode((buffer >> bits) & 255); }
    }
    return output;
  }
  function btoa(value) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let output = '', index = 0;
    value = String(value);
    while (index < value.length) {
      const a = value.charCodeAt(index++) & 255;
      const b = index < value.length ? value.charCodeAt(index++) & 255 : NaN;
      const c = index < value.length ? value.charCodeAt(index++) & 255 : NaN;
      output += chars[a >> 2];
      output += chars[((a & 3) << 4) | (b >> 4)];
      output += Number.isNaN(b) ? '=' : chars[((b & 15) << 2) | (c >> 6)];
      output += Number.isNaN(c) ? '=' : chars[c & 63];
    }
    return output;
  }
''';

const _seanimeCompatibilityBootstrap = r'''
  if (typeof console === 'undefined') {
    globalThis.console = {};
  }
  for (const method of ['log', 'info', 'warn', 'error', 'debug', 'trace', 'table', 'assert']) {
    if (typeof globalThis.console[method] !== 'function') {
      globalThis.console[method] = function() {};
    }
  }

  if (typeof URLSearchParams === 'undefined') {
    globalThis.URLSearchParams = class URLSearchParams {
      constructor(input) {
        this.pairs = [];
        if (typeof input === 'string') {
          String(input).replace(/^\?/, '').split('&').forEach(part => {
            if (!part) return;
            const split = part.indexOf('=');
            this.append(
              decodeURIComponent(split < 0 ? part : part.slice(0, split)),
              decodeURIComponent(split < 0 ? '' : part.slice(split + 1))
            );
          });
        } else if (Array.isArray(input)) {
          input.forEach(entry => this.append(entry[0], entry[1]));
        } else if (input && typeof input === 'object') {
          Object.keys(input).forEach(key => this.append(key, input[key]));
        }
      }
      append(key, value) { this.pairs.push([String(key), String(value)]); }
      set(key, value) {
        this.delete(key);
        this.append(key, value);
      }
      get(key) {
        const item = this.pairs.find(entry => entry[0] === String(key));
        return item ? item[1] : null;
      }
      getAll(key) {
        return this.pairs.filter(entry => entry[0] === String(key)).map(entry => entry[1]);
      }
      has(key) { return this.pairs.some(entry => entry[0] === String(key)); }
      delete(key) { this.pairs = this.pairs.filter(entry => entry[0] !== String(key)); }
      forEach(callback) { this.pairs.forEach(entry => callback(entry[1], entry[0], this)); }
      entries() { return this.pairs[Symbol.iterator](); }
      keys() { return this.pairs.map(entry => entry[0])[Symbol.iterator](); }
      values() { return this.pairs.map(entry => entry[1])[Symbol.iterator](); }
      toString() {
        return this.pairs.map(entry => encodeURIComponent(entry[0]) + '=' + encodeURIComponent(entry[1])).join('&');
      }
    };
  }

  if (typeof URL === 'undefined') {
    globalThis.URL = class URL {
      constructor(value, base) {
        const input = String(value || '');
        this.href = /^https?:\/\//i.test(input)
          ? input
          : String(base || '').replace(/\/$/, '') + '/' + input.replace(/^\//, '');
        const match = /^(https?):\/\/([^/?#]+)([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/i.exec(this.href) || [];
        this.protocol = match[1] ? match[1] + ':' : '';
        this.host = match[2] || '';
        this.hostname = this.host.split(':')[0];
        this.origin = this.protocol && this.host ? this.protocol + '//' + this.host : '';
        this.pathname = match[3] || '/';
        this.search = match[4] ? '?' + match[4] : '';
        this.hash = match[5] ? '#' + match[5] : '';
        this.searchParams = new URLSearchParams(match[4] || '');
      }
      toString() { return this.href; }
    };
  }

  function __tetoElements(value) {
    if (value == null) return [];
    if (Array.isArray(value)) return value.filter(Boolean);
    if (typeof value === 'string') return Array.from(__tetoParseDocument(value).children || []);
    if (typeof value.length === 'number' && !value.nodeType) return Array.from(value).filter(Boolean);
    return [value];
  }

  function __tetoSelect(root, selector) {
    let query = String(selector || '*');
    let contains = null;
    const match = /:contains\((?:"([^"]*)"|'([^']*)'|([^)]*))\)/.exec(query);
    if (match) {
      contains = match[1] || match[2] || match[3] || '';
      query = query.replace(match[0], '') || '*';
    }
    let results = [];
    try { results = Array.from(root.querySelectorAll(query)); } catch (_) { return []; }
    return contains == null
      ? results
      : results.filter(node => String(node.textContent || '').includes(contains));
  }

  function __tetoSelection(value) {
    const elements = __tetoElements(value);
    function selection(selector) {
      if (selector == null) return selection;
      return __tetoSelection(elements.flatMap(node => __tetoSelect(node, selector)));
    }
    selection.length = elements.length;
    elements.forEach((node, index) => { selection[index] = node; });
    selection.toArray = () => elements.slice();
    selection.get = index => index == null ? elements.slice() : elements[index < 0 ? elements.length + index : index];
    selection.eq = index => __tetoSelection(selection.get(index));
    selection.first = () => selection.eq(0);
    selection.last = () => selection.eq(-1);
    selection.each = callback => {
      elements.forEach((node, index) => callback.call(node, index, node));
      return selection;
    };
    selection.map = callback => ({
      get: () => elements.map((node, index) => callback.call(node, index, node)),
      toArray: () => elements.map((node, index) => callback.call(node, index, node)),
    });
    selection.text = () => elements.map(node => node.textContent || '').join('');
    selection.html = () => elements[0] ? elements[0].innerHTML || '' : '';
    selection.attr = name => elements[0] && elements[0].getAttribute ? elements[0].getAttribute(name) : undefined;
    selection.data = name => selection.attr('data-' + String(name).replace(/[A-Z]/g, letter => '-' + letter.toLowerCase()));
    selection.val = () => elements[0] ? elements[0].value : undefined;
    selection.hasClass = name => !!(elements[0] && elements[0].classList && elements[0].classList.contains(name));
    selection.find = selector => __tetoSelection(elements.flatMap(node => __tetoSelect(node, selector)));
    selection.children = selector => {
      const children = elements.flatMap(node => Array.from(node.children || []));
      if (!selector) return __tetoSelection(children);
      return __tetoSelection(children.filter(node => node.matches && node.matches(selector)));
    };
    selection.parent = () => __tetoSelection(elements.map(node => node.parentElement));
    selection.next = () => __tetoSelection(elements.map(node => node.nextElementSibling));
    selection.prev = () => __tetoSelection(elements.map(node => node.previousElementSibling));
    selection.filter = selector => __tetoSelection(elements.filter(node => node.matches && node.matches(selector)));
    return selection;
  }

  function LoadDoc(source) {
    const document = __tetoParseDocument(String(source || ''));
    function loaded(selector) {
      if (typeof selector === 'string') return __tetoSelection(__tetoSelect(document, selector));
      return __tetoSelection(selector);
    }
    loaded.root = () => __tetoSelection(document.documentElement);
    loaded.html = () => document.documentElement ? document.documentElement.outerHTML : '';
    return loaded;
  }

  async function _makeRequest(url, options) {
    const response = await fetch(url, options || {});
    const body = await response.text();
    if (!response.ok) throw new Error('HTTP ' + response.status + ' for ' + url);
    return {status: response.status, headers: response.headers, body, data: body, text: body, url: response.url};
  }

  async function $sleep() {}

  function normalizeQuery(value) {
    return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-zA-Z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function __tetoSimilarity(left, right) {
    const a = new Set(normalizeQuery(left).split(' ').filter(Boolean));
    const b = new Set(normalizeQuery(right).split(' ').filter(Boolean));
    if (!a.size || !b.size) return 0;
    let common = 0;
    a.forEach(item => { if (b.has(item)) common++; });
    return common / Math.max(a.size, b.size);
  }

  function filterBySimilarity(items, query) {
    return (Array.isArray(items) ? items : []).slice().sort((left, right) =>
      __tetoSimilarity(right.title || right.name, query) - __tetoSimilarity(left.title || left.name, query)
    );
  }

  globalThis.$scannerUtils = {
    normalizeQuery,
    sanitizeQuery(value) { return normalizeQuery(value); },
    buildSearchQuery(value) { return normalizeQuery(value); },
    buildSmartSearchTitles(values) {
      const titles = [];
      (Array.isArray(values) ? values : [values]).forEach(value => {
        const title = String(value || '').trim();
        if (title && !titles.includes(title)) titles.push(title);
      });
      return {titles, season: null, part: null};
    },
    filterBySimilarity,
    findBestMatch(items, query) { return filterBySimilarity(items, query)[0] || null; },
    similarity: __tetoSimilarity,
    compareTwoStrings: __tetoSimilarity,
  };
''';
