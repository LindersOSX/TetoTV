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
  const SeanimeJavascriptProvider(
    this.addon, {
    this.validateResultTarget = validatePublicNetworkTarget,
  });

  static Future<String>? _domRuntimeSource;

  final InstalledStreamingAddon addon;
  final Future<void> Function(Uri uri) validateResultTarget;

  @override
  String get id => addon.manifest.id;

  @override
  String get name => addon.manifest.name;

  String? get version => addon.manifest.version;

  String? get repositoryHost =>
      safePublicHttpsUri(addon.manifest.repositoryUrl)?.host;

  String get executableHost =>
      (addon.manifest.payloadUri ?? addon.manifest.manifestUri).host;

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
        'userConfig': addon.manifest.userConfigDefaults,
        'domRuntime': domRuntime,
        'title': episode.title,
        'titles': seanimeProviderSearchTitles(episode),
        'synonyms': seanimeProviderMediaSynonyms(episode),
        'titleEnglish': episode.titleEnglish,
        'titleRomaji': episode.titleRomaji,
        'status': episode.status,
        'format': episode.format,
        'episodeCount': episode.episodeCount,
        'isAdult': episode.isAdult,
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
        await validateResultTarget(uri);
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
        'NO_STREAM: Provider streams failed URL or network safety validation. '
        '[stage=server; reason=unsafe_target]',
      );
    }
    return results;
  }
}

bool isSeanimeProviderNoMatch(Object error) =>
    error.toString().contains('NO_MATCH:');

/// Ordered title queries for older Seanime providers that inspect only
/// `SearchOptions.query` instead of the richer `SearchOptions.media` object.
List<String> seanimeProviderSearchTitles(EpisodeReference episode) {
  final values = <String?>[
    episode.title,
    episode.titleEnglish,
    episode.titleRomaji,
    ...episode.alternativeTitles,
  ];
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final title = value?.trim();
    if (title == null || title.isEmpty || !seen.add(title.toLowerCase())) {
      continue;
    }
    result.add(title);
    if (result.length == 5) break;
  }
  return result;
}

/// Full bounded alias set for Seanime's `Media.synonyms`. This is separate
/// from the five actual search attempts because providers may inspect a
/// later/site-specific alias themselves (AnimeAV1 is one such provider).
List<String> seanimeProviderMediaSynonyms(EpisodeReference episode) {
  final values = <String?>[
    episode.titleEnglish,
    episode.titleRomaji,
    ...episode.alternativeTitles,
  ];
  final primary = episode.title.trim().toLowerCase();
  final seen = <String>{primary};
  final result = <String>[];
  for (final value in values) {
    final title = value?.trim();
    if (title == null || title.isEmpty || !seen.add(title.toLowerCase())) {
      continue;
    }
    result.add(title);
    if (result.length == 32) break;
  }
  return result;
}

bool isSeanimeProviderNoStream(Object error) =>
    error.toString().contains('NO_STREAM:');

class SeanimeProviderFailureDetails {
  const SeanimeProviderFailureDetails({
    required this.stage,
    required this.reason,
  });

  final String stage;
  final String reason;
}

const _providerFailureStages = {'search', 'episodes', 'server', 'runtime'};
const _providerFailureReasons = {
  'timeout',
  'empty_sources',
  'unsafe_target',
  'invalid_response',
  'network',
  'runtime_api',
  'provider_error',
  'empty_result',
};

/// Reads only the bounded, runtime-generated failure marker. Provider error
/// text is deliberately excluded so URLs, search terms, cookies, and tokens
/// cannot be copied into diagnostics through a thrown third-party error.
SeanimeProviderFailureDetails? seanimeProviderFailureDetails(Object error) {
  final match = RegExp(
    r'\[stage=([a-z_]+);\s*reason=([a-z0-9_]+)\]',
  ).firstMatch(error.toString());
  if (match == null) return null;
  final stage = match.group(1)!;
  final reason = match.group(2)!;
  if (!_providerFailureStages.contains(stage)) return null;
  if (!_providerFailureReasons.contains(reason) &&
      !RegExp(r'^http_[1-5][0-9]{2}$').hasMatch(reason)) {
    return null;
  }
  return SeanimeProviderFailureDetails(stage: stage, reason: reason);
}

String _providerReasonCopy(String reason) => switch (reason) {
  'timeout' => 'the provider timed out',
  'empty_sources' || 'empty_result' => 'the upstream returned no sources',
  'unsafe_target' => 'the returned address failed network safety checks',
  'invalid_response' => 'the upstream response format changed',
  'network' => 'the provider could not reach its upstream service',
  'runtime_api' => 'the provider uses an unsupported runtime API',
  final String value when value.startsWith('http_') =>
    'the upstream returned HTTP ${value.substring(5)}',
  _ => 'the provider reported an error',
};

/// Converts provider/runtime failures into bounded user-facing copy without
/// leaking Dart's implementation prefix (`Bad state:`) into the stream UI.
String seanimeProviderFailureMessage(Object error) {
  var value = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  final details = seanimeProviderFailureDetails(error);
  value = value.replaceAll(
    RegExp(r'\s*\[stage=[a-z_]+;\s*reason=[a-z0-9_]+\]\s*'),
    '',
  );
  final implementationPrefix = RegExp(
    r'^(?:Bad state|StateError|Exception):\s*',
    caseSensitive: false,
  );
  while (implementationPrefix.hasMatch(value)) {
    value = value.replaceFirst(implementationPrefix, '').trimLeft();
  }
  if (value.startsWith('NO_STREAM:')) {
    final reason = details == null
        ? 'It may need an update or a different server.'
        : 'Reason: ${_providerReasonCopy(details.reason)}.';
    value =
        'This provider found the episode but could not return a '
        'compatible stream. $reason';
  } else if (value.startsWith('NO_MATCH:')) {
    value = value.toLowerCase().contains('episode')
        ? 'This provider matched the title but has no matching episode.'
        : 'This provider has no matching title.';
  }
  return value.length > 180 ? '${value.substring(0, 180)}…' : value;
}

/// Stable, redacted provider provenance for diagnostic events and health
/// records. Only manifest-derived IDs/versions/hosts and runtime-generated
/// enums are included; full URLs and provider exception text are omitted.
String seanimeProviderDiagnosticMessage(
  SeanimeJavascriptProvider provider,
  Object error,
) {
  final details = seanimeProviderFailureDetails(error);
  String field(Object? value, {int maximum = 80}) {
    final safe = '${value ?? 'unknown'}'
        .replaceAll(RegExp(r'[^A-Za-z0-9._:-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.length <= maximum ? safe : safe.substring(0, maximum);
  }

  return [
    'provider=${field(provider.id)}',
    'version=${field(provider.version)}',
    'repositoryHost=${field(provider.repositoryHost)}',
    'executableHost=${field(provider.executableHost)}',
    'stage=${field(details?.stage ?? 'runtime')}',
    'reason=${field(details?.reason ?? (error is TimeoutException ? 'timeout' : 'provider_error'))}',
  ].join(' ');
}

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
        // A master playlist may point directly at a different origin without
        // an HTTP redirect. Apply the same allowlist used for cross-origin
        // redirects so addon credentials and custom secrets never reach that
        // variant host.
        'headers': _sameOrigin(masterUri, variant.uri)
            ? item['headers']
            : sanitizeAddonHeaders(item['headers'], stripCredentials: true),
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
  final runtimeStartedAt = DateTime.now();
  const runtimeNetworkWindow = Duration(seconds: 18);
  final completed = Completer<List<Map<String, dynamic>>>();
  final networkBudget = AddonRuntimeNetworkBudget();
  final sleepTimers = <String, Timer>{};

  runtime.onMessage('TetoNetwork', (dynamic request) {
    unawaited(() async {
      final id = request is Map ? '${request['id'] ?? ''}' : '';
      var acquired = false;
      try {
        await networkBudget.acquire();
        acquired = true;
        final remaining =
            runtimeNetworkWindow - DateTime.now().difference(runtimeStartedAt);
        if (remaining <= Duration.zero) {
          throw TimeoutException('Provider runtime deadline exceeded.');
        }
        const perRequestCeiling = Duration(seconds: 6);
        final requestBudget = remaining < perRequestCeiling
            ? remaining
            : perRequestCeiling;
        final response = await _safeAddonRequest(
          request,
          maximumOverallTimeout: requestBudget,
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
  runtime.onMessage('TetoSleep', (dynamic request) {
    if (disposed || cancellation.isCancelled || request is! Map) return;
    final id = '${request['id'] ?? ''}';
    if (id.isEmpty || sleepTimers.containsKey(id)) return;
    final remaining =
        runtimeNetworkWindow - DateTime.now().difference(runtimeStartedAt);
    final duration = addonSleepDuration(
      request['milliseconds'],
      remaining: remaining,
    );
    void finish() {
      sleepTimers.remove(id);
      if (disposed || cancellation.isCancelled) return;
      runtime.evaluate('__tetoSleepFinish(${jsonEncode(id)});');
      unawaited(runtime.dispatch());
    }

    if (duration <= Duration.zero) {
      sleepTimers[id] = Timer(Duration.zero, finish);
    } else {
      sleepTimers[id] = Timer(duration, finish);
    }
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
    final preferences = runtime.evaluate(
      'globalThis.__tetoUserPreferences = Object.freeze('
      '${jsonEncode(input['userConfig'] ?? const <String, String>{})});',
      sourceUrl: 'tetotv://provider-preferences.js',
    );
    if (preferences.isError) throw StateError(preferences.stringResult);
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
          const providerCall = async callback => {
            try {
              return await callback();
            } finally {
              // `$sleep` is synchronous in Seanime's provider contract. Flush
              // unawaited compatibility sleeps even when the provider method
              // throws before the next fetch can observe the sleep barrier.
              await __tetoAwaitSleeps();
            }
          };
          const settings = typeof provider.getSettings === 'function'
            ? ((await providerCall(() => provider.getSettings())) || {}) : {};
          const titles = ${jsonEncode((input['titles'] as List?) ?? const [])}
            .filter(Boolean).filter((title, index, all) =>
              all.findIndex(other => String(other).toLowerCase() === String(title).toLowerCase()) === index
            ).slice(0, 5);
          const episodeNumber = ${input['episode']};
          // Match Seanime's documented provider contract exactly. Providers
          // are allowed to branch on these sentinel values when catalog
          // metadata is unavailable.
          const releaseYear = ${input['year'] ?? 0};
          const media = {
            id: ${input['anilistId']},
            status: ${jsonEncode(input['status'] ?? 'NOT_YET_RELEASED')},
            format: ${jsonEncode(input['format'] ?? 'TV')},
            romajiTitle: ${jsonEncode(input['titleRomaji'])} || titles[0] || '',
            episodeCount: ${input['episodeCount'] ?? -1},
            synonyms: ${jsonEncode((input['synonyms'] as List?) ?? const [])},
            isAdult: ${input['isAdult'] == true},
          };
          // Canonical Seanime names stay authoritative. Read-only aliases
          // cover older community providers without changing the object shape
          // expected by current SearchOptions implementations.
          Object.defineProperties(media, {
            anilistId: {value: media.id, enumerable: false},
            aniListId: {value: media.id, enumerable: false},
            idAniList: {value: media.id, enumerable: false},
          });
          const englishTitle = ${jsonEncode(input['titleEnglish'])};
          if (englishTitle) media.englishTitle = englishTitle;
          Object.defineProperties(media, {
            title: {value: titles[0] || media.romajiTitle, enumerable: false},
            titleRomaji: {value: media.romajiTitle, enumerable: false},
            titleEnglish: {value: englishTitle || undefined, enumerable: false},
          });
          const malMediaId = ${input['malId'] ?? 'null'};
          if (malMediaId != null) {
            media.idMal = malMediaId;
            Object.defineProperties(media, {
              malId: {value: malMediaId, enumerable: false},
              idMAL: {value: malMediaId, enumerable: false},
            });
          }
          if (releaseYear > 0) {
            media.startDate = {year: releaseYear};
          }
          const supportsDub = settings.supportsDub === true ||
            settings.supportsDubbed === true || settings.hasDub === true;
          const modes = supportsDub ? [false, true] : [false];
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
          const listFrom = (value, keys, depth) => {
            const level = Number(depth || 0);
            if (Array.isArray(value)) return value.slice(0, 200);
            if (!value || typeof value !== 'object' || level >= 3) return [];
            for (const key of keys) {
              if (Array.isArray(value[key])) return value[key].slice(0, 200);
              if (value[key] && typeof value[key] === 'object') {
                const nested = listFrom(value[key], keys, level + 1);
                if (nested.length) return nested;
              }
            }
            for (const wrapper of ['data', 'result', 'response', 'payload']) {
              if (value[wrapper] && typeof value[wrapper] === 'object') {
                const nested = listFrom(value[wrapper], keys, level + 1);
                if (nested.length) return nested;
              }
            }
            const mapped = Object.values(value);
            if (mapped.length && mapped.length <= 200 &&
                mapped.every(item => item && typeof item === 'object')) {
              return mapped;
            }
            return [];
          };
          const episodeNumberOf = item => {
            if (!item || typeof item !== 'object') return NaN;
            const explicit = [
              item.number, item.episodeNumber, item.episode_number,
              item.episodeNum, item.episode, item.ep, item.num, item.index,
            ];
            for (const raw of explicit) {
              if (raw == null || raw === '') continue;
              const direct = Number(raw);
              if (Number.isFinite(direct)) return direct;
              const text = String(raw);
              const seasonEpisode = text.match(/s\\d{1,3}\\s*e([0-9]+(?:\\.[0-9]+)?)/i);
              if (seasonEpisode) return Number(seasonEpisode[1]);
              const embedded = text.match(/(?:episode|ep|e)\\s*[-_.:#]?\\s*([0-9]+(?:\\.[0-9]+)?)/i);
              if (embedded) return Number(embedded[1]);
            }
            const values = [item.title, item.name, item.label, item.url, item.id];
            for (const raw of values) {
              const text = String(raw || '');
              let match = text.match(/s\\d{1,3}\\s*e([0-9]+(?:\\.[0-9]+)?)/i);
              if (!match) match = text.match(/(?:episode|ep|e)\\s*[-_.:#]?\\s*([0-9]+(?:\\.[0-9]+)?)/i);
              if (!match) match = text.match(/(?:^|[\\/_-])([0-9]+(?:\\.[0-9]+)?)(?:\$|[/?#._-])/);
              if (match) return Number(match[1]);
            }
            return NaN;
          };
          const valueFrom = (item, keys) => {
            if (!item || typeof item !== 'object') return undefined;
            for (const key of keys) {
              const value = item[key];
              if (value != null && value !== '') return value;
            }
            return undefined;
          };
          const candidateKey = item => {
            const identity = valueFrom(item, [
              'id', 'animeId', 'mediaId', 'providerId', 'slug', 'url', 'link',
            ]);
            if (identity != null) return String(identity).slice(0, 512);
            try { return String(JSON.stringify(item)).slice(0, 512); }
            catch (_) { return candidateTitle(item).slice(0, 512); }
          };
          const candidateTitle = item => String(valueFrom(item, [
            'title', 'name', 'englishTitle', 'romajiTitle', 'label',
          ]) || '');
          const providerReason = error => {
            const message = String(error && error.message || error || '').toLowerCase();
            if (/timeout|timed out|deadline|aborted/.test(message)) return 'timeout';
            const http = message.match(/(?:http|status|returned|failed)\\D{0,12}([1-5][0-9]{2})/);
            if (http) return 'http_' + http[1];
            if (/no source|no stream|video source|empty source|unable to find a valid source/.test(message)) return 'empty_sources';
            if (/public https|safety|unsafe|private address|not permitted/.test(message)) return 'unsafe_target';
            if (/json|parse|unexpected token|invalid response/.test(message)) return 'invalid_response';
            if (/network|socket|dns|connection|fetch failed|host lookup/.test(message)) return 'network';
            if (/referenceerror|is not defined|is not a function|undefined/.test(message)) return 'runtime_api';
            return 'provider_error';
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
            const candidates = new Map();
            for (const title of titles) {
              const searchInput = {
                query: title,
                dub,
                year: releaseYear,
                media,
                opts: {dub, year: releaseYear, media},
              };
              let matches = [];
              try {
                const rawMatches = await providerCall(
                  () => provider.search(searchInput)
                );
                matches = listFrom(rawMatches, ['results', 'items', 'data', 'matches']);
              } catch (error) {
                errors.push({stage: 'search', reason: providerReason(error)});
              }
              // Several pre-SearchOptions providers throw when handed the
              // canonical object (for example they call query.replace()). A
              // failure must not suppress the bounded legacy string attempt.
              if (!matches.length) {
                try {
                  const legacyOptions = {dub, year: releaseYear, media};
                  const rawMatches = await providerCall(
                    () => provider.search(title, legacyOptions)
                  );
                  matches = listFrom(rawMatches, ['results', 'items', 'data', 'matches']);
                } catch (error) {
                  errors.push({stage: 'search', reason: providerReason(error)});
                }
              }
              matches.slice(0, 40).forEach((item, index) => {
                if (!item || typeof item !== 'object') return;
                const titleScore = score(candidateTitle(item), title);
                const mediaId = valueFrom(item, ['anilistId', 'aniListId', 'idAniList']);
                const idBonus = Number(mediaId) === media.id ? 2000 : 0;
                const providerOrderBonus = Math.max(0, 39 - index);
                const points = titleScore + idBonus + providerOrderBonus;
                const key = candidateKey(item);
                const existing = candidates.get(key);
                if (!existing || points > existing.points) {
                  candidates.set(key, {item, points});
                }
              });
              if (Array.from(candidates.values()).some(item => item.points >= 1000)) break;
            }
            const rankedCandidates = Array.from(candidates.values())
              .sort((left, right) => right.points - left.points)
              .slice(0, 4);
            if (!rankedCandidates.length) continue;
            foundTitle = true;
            let selected = null;
            let episode = null;
            for (const candidate of rankedCandidates) {
              let episodes = listFrom(candidate.item, ['episodes']);
              const identifier = valueFrom(candidate.item, [
                'id', 'animeId', 'mediaId', 'providerId', 'slug', 'url', 'link',
              ]);
              if (!episodes.length && identifier != null) {
                try {
                  const rawEpisodes = await providerCall(
                    () => provider.findEpisodes(identifier)
                  );
                  episodes = listFrom(rawEpisodes, [
                    'episodes', 'items', 'results', 'data', 'entries',
                  ]);
                } catch (error) {
                  errors.push({stage: 'episodes', reason: providerReason(error)});
                  // A bounded object-shape retry covers providers that adopted
                  // search-result objects before Seanime standardized the ID
                  // argument. Network failures are never repeated.
                  const message = String(error && error.message || error);
                  if (/argument|undefined|null|property|object|expected/i.test(message)) {
                    try {
                      const rawEpisodes = await providerCall(
                        () => provider.findEpisodes(candidate.item)
                      );
                      episodes = listFrom(rawEpisodes, [
                        'episodes', 'items', 'results', 'data', 'entries',
                      ]);
                    } catch (fallbackError) {
                      errors.push({
                        stage: 'episodes',
                        reason: providerReason(fallbackError),
                      });
                    }
                  }
                }
              }
              episode = episodes.find(
                item => Math.abs(episodeNumberOf(item) - episodeNumber) < 0.01
              );
              if (!episode && episodes.length === 1 && episodeNumber === 1) {
                episode = episodes[0];
              }
              if (episode) {
                selected = candidate;
                break;
              }
            }
            if (!selected || !episode) continue;
            foundEpisode = true;
            const configuredServers = settings.episodeServers || settings.servers;
            let servers = Array.isArray(configuredServers) && configuredServers.length
              ? configuredServers.slice(0, 6) : ['default'];
            const serverName = server => server && typeof server === 'object'
              ? String(server.name || server.label || server.id || server.value || 'Default')
              : String(server || 'Default');
            const serverValue = server => server && typeof server === 'object'
              ? (server.value || server.id || server.name || server.label) : server;
            const dubbedServers = servers.filter(server => /dub/i.test(serverName(server)));
            if (supportsDub && dubbedServers.length) {
              servers = dub ? dubbedServers : servers.filter(server => !/dub/i.test(serverName(server)));
            }
            // Providers commonly mutate instance headers/cookies while
            // resolving a server. Resolve in manifest order on the one
            // Provider instance so those stateful calls cannot race and so
            // stream ordering remains deterministic.
            for (const server of servers) {
              try {
                let resolved = null;
                try {
                  resolved = await providerCall(
                    () => provider.findEpisodeServer(episode, serverValue(server))
                  );
                } catch (error) {
                  const message = String(error && error.message || error);
                  errors.push({stage: 'server', reason: providerReason(error)});
                  // Seanime's current contract passes the episode object. A
                  // small number of legacy providers expect its ID instead;
                  // retry only argument-shape errors so network failures are
                  // not repeated three times.
                  if (/argument|undefined|null|property|\\bid\\b|object/i.test(message)) {
                    try {
                      resolved = await providerCall(
                        () => provider.findEpisodeServer(
                          episode.id || episode.url || episode,
                          serverValue(server),
                        )
                      );
                    } catch (fallbackError) {
                      errors.push({
                        stage: 'server',
                        reason: providerReason(fallbackError),
                      });
                    }
                  }
                }
                if (!resolved) continue;
                const resolvedHeaders = resolved &&
                  (resolved.headers || resolved.requestHeaders || resolved.responseHeaders);
                const serverHeaders = resolvedHeaders && typeof resolvedHeaders === 'object'
                  ? resolvedHeaders : {};
                let sources = listFrom(resolved, [
                  'videoSources', 'sources', 'streams', 'videos', 'links',
                ]);
                if (!sources.length && (typeof resolved === 'string' || resolved.url || resolved.file || resolved.src || resolved.link)) {
                  sources = [resolved];
                }
                for (const rawSource of sources.slice(0, 20)) {
                  const source = typeof rawSource === 'string' ? {url: rawSource} : rawSource;
                  if (!source || typeof source !== 'object') continue;
                  const bases = [source.baseUrl, resolved.baseUrl, resolved.url, episode.url, selected.item.url];
                  const url = toHttps(
                    source.url || source.file || source.src || source.link ||
                      source.href || source.uri || source.manifest ||
                      source.playlist || source.streamUrl || source.hls,
                    bases,
                  );
                  if (!url) continue;
                  const subtitles = listFrom(
                    source.subtitles || source.tracks || source.captions,
                    ['subtitles', 'tracks', 'captions'],
                  ).concat(listFrom(
                    resolved.subtitles || resolved.tracks || resolved.captions,
                    ['subtitles', 'tracks', 'captions'],
                  ));
                  const english = englishTrack(subtitles);
                  const subtitleUrl = english && toHttps(
                    english.url || english.file || english.src || english.link ||
                      english.href || english.uri || english.subtitleUrl,
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
              } catch (error) {
                errors.push({stage: 'server', reason: providerReason(error)});
              }
            }
          }
          if (!output.length) {
            const failure = errors.length
              ? errors[errors.length - 1]
              : {stage: foundEpisode ? 'server' : (foundTitle ? 'episodes' : 'search'), reason: 'empty_result'};
            const marker = ' [stage=' + failure.stage + '; reason=' + failure.reason + ']';
            if (!foundTitle) throw new Error('NO_MATCH: This provider has no matching title.' + marker);
            if (!foundEpisode) throw new Error('NO_MATCH: This provider has no matching episode.' + marker);
            throw new Error('NO_STREAM: The provider found the episode but returned no compatible stream.' + marker);
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
    for (final timer in sleepTimers.values) {
      timer.cancel();
    }
    sleepTimers.clear();
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
  Duration? maximumOverallTimeout,
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
  final requestedTimeout = addonRequestTimeout(
    options['timeout'],
    maximum: maximumOverallTimeout ?? const Duration(seconds: 12),
  );
  final effectiveOverallTimeout = overallTimeout == null
      ? requestedTimeout
      : requestedTimeout < overallTimeout
      ? requestedTimeout
      : overallTimeout;
  final method = '${options['method'] ?? 'GET'}'.toUpperCase();
  if (!const {
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  }.contains(method)) {
    throw const FormatException(
      'The provider request uses an unsupported HTTP method.',
    );
  }
  final redirectMode = '${options['redirect'] ?? 'follow'}'.toLowerCase();
  if (!const {'follow', 'manual', 'error'}.contains(redirectMode)) {
    throw const FormatException('Invalid provider redirect mode.');
  }
  var headers = Map<String, String>.from(
    sanitizeAddonHeaders(
      options['headers'],
      defaultUserAgent: 'TetoTV addon runtime',
    ),
  );
  String? body;
  final rawBody = options['body'];
  if (rawBody != null) {
    body = rawBody is String ? rawBody : jsonEncode(rawBody);
    if (rawBody is! String &&
        !headers.keys.any(
          (key) => key.toLowerCase() == HttpHeaders.contentTypeHeader,
        )) {
      headers[HttpHeaders.contentTypeHeader] = 'application/json';
    }
  }
  headers = Map.unmodifiable(headers);
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
  final overallDeadline = Timer(
    effectiveOverallTimeout,
    () => cancelToken.cancel('Provider request deadline exceeded.'),
  );
  Response<ResponseBody>? response;
  String responseText = '';
  var currentMethod = method;
  var redirected = false;
  try {
    for (var redirect = 0; ; redirect++) {
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
      if (!_isAddonRedirectStatus(status) || location == null) break;
      if (redirectMode == 'manual') break;
      if (redirectMode == 'error') {
        throw const HttpException(
          'Provider request received a redirect in error mode.',
        );
      }
      if (redirect >= 4) {
        throw const HttpException('Provider request exceeded redirect limit.');
      }
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
      if ((status == 303 &&
              currentMethod != 'GET' &&
              currentMethod != 'HEAD') ||
          ((status == 301 || status == 302) && currentMethod == 'POST')) {
        currentMethod = 'GET';
        body = null;
        headers = Map.unmodifiable(
          Map<String, String>.from(headers)..removeWhere(
            (key, _) => key.toLowerCase() == HttpHeaders.contentTypeHeader,
          ),
        );
      }
      currentUri = redirectUri;
      redirected = true;
      await validatePublicNetworkTarget(currentUri);
      cancellation?.throwIfCancelled();
    }
  } finally {
    overallDeadline.cancel();
    removeCancellationListener?.call();
    dio.close(force: true);
  }
  final rawResponseHeaders = sanitizeAddonResponseHeaders(response.headers.map);
  final responseHeaders = Map<String, String>.unmodifiable({
    for (final entry in rawResponseHeaders.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value.first,
  });
  final declaredLength = int.tryParse(
    response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
  );
  return {
    'status': response.statusCode ?? 0,
    'statusText': response.statusMessage ?? '',
    'method': currentMethod,
    'url': currentUri.toString(),
    'ok': (response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 300,
    'redirected': redirected,
    'contentType': response.headers.value(HttpHeaders.contentTypeHeader) ?? '',
    'contentLength': declaredLength ?? utf8.encode(responseText).length,
    'body': responseText,
    // HLS expansion must reuse the post-redirect header set. In particular,
    // credentials supplied for one origin cannot follow a master-playlist
    // redirect and then leak to that other origin's variant URLs.
    'requestHeaders': headers,
    'headers': responseHeaders,
    'rawHeaders': rawResponseHeaders,
    'cookies': _addonResponseCookies(response.headers),
  };
}

/// Seanime FetchOptions.timeout is expressed in seconds. Keep every request
/// inside both its requested budget and TetoTV's remaining provider deadline.
Duration addonRequestTimeout(
  Object? raw, {
  Duration maximum = const Duration(seconds: 12),
}) {
  final numeric = raw is num ? raw.toDouble() : double.tryParse('$raw');
  final requested = numeric != null && numeric.isFinite && numeric > 0
      ? Duration(milliseconds: (numeric * 1000).round())
      : maximum;
  const minimum = Duration(milliseconds: 100);
  if (maximum <= Duration.zero) return minimum;
  if (requested < minimum) return minimum < maximum ? minimum : maximum;
  return requested > maximum ? maximum : requested;
}

/// Seanime's `$sleep(milliseconds)` is synchronous from a provider author's
/// perspective, but TetoTV implements it as a host-backed promise barrier so a
/// sleeping addon does not block cancellation or the Dart isolate. Individual
/// waits are clamped while the aggregate provider runtime remains protected by
/// its normal deadline.
Duration addonSleepDuration(
  Object? raw, {
  required Duration remaining,
  Duration maximum = const Duration(seconds: 1),
}) {
  final numeric = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (numeric == null || !numeric.isFinite || numeric <= 0) {
    return Duration.zero;
  }
  if (remaining <= Duration.zero || maximum <= Duration.zero) {
    return Duration.zero;
  }
  final requested = Duration(milliseconds: numeric.ceil());
  final bounded = requested > maximum ? maximum : requested;
  return bounded > remaining ? remaining : bounded;
}

bool _isAddonRedirectStatus(int status) =>
    status == 301 ||
    status == 302 ||
    status == 303 ||
    status == 307 ||
    status == 308;

/// Bounds response metadata before it crosses from an untrusted server into
/// the provider VM. Multiple values remain separate to match Seanime's
/// `rawHeaders` contract; [FetchResponse.headers] uses the first value.
Map<String, List<String>> sanitizeAddonResponseHeaders(
  Object? raw, {
  int maximumValueLength = 4096,
}) {
  if (raw is! Map) return const {};
  final result = <String, List<String>>{};
  final seen = <String>{};
  var totalLength = 0;
  for (final entry in raw.entries.take(48)) {
    final key = '${entry.key}'.trim();
    final lower = key.toLowerCase();
    if (key.isEmpty ||
        key.length > 80 ||
        !RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(key) ||
        seen.contains(lower)) {
      continue;
    }
    final sourceValues = entry.value is Iterable
        ? (entry.value as Iterable)
        : [entry.value];
    final values = <String>[];
    for (final rawValue in sourceValues.take(16)) {
      final value = '$rawValue'.trim();
      if (value.length > maximumValueLength ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        continue;
      }
      totalLength += key.length + value.length;
      if (totalLength > 32 * 1024) break;
      values.add(value);
    }
    if (values.isEmpty) continue;
    seen.add(lower);
    result[key] = List.unmodifiable(values);
    if (totalLength > 32 * 1024) break;
  }
  return Map.unmodifiable(result);
}

Map<String, String> _addonResponseCookies(Headers headers) {
  return parseAddonResponseCookies(
    headers.map[HttpHeaders.setCookieHeader] ?? const [],
  );
}

/// Parses only bounded, syntactically safe cookie name/value pairs. Cookie
/// attributes stay out of the provider-facing record, matching Seanime.
Map<String, String> parseAddonResponseCookies(Iterable<String> values) {
  final result = <String, String>{};
  for (final raw in values) {
    if (result.length >= 64) break;
    if (raw.length > 8192) continue;
    try {
      final cookie = Cookie.fromSetCookieValue(raw);
      if (cookie.name.isEmpty ||
          cookie.name.length > 256 ||
          !RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(cookie.name) ||
          cookie.value.length > 4096 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(cookie.value)) {
        continue;
      }
      result[cookie.name] = cookie.value;
    } on FormatException {
      // Ignore a malformed cookie without hiding the otherwise valid response.
    }
  }
  return Map.unmodifiable(result);
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
  async function fetch(url, options) {
    // Official Seanime providers call `$sleep(ms)` without awaiting it. Treat
    // those calls as a barrier before the next request so rate-limit pacing is
    // preserved without synchronously blocking QuickJS.
    if (typeof __tetoAwaitSleeps === 'function') await __tetoAwaitSleeps();
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
  function __tetoCreateFetchResponse(response) {
    const headers = Object.assign({}, response.headers || {});
    const headerValue = name => {
      const target = String(name).toLowerCase();
      for (const key of Object.keys(headers)) {
        if (key.toLowerCase() === target) return headers[key];
      }
      return null;
    };
    // Preserve Seanime's plain header record while remaining friendly to
    // providers written against the browser Headers API.
    Object.defineProperty(headers, 'get', {
      configurable: true,
      enumerable: false,
      value: headerValue,
    });
    const body = String(response.body || '');
    let parsedJson = null;
    try { parsedJson = body ? JSON.parse(body) : null; } catch (_) {}
    return {
      ok: response.ok === true || (response.status >= 200 && response.status < 300),
      status: response.status,
      statusText: String(response.statusText || ''),
      method: String(response.method || 'GET'),
      rawHeaders: Object.assign({}, response.rawHeaders || {}),
      url: String(response.url || ''),
      headers,
      cookies: Object.assign({}, response.cookies || {}),
      redirected: response.redirected === true,
      contentType: String(response.contentType || headerValue('content-type') || ''),
      contentLength: Number(response.contentLength || 0),
      body,
      // Seanime's extension FetchResponse intentionally exposes synchronous
      // body readers. `await response.text()` still works because awaiting a
      // non-Promise value is valid JavaScript.
      text: () => body,
      json: () => parsedJson,
    };
  }
  function __tetoNetworkFinish(id, response) {
    const pending = __tetoPending[id]; if (!pending) return;
    delete __tetoPending[id];
    pending.resolve(__tetoCreateFetchResponse(response));
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

  // Seanime exposes a small Node-compatible Buffer surface to providers.
  // Some marketplace extensions keep this as their base64 fallback even when
  // `atob` is available, so provide the same byte-indexable result and UTF-8
  // decoding behavior without importing Node's much larger runtime.
  if (typeof Buffer === 'undefined') {
    globalThis.Buffer = class Buffer extends Uint8Array {
      static from(value, encoding) {
        if (typeof value === 'string') {
          const normalized = String(encoding || 'utf8').toLowerCase().replace(/[-_]/g, '');
          if (normalized === 'base64') {
            const decoded = atob(value.replace(/-/g, '+').replace(/_/g, '/'));
            const bytes = new Buffer(decoded.length);
            for (let index = 0; index < decoded.length; index++) {
              bytes[index] = decoded.charCodeAt(index) & 255;
            }
            return bytes;
          }
          if (normalized === 'hex') {
            const clean = value.replace(/[^0-9a-f]/gi, '');
            const bytes = new Buffer(Math.floor(clean.length / 2));
            for (let index = 0; index < bytes.length; index++) {
              bytes[index] = parseInt(clean.slice(index * 2, index * 2 + 2), 16);
            }
            return bytes;
          }
          const encoded = unescape(encodeURIComponent(value));
          const bytes = new Buffer(encoded.length);
          for (let index = 0; index < encoded.length; index++) {
            bytes[index] = encoded.charCodeAt(index) & 255;
          }
          return bytes;
        }
        if (value instanceof ArrayBuffer) return new Buffer(new Uint8Array(value));
        if (ArrayBuffer.isView(value)) {
          return new Buffer(new Uint8Array(value.buffer, value.byteOffset, value.byteLength));
        }
        return new Buffer(value == null ? 0 : value);
      }

      static alloc(size, fill) {
        const bytes = new Buffer(Math.max(0, Number(size) || 0));
        if (fill != null) bytes.fill(typeof fill === 'number' ? fill : String(fill).charCodeAt(0));
        return bytes;
      }

      equals(other) {
        if (!other || this.length !== other.length) return false;
        for (let index = 0; index < this.length; index++) {
          if (this[index] !== other[index]) return false;
        }
        return true;
      }

      toString(encoding) {
        const normalized = String(encoding || 'utf8').toLowerCase().replace(/[-_]/g, '');
        if (normalized === 'base64') {
          let binary = '';
          for (let index = 0; index < this.length; index++) binary += String.fromCharCode(this[index]);
          return btoa(binary);
        }
        if (normalized === 'hex') {
          return Array.from(this).map(byte => byte.toString(16).padStart(2, '0')).join('');
        }
        let escaped = '';
        for (let index = 0; index < this.length; index++) {
          escaped += '%' + this[index].toString(16).padStart(2, '0');
        }
        try { return decodeURIComponent(escaped); } catch (_) {
          return Array.from(this).map(byte => String.fromCharCode(byte)).join('');
        }
      }
    };
    // Avoid class-field syntax because the packaged QuickJS engine supports a
    // wider range of extension payloads than it does newer JavaScript syntax.
    globalThis.Buffer.poolSize = 8192;
  }

  // Seanime's CryptoJS encoder contract returns byte-indexable data. The
  // bundled CryptoJS implementation returns its native WordArray instead.
  // Decorate that same object rather than replacing it with a plain array so
  // existing CryptoJS AES/encoder calls retain `words`, `sigBytes`, and all
  // WordArray methods while providers can safely use `.length` and `[index]`.
  if (typeof CryptoJS !== 'undefined' && CryptoJS.enc && CryptoJS.enc.Base64 &&
      !CryptoJS.enc.Base64.__tetoByteCompatible) {
    const originalBase64Parse = CryptoJS.enc.Base64.parse;
    CryptoJS.enc.Base64.parse = function(input) {
      const wordArray = originalBase64Parse.call(this, String(input || ''));
      const length = Math.max(0, Number(wordArray.sigBytes) || 0);
      Object.defineProperty(wordArray, 'length', {
        value: length, writable: false, configurable: true, enumerable: false,
      });
      for (let index = 0; index < length; index++) {
        Object.defineProperty(wordArray, index, {
          value: (wordArray.words[index >>> 2] >>> (24 - (index % 4) * 8)) & 255,
          writable: false,
          configurable: true,
          enumerable: true,
        });
      }
      return wordArray;
    };
    Object.defineProperty(CryptoJS.enc.Base64, '__tetoByteCompatible', {
      value: true, enumerable: false,
    });
  }

  if (typeof URLSearchParams === 'undefined') {
    globalThis.URLSearchParams = class URLSearchParams {
      constructor(input, onChange) {
        this.pairs = [];
        this.onChange = typeof onChange === 'function' ? onChange : function() {};
        if (typeof input === 'string') {
          String(input).replace(/^\?/, '').split('&').forEach(part => {
            if (!part) return;
            const split = part.indexOf('=');
            const decode = value => decodeURIComponent(String(value).replace(/\+/g, ' '));
            this.pairs.push([
              decode(split < 0 ? part : part.slice(0, split)),
              decode(split < 0 ? '' : part.slice(split + 1)),
            ]);
          });
        } else if (Array.isArray(input)) {
          input.forEach(entry => this.pairs.push([String(entry[0]), String(entry[1])]));
        } else if (input && typeof input === 'object') {
          Object.keys(input).forEach(key => this.pairs.push([String(key), String(input[key])]));
        }
      }
      changed() { this.onChange(this.toString()); }
      append(key, value) { this.pairs.push([String(key), String(value)]); this.changed(); }
      set(key, value) {
        const target = String(key);
        const next = [];
        let replaced = false;
        this.pairs.forEach(entry => {
          if (entry[0] !== target) next.push(entry);
          else if (!replaced) { next.push([target, String(value)]); replaced = true; }
        });
        if (!replaced) next.push([target, String(value)]);
        this.pairs = next;
        this.changed();
      }
      get(key) {
        const item = this.pairs.find(entry => entry[0] === String(key));
        return item ? item[1] : null;
      }
      getAll(key) {
        return this.pairs.filter(entry => entry[0] === String(key)).map(entry => entry[1]);
      }
      has(key) { return this.pairs.some(entry => entry[0] === String(key)); }
      delete(key) { this.pairs = this.pairs.filter(entry => entry[0] !== String(key)); this.changed(); }
      sort() { this.pairs.sort((left, right) => left[0].localeCompare(right[0])); this.changed(); }
      forEach(callback) { this.pairs.forEach(entry => callback(entry[1], entry[0], this)); }
      entries() { return this.pairs[Symbol.iterator](); }
      keys() { return this.pairs.map(entry => entry[0])[Symbol.iterator](); }
      values() { return this.pairs.map(entry => entry[1])[Symbol.iterator](); }
      [Symbol.iterator]() { return this.entries(); }
      toString() {
        return this.pairs.map(entry => encodeURIComponent(entry[0]) + '=' + encodeURIComponent(entry[1])).join('&');
      }
    };
  }

  if (typeof URL === 'undefined') {
    globalThis.URL = class URL {
      constructor(value, base) {
        const input = String(value || '');
        let absolute = input;
        if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(absolute)) {
          const baseMatch = /^([a-z][a-z0-9+.-]*:)\/\/([^/?#]+)([^?#]*)(?:\?[^#]*)?(?:#.*)?$/i.exec(String(base || ''));
          if (!baseMatch) throw new TypeError('Invalid URL');
          const origin = baseMatch[1] + '//' + baseMatch[2];
          if (absolute.startsWith('//')) absolute = baseMatch[1] + absolute;
          else if (absolute.startsWith('/')) absolute = origin + absolute;
          else if (absolute.startsWith('?') || absolute.startsWith('#')) {
            absolute = origin + (baseMatch[3] || '/') + absolute;
          } else {
            const directory = (baseMatch[3] || '/').replace(/[^/]*$/, '');
            absolute = origin + directory + absolute;
          }
        }
        const match = /^([a-z][a-z0-9+.-]*):\/\/([^/?#]+)([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/i.exec(absolute);
        if (!match) throw new TypeError('Invalid URL');
        this.protocol = match[1] ? match[1] + ':' : '';
        this.host = match[2] || '';
        this.hostname = this.host.replace(/^\[|\]$/g, '').split(':')[0];
        this.port = this.host.includes(':') ? this.host.split(':').pop() : '';
        this.origin = this.protocol && this.host ? this.protocol + '//' + this.host : '';
        const path = (match[3] || '/').split('/').reduce((parts, part) => {
          if (part === '..') parts.pop();
          else if (part !== '.') parts.push(part);
          return parts;
        }, []).join('/');
        this.pathname = path.startsWith('/') ? path : '/' + path;
        this.search = match[4] ? '?' + match[4] : '';
        this.hash = match[5] ? '#' + match[5] : '';
        this.sync = () => {
          this.href = this.origin + this.pathname + this.search + this.hash;
        };
        this.searchParams = new URLSearchParams(match[4] || '', query => {
          this.search = query ? '?' + query : '';
          this.sync();
        });
        this.sync();
      }
      toString() { return this.href; }
      toJSON() { return this.href; }
    };
  }

  function __tetoElements(value) {
    if (value == null) return [];
    if (Array.isArray(value.__tetoNodes)) return value.__tetoNodes.slice();
    if (Array.isArray(value)) return value.filter(Boolean);
    if (typeof value === 'string') return Array.from(__tetoParseDocument(value).children || []);
    if (typeof value.length === 'number' && !value.nodeType) return Array.from(value).filter(Boolean);
    return [value];
  }

  function __tetoUnique(values) {
    return values.filter((value, index, all) => value && all.indexOf(value) === index);
  }

  function __tetoMatches(node, selector) {
    if (!node || node.nodeType !== 1 || typeof node.matches !== 'function') return false;
    try { return node.matches(String(selector || '*')); } catch (_) { return false; }
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

  function __tetoSelection(value, previous) {
    const elements = __tetoUnique(__tetoElements(value));
    const selection = {};
    Object.defineProperty(selection, '__tetoNodes', {value: elements, enumerable: false});
    Object.defineProperty(selection, '__tetoPrevious', {value: previous || null, enumerable: false});
    elements.forEach((node, index) => {
      Object.defineProperty(selection, index, {value: node, enumerable: false});
    });
    selection.toArray = () => elements.slice();
    selection.get = index => index == null ? elements.slice() : elements[index < 0 ? elements.length + index : index];
    selection.length = () => elements.length;
    selection.eq = index => __tetoSelection(selection.get(index), selection);
    selection.first = () => selection.eq(0);
    selection.last = () => selection.eq(-1);
    selection.each = callback => {
      elements.forEach((node, index) => {
        const item = __tetoSelection(node, selection);
        callback.call(item, index, item);
      });
      return selection;
    };
    selection.map = callback => elements.map((node, index) => {
      const item = __tetoSelection(node, selection);
      return callback.call(item, index, item);
    });
    selection.text = () => elements.map(node => node.textContent || '').join('');
    selection.html = () => elements[0] ? (elements[0].innerHTML ?? null) : null;
    selection.attr = name => {
      if (!elements[0] || typeof elements[0].getAttribute !== 'function') return undefined;
      const value = elements[0].getAttribute(name);
      return value == null ? undefined : value;
    };
    selection.attrs = () => {
      const result = {};
      Array.from((elements[0] && elements[0].attributes) || []).forEach(attribute => {
        result[attribute.name] = attribute.value;
      });
      return result;
    };
    selection.data = name => {
      if (name != null) {
        return selection.attr('data-' + String(name).replace(/[A-Z]/g, letter => '-' + letter.toLowerCase()));
      }
      const result = {};
      Object.keys(selection.attrs()).filter(key => key.startsWith('data-')).forEach(key => {
        result[key] = selection.attrs()[key];
      });
      return result;
    };
    selection.val = () => elements[0] ? elements[0].value : undefined;
    selection.hasClass = name => !!(elements[0] && elements[0].classList && elements[0].classList.contains(name));
    selection.find = selector => __tetoSelection(
      elements.flatMap(node => __tetoSelect(node, selector)), selection
    );
    selection.children = selector => {
      const children = elements.flatMap(node => Array.from(node.children || []));
      return __tetoSelection(
        selector ? children.filter(node => __tetoMatches(node, selector)) : children,
        selection,
      );
    };
    selection.contents = () => __tetoSelection(
      elements.flatMap(node => Array.from(node.childNodes || [])), selection
    );
    selection.contentsFiltered = selector => String(selector || '')
      ? selection.children(selector)
      : selection.contents();
    selection.parent = selector => {
      const parents = elements.map(node => node.parentElement).filter(Boolean);
      return __tetoSelection(
        selector ? parents.filter(node => __tetoMatches(node, selector)) : parents,
        selection,
      );
    };
    selection.parents = selector => {
      const parents = [];
      elements.forEach(node => {
        for (let parent = node.parentElement; parent; parent = parent.parentElement) {
          if (!selector || __tetoMatches(parent, selector)) parents.push(parent);
        }
      });
      return __tetoSelection(parents, selection);
    };
    selection.parentsUntil = (selector, until) => {
      const parents = [];
      elements.forEach(node => {
        for (let parent = node.parentElement; parent; parent = parent.parentElement) {
          if (__tetoMatches(parent, until || selector)) break;
          if (!until || __tetoMatches(parent, selector)) parents.push(parent);
        }
      });
      return __tetoSelection(parents, selection);
    };
    selection.closest = selector => {
      const matches = [];
      if (!selector) return __tetoSelection(matches, selection);
      elements.forEach(node => {
        for (let current = node; current; current = current.parentElement) {
          if (__tetoMatches(current, selector)) { matches.push(current); break; }
        }
      });
      return __tetoSelection(matches, selection);
    };
    selection.filter = selector => __tetoSelection(elements.filter((node, index) =>
      typeof selector === 'function'
        ? !!selector(index, __tetoSelection(node, selection))
        : __tetoMatches(node, selector)
    ), selection);
    selection.not = selector => __tetoSelection(elements.filter((node, index) =>
      typeof selector === 'function'
        ? !selector(index, __tetoSelection(node, selection))
        : !__tetoMatches(node, selector)
    ), selection);
    selection.is = selector => elements.some((node, index) =>
      typeof selector === 'function'
        ? !!selector(index, __tetoSelection(node, selection))
        : __tetoMatches(node, selector)
    );
    selection.has = selector => __tetoSelection(elements.filter(node =>
      __tetoSelect(node, selector).length > 0
    ), selection);
    const sibling = (direction, selector) => {
      const values = elements.map(node => node[direction]).filter(Boolean);
      return __tetoSelection(
        selector ? values.filter(node => __tetoMatches(node, selector)) : values,
        selection,
      );
    };
    const siblingAll = (direction, selector, until) => {
      const values = [];
      elements.forEach(node => {
        for (let current = node[direction]; current; current = current[direction]) {
          if (until && __tetoMatches(current, until)) break;
          if (!selector || __tetoMatches(current, selector)) values.push(current);
        }
      });
      return __tetoSelection(values, selection);
    };
    selection.next = selector => sibling('nextElementSibling', selector);
    selection.prev = selector => sibling('previousElementSibling', selector);
    selection.nextAll = selector => siblingAll('nextElementSibling', selector);
    selection.prevAll = selector => siblingAll('previousElementSibling', selector);
    selection.nextUntil = (selector, until) => siblingAll(
      'nextElementSibling', until ? selector : null, until || selector
    );
    selection.prevUntil = (selector, until) => siblingAll(
      'previousElementSibling', until ? selector : null, until || selector
    );
    selection.siblings = selector => {
      const values = elements.flatMap(node =>
        Array.from((node.parentElement && node.parentElement.children) || [])
          .filter(sibling => sibling !== node)
      );
      return __tetoSelection(
        selector ? values.filter(node => __tetoMatches(node, selector)) : values,
        selection,
      );
    };
    selection.end = () => previous || __tetoSelection([]);
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

  globalThis.Doc = class Doc {
    constructor(source) {
      const document = __tetoParseDocument(String(source || ''));
      return __tetoSelection(document.documentElement || document);
    }
  };

  globalThis.__isOffline__ = false;
  globalThis.$getUserPreference = key => {
    const preferences = globalThis.__tetoUserPreferences || {};
    const name = String(key || '');
    return Object.prototype.hasOwnProperty.call(preferences, name)
      ? preferences[name]
      : undefined;
  };
  async function _makeRequest(url, options) {
    const response = await fetch(url, options || {});
    const body = await response.text();
    if (!response.ok) throw new Error('HTTP ' + response.status + ' for ' + url);
    return {status: response.status, headers: response.headers, body, data: body, text: body, url: response.url};
  }

  const __tetoPendingSleeps = Object.create(null);
  let __tetoSleepId = 0;
  let __tetoSleepTail = Promise.resolve();
  function $sleep(milliseconds) {
    const numeric = Number(milliseconds);
    if (!Number.isFinite(numeric) || numeric <= 0) return __tetoSleepTail;
    const wait = __tetoSleepTail.then(() => new Promise(resolve => {
      const id = String(++__tetoSleepId);
      __tetoPendingSleeps[id] = resolve;
      sendMessage('TetoSleep', JSON.stringify({id, milliseconds: numeric}));
    }));
    // Keep the shared barrier fulfilled even if a future bridge implementation
    // chooses to reject an individual wait.
    __tetoSleepTail = wait.catch(() => {});
    return wait;
  }
  function __tetoSleepFinish(id) {
    const resolve = __tetoPendingSleeps[id];
    if (!resolve) return;
    delete __tetoPendingSleeps[id];
    resolve();
  }
  async function __tetoAwaitSleeps() {
    let pending;
    do {
      pending = __tetoSleepTail;
      await pending;
    } while (pending !== __tetoSleepTail);
  }

  // Seanime-compatible scanner surface. This is an original, bounded
  // implementation of the public behavior exercised by community providers;
  // it does not embed Seanime source code.
  const __tetoNoiseWords = new Set([
    'the', 'a', 'an', 'of', 'to', 'in', 'for', 'on', 'with', 'at', 'by',
    'from', 'as', 'is', 'it', 'that', 'this', 'be', 'are', 'was', 'were',
    'no', 'wa', 'wo', 'ga', 'ni', 'de', 'ka', 'mo', 'ya', 'e', 'he',
    'anime', 'ova', 'ona', 'oad', 'tv', 'movie', 'nc', 'nced', 'ncop',
    'extras', 'ending', 'opening', 'preview', 'special', 'specials', 'sp',
    'finale', 'season', 'uncensored', 'censored', 'bluray',
  ]);
  const __tetoFormatWords = new Set([
    'ova', 'ona', 'oad', 'oav', 'sp', 'special', 'specials', 'movie',
    'film', 'tv', 'nc', 'nced', 'ncop', 'extras', 'opening', 'ending',
    'preview', 'finale',
  ]);
  // Standalone I and X are deliberately excluded because ordinary titles use
  // them too often for them to be reliable season markers.
  const __tetoRoman = Object.freeze({ii: 2, iii: 3, iv: 4, v: 5, vi: 6, vii: 7, viii: 8, ix: 9, xi: 11, xii: 12, xiii: 13});
  const __tetoOrdinalWords = {first: 1, second: 2, third: 3, fourth: 4, fifth: 5, sixth: 6, seventh: 7, eighth: 8, ninth: 9, tenth: 10};
  const __tetoIsRoman = value => Object.prototype.hasOwnProperty.call(
    __tetoRoman, value
  );

  function __tetoNumber(value, fallback) {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? Math.trunc(numeric) : fallback;
  }

  function extractSeasonNumber(value) {
    const text = String(value || '').toLowerCase();
    let match = text.match(/\b(?:season|series)\s*0*([0-9]{1,2})\b/);
    if (match) return Number(match[1]);
    match = text.match(/\bs\s*0*([0-9]{1,2})(?=\b|e[0-9])/);
    if (match) return Number(match[1]);
    match = text.match(/\b([0-9]{1,2})(?:st|nd|rd|th)\s+(?:season|series)\b/);
    if (match) return Number(match[1]);
    match = text.match(/\b(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+season\b/);
    if (match) return __tetoOrdinalWords[match[1]] || -1;
    match = text.match(/([0-9]{1,2})\s*(?:期|シーズン)/);
    if (match) return Number(match[1]);
    const romanSource = text.replace(
      /\b(?:act|arc|chapter|saga|hen|part|cour)[\s._:-]+(?:ii|iii|iv|v|vi|vii|viii|ix|xi|xii|xiii)\b/g,
      ' ',
    );
    match = romanSource.match(
      /(?:^|[\s.])(ii|iii|iv|v|vi|vii|viii|ix|xi|xii|xiii)(?:\s*$|[:,.'"]|\s+(?:s[0-9]|e[0-9]|part))/,
    );
    if (match) return __tetoRoman[match[1]] || -1;
    match = text.match(/(?:^|\s)([0-9]{1,2})\s*$/);
    if (match && !/(?:part|cour|special|sp|movie|ova|ona|oad)\s*[0-9]{1,2}\s*$/.test(text)) {
      const trailing = Number(match[1]);
      if (trailing >= 2 && trailing <= 10) return trailing;
    }
    return -1;
  }

  function extractPartNumber(value) {
    const text = String(value || '').toLowerCase();
    let match = text.match(/\b(?:part|cour)\s*([0-9]{1,2})\b/);
    if (!match) match = text.match(/\b([0-9]{1,2})(?:st|nd|rd|th)\s+(?:part|cour)\b/);
    if (match) return Number(match[1]);
    match = text.match(/\b(?:part|cour)\s+(ii|iii|iv|v|vi|vii|viii|ix|xi|xii|xiii)\b/);
    return match ? (__tetoRoman[match[1]] || -1) : -1;
  }

  function extractYear(value) {
    const match = String(value || '').match(/(?:\(|\b)(19[0-9]{2}|20[0-9]{2})(?:\)|\b)/);
    return match ? Number(match[1]) : -1;
  }

  function normalizeQuery(value) {
    return String(value || '').toLowerCase()
      // Expand macrons before Unicode decomposition removes their marks.
      .replace(/ō/g, 'ou').replace(/ū/g, 'uu')
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/@/g, 'a').replace(/×/g, ' x ')
      .replace(/꞉/g, ':').replace(/＊/g, ' * ')
      .replace(/\bthe animation\b/g, ' ')
      .replace(/\bthe\b/g, ' ').replace(/\bepisode\b/g, ' ')
      .replace(/\boad\b/g, ' ova ').replace(/\boav\b/g, ' ova ')
      .replace(/\bspecials?\b/g, ' sp ').replace(/\(\s*tv\s*\)/g, ' ')
      .replace(/&/g, ' and ')
      // Possessives need a token boundary; deleting the apostrophe first would
      // incorrectly merge e.g. "Magus's" into "maguss".
      .replace(/[’'`]s\b/g, ' ')
      .replace(/[’'`"“”]/g, '')
      .replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
  }

  function normalizeTitle(value) {
    const original = String(value || '');
    const season = extractSeasonNumber(original);
    const part = extractPartNumber(original);
    const year = extractYear(original);
    // Strip Japanese season suffixes before the ASCII-only query pass turns
    // the suffix into whitespace and leaves a misleading bare number behind.
    const titleForNormalization = original.replace(
      /[0-9]{1,2}\s*(?:期|シーズン)/g,
      ' ',
    );
    let normalized = normalizeQuery(titleForNormalization)
      .replace(/\b(?:season|series)\s*0*[0-9]{1,2}\b/g, ' ')
      .replace(/\bs\s*0*[0-9]{1,2}(?=\b|e[0-9])/g, ' ')
      .replace(/\b[0-9]{1,2}(?:st|nd|rd|th)\s+(?:season|series)\b/g, ' ')
      .replace(/\b(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\s+season\b/g, ' ')
      .replace(/\b(?:part|cour)\s*(?:[0-9]{1,2}|ii|iii|iv|v|vi|vii|viii|ix|xi|xii|xiii)\b/g, ' ')
      .replace(/\b[0-9]{1,2}(?:st|nd|rd|th)\s+(?:part|cour)\b/g, ' ')
      .replace(/\s+/g, ' ').trim();
    const tokens = normalized ? normalized.split(' ').slice(0, 64) : [];
    let base = tokens.filter(token =>
      !__tetoFormatWords.has(token) && !__tetoIsRoman(token)
    ).join(' ');
    base = base.replace(/\b[0-9]+$/, '').replace(/\s+/g, ' ').trim();
    const denoised = base.split(' ').filter(token => token && !__tetoNoiseWords.has(token)).join(' ');
    return {
      original,
      normalized,
      cleanBaseTitle: base,
      denoisedTitle: denoised,
      tokens,
      season,
      part,
      year,
      isMain: false,
    };
  }

  function getSignificantTokens(value) {
    const tokens = Array.isArray(value) ? value : normalizeTitle(value).tokens;
    return tokens.slice(0, 64).filter(token => String(token).length > 1 && !__tetoNoiseWords.has(String(token).toLowerCase()));
  }

  function compareTitles(left, right) {
    const a = normalizeTitle(left).tokens;
    const b = new Set(normalizeTitle(right).tokens);
    if (!a.length || !b.size) return 0;
    let total = 0; let matched = 0;
    a.forEach(token => {
      const weight = __tetoNoiseWords.has(token) ? 0.3 : (/^(?:19|20)[0-9]{2}$/.test(token) ? 0.5 : 1);
      total += weight;
      if (b.has(token)) matched += weight;
    });
    return total ? matched / total : 0;
  }

  function __tetoSimilarity(left, right) {
    return Math.min(compareTitles(left, right), compareTitles(right, left));
  }

  function sanitizeQuery(value) {
    return String(value || '').replace(/[()[\]{}|"'~*?\\^!]/g, ' ')
      .replace(/\s{2,}/g, ' ').trim();
  }

  function buildSearchQuery(value) {
    const normalized = normalizeTitle(value);
    return sanitizeQuery(normalized.denoisedTitle || normalized.cleanBaseTitle || normalized.normalized);
  }

  function buildAdvancedQuery(values) {
    const unique = [];
    (Array.isArray(values) ? values : []).slice(0, 32).forEach(value => {
      const query = buildSearchQuery(value);
      if (query && !unique.includes(query)) unique.push(query);
    });
    if (!unique.length) return '';
    return unique.length === 1 ? unique[0] : '(' + unique.join(' | ') + ')';
  }

  function __tetoOrdinal(value) {
    const number = Math.abs(value);
    const suffix = number % 100 >= 11 && number % 100 <= 13
      ? 'th' : ({1: 'st', 2: 'nd', 3: 'rd'}[number % 10] || 'th');
    return String(value) + suffix;
  }

  function buildSeasonQuery(title, value) {
    const base = buildSearchQuery(title);
    const season = __tetoNumber(value, -1);
    if (!base || season <= 1) return base;
    return '(' + [base + ' S' + String(season).padStart(2, '0'), base + ' S' + season,
      base + ' Season ' + season, base + ' ' + __tetoOrdinal(season) + ' Season'].join(' | ') + ')';
  }

  function buildPartQuery(title, value) {
    const base = buildSearchQuery(title);
    const part = __tetoNumber(value, -1);
    if (!base || part <= 1) return base;
    const roman = Object.keys(__tetoRoman).find(key => __tetoRoman[key] === part);
    const variants = [base + ' Part ' + part];
    if (roman) variants.push(base + ' Part ' + roman.toUpperCase());
    variants.push(base + ' ' + __tetoOrdinal(part) + ' Cour');
    return '(' + variants.join(' | ') + ')';
  }

  function buildSmartSearchTitles(values) {
    const titles = [];
    const seen = new Set();
    let season = -1; let part = -1;
    const add = value => {
      const title = String(value || '').trim();
      const key = title.toLowerCase();
      if (title && !seen.has(key) && titles.length < 64) {
        seen.add(key); titles.push(title);
      }
    };
    const addNormalizedVariants = value => {
      const normalized = normalizeTitle(value);
      add(sanitizeQuery(
        normalized.denoisedTitle || normalized.cleanBaseTitle || normalized.normalized
      ));
      add(sanitizeQuery(normalized.cleanBaseTitle));
      return normalized;
    };
    (Array.isArray(values) ? values : [values]).slice(0, 32).forEach(value => {
      const original = String(value || '');
      if (!original) return;
      const normalized = addNormalizedVariants(original);
      if (season <= 0 && normalized.season > 0) season = normalized.season;
      if (part <= 0 && normalized.part > 0) part = normalized.part;
      [original.indexOf(':'), original.indexOf(' - ')].forEach(index => {
        if (index >= 5) addNormalizedVariants(original.substring(0, index));
      });
    });
    return {titles, season, part};
  }

  function filterBySimilarity(items, query) {
    return (Array.isArray(items) ? items : []).slice(0, 200).sort((left, right) =>
      __tetoSimilarity(right && (right.title || right.name), query) -
      __tetoSimilarity(left && (left.title || left.name), query)
    );
  }

  function findBestMatch(target, candidates) {
    let best = ''; let score = -1;
    (Array.isArray(candidates) ? candidates : []).slice(0, 200).forEach(candidate => {
      if (typeof candidate !== 'string') return;
      const next = compareTitles(target, candidate);
      if (next > score) { best = candidate; score = next; }
    });
    return best;
  }

  globalThis.$scannerUtils = {
    normalizeTitle,
    extractPartNumber,
    extractSeasonNumber,
    extractYear,
    compareTitles,
    findBestMatch,
    getSignificantTokens,
    buildSearchQuery,
    buildAdvancedQuery,
    sanitizeQuery,
    buildSeasonQuery,
    buildPartQuery,
    buildSmartSearchTitles,
    // Compatibility aliases retained for providers predating the current
    // scanner contract.
    normalizeQuery,
    filterBySimilarity,
    similarity: __tetoSimilarity,
    compareTwoStrings: __tetoSimilarity,
  };

  // A bounded invocation-local store lets providers cache repeated title
  // attempts without persisting third-party data or sharing it across
  // providers. JSON cloning prevents callers from mutating stored values by
  // reference while keeping memory use measurable and bounded.
  function __tetoCreateStore() {
    const entries = Object.create(null);
    let totalSize = 0;
    const keyOf = value => {
      const key = String(value == null ? '' : value);
      if (!key || key.length > 128 || /[\u0000-\u001f]/.test(key)) {
        throw new Error('Store key is invalid');
      }
      return key;
    };
    const encode = value => {
      const encoded = JSON.stringify(value);
      if (encoded === undefined || encoded.length > 131072) {
        throw new Error('Store value exceeds its limit');
      }
      return encoded;
    };
    const decode = encoded => encoded === undefined ? undefined : JSON.parse(encoded);
    const set = (rawKey, value) => {
      const key = keyOf(rawKey);
      const encoded = encode(value);
      if (!Object.prototype.hasOwnProperty.call(entries, key) && Object.keys(entries).length >= 64) {
        throw new Error('Store entry limit exceeded');
      }
      const nextSize = totalSize - (entries[key] ? entries[key].length : 0) + encoded.length;
      if (nextSize > 262144) throw new Error('Store total size limit exceeded');
      entries[key] = encoded; totalSize = nextSize;
    };
    const api = {
      set,
      get(key) { return decode(entries[keyOf(key)]); },
      getUnsafe(key) { return decode(entries[keyOf(key)]); },
      has(key) { return Object.prototype.hasOwnProperty.call(entries, keyOf(key)); },
      getOrSet(key, factory) {
        const normalized = keyOf(key);
        if (Object.prototype.hasOwnProperty.call(entries, normalized)) return decode(entries[normalized]);
        const value = typeof factory === 'function' ? factory() : factory;
        set(normalized, value); return decode(entries[normalized]);
      },
      setIfLessThanLimit(key, value, maximum) {
        const limit = Math.max(0, Math.min(64, __tetoNumber(maximum, 0)));
        if (!api.has(key) && Object.keys(entries).length >= limit) return false;
        set(key, value); return true;
      },
      marshalJSON(value) { return encode(value); },
      unmarshalJSON(value) {
        const decoded = JSON.parse(String(value || '{}'));
        if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) return;
        Object.keys(decoded).slice(0, 64).forEach(key => set(key, decoded[key]));
      },
      reset() { Object.keys(entries).forEach(key => delete entries[key]); totalSize = 0; },
      clear() { api.reset(); },
      drop() { api.reset(); },
      remove(key) {
        const normalized = keyOf(key);
        if (entries[normalized]) totalSize -= entries[normalized].length;
        delete entries[normalized];
      },
      keys() { return Object.keys(entries); },
      values() { return Object.keys(entries).map(key => decode(entries[key])); },
      valuesUnsafe() { return api.values(); },
      getAll() {
        const result = Object.create(null);
        Object.keys(entries).forEach(key => { result[key] = decode(entries[key]); });
        return result;
      },
      getAllUnsafe() { return api.getAll(); },
    };
    return Object.freeze(api);
  }
  globalThis.$store = __tetoCreateStore();
  globalThis.$storage = __tetoCreateStore();
''';
