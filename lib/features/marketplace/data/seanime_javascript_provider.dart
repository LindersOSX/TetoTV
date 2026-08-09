import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';

abstract interface class WebStreamingProvider {
  String get id;
  String get name;
  Future<List<WebStreamResult>> streams(EpisodeReference episode);
}

class SeanimeJavascriptProvider implements WebStreamingProvider {
  const SeanimeJavascriptProvider(this.addon);

  final InstalledStreamingAddon addon;

  @override
  String get id => addon.manifest.id;

  @override
  String get name => addon.manifest.name;

  @override
  Future<List<WebStreamResult>> streams(EpisodeReference episode) async {
    final raw = await Isolate.run(
      () => _executeProvider({
        'id': addon.manifest.id,
        'name': addon.manifest.name,
        'payload': addon.payload,
        'title': episode.title,
        'titles': episode.alternativeTitles,
        'episode': episode.episode,
      }),
    ).timeout(const Duration(seconds: 28));
    final results = <WebStreamResult>[];
    final publicHosts = <String, bool>{};
    Future<bool> allowed(Uri uri) async {
      final known = publicHosts[uri.host];
      if (known != null) return known;
      try {
        await validatePublicNetworkTarget(uri);
        publicHosts[uri.host] = true;
        return true;
      } catch (_) {
        publicHosts[uri.host] = false;
        return false;
      }
    }

    for (final item in raw) {
      final uri = safePublicHttpsUri(item['url']);
      if (uri == null || !await allowed(uri)) continue;
      final candidateSubtitle = safePublicHttpsUri(item['subtitleUrl']);
      final subtitle =
          candidateSubtitle != null && await allowed(candidateSubtitle)
          ? candidateSubtitle
          : null;
      final headers = <String, String>{};
      final rawHeaders = item['headers'];
      if (rawHeaders is Map) {
        for (final entry in rawHeaders.entries.take(24)) {
          final key = '${entry.key}'.trim();
          final value = '${entry.value}'.trim();
          if (key.isNotEmpty && key.length <= 80 && value.length <= 1024) {
            headers[key] = value;
          }
        }
      }
      results.add(
        WebStreamResult(
          providerId: id,
          providerName: name,
          title: '${item['title'] ?? name}',
          uri: uri,
          quality: item['quality'] as String?,
          headers: headers,
          subtitleUri: subtitle,
          subtitleLanguage: item['subtitleLanguage'] as String?,
          isDubbed: item['isDubbed'] == true,
        ),
      );
    }
    return results;
  }
}

Future<List<Map<String, dynamic>>> _executeProvider(
  Map<String, Object?> input,
) async {
  final runtime = QuickJsRuntime2(
    timeout: 3500,
    memoryLimit: 32 * 1024 * 1024,
    stackSize: 512 * 1024,
  );
  var disposed = false;
  final completed = Completer<List<Map<String, dynamic>>>();

  runtime.onMessage('TetoNetwork', (dynamic request) {
    unawaited(() async {
      final id = request is Map ? '${request['id'] ?? ''}' : '';
      try {
        final response = await _safeAddonRequest(request);
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
    final bootstrap = runtime.evaluate(_networkBootstrap);
    if (bootstrap.isError) throw StateError(bootstrap.stringResult);
    final payload = input['payload']! as String;
    final provider = runtime.evaluate(
      payload,
      sourceUrl: 'addon://${input['id']}/provider.js',
    );
    if (provider.isError) throw StateError(provider.stringResult);
    final invocation = runtime.evaluate('''
      (async function() {
        try {
          const provider = new Provider();
          const settings = (await provider.getSettings()) || {};
          const titles = ${jsonEncode([input['title'], ...((input['titles'] as List?) ?? const [])])}
            .filter(Boolean).slice(0, 8);
          const episodeNumber = ${input['episode']};
          const modes = settings.supportsDub ? [false, true] : [false];
          const output = [];
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
          for (const dub of modes) {
            let selected = null;
            for (const title of titles) {
              try {
                const matches = (await provider.search({query: title, opts: {dub}})) || [];
                const ranked = matches.slice(0, 40).map(item => ({item, points: score(item.title, title)}))
                  .sort((a, b) => b.points - a.points);
                if (ranked.length && (!selected || ranked[0].points > selected.points)) {
                  selected = ranked[0];
                }
                if (selected && selected.points >= 700) break;
              } catch (_) {}
            }
            if (!selected) continue;
            const episodes = (await provider.findEpisodes(selected.item.id)) || [];
            const episode = episodes.find(item => Math.abs(Number(item.number) - episodeNumber) < 0.01);
            if (!episode) continue;
            let servers = Array.isArray(settings.episodeServers) ? settings.episodeServers.slice(0, 12) : ['default'];
            const dubbedServers = servers.filter(server => /dub/i.test(String(server)));
            if (settings.supportsDub && dubbedServers.length) {
              servers = dub ? dubbedServers : servers.filter(server => !/dub/i.test(String(server)));
            }
            for (const server of servers) {
              try {
                const resolved = await provider.findEpisodeServer(episode, server);
                const serverHeaders = resolved && resolved.headers && typeof resolved.headers === 'object'
                  ? resolved.headers : {};
                const sources = resolved && Array.isArray(resolved.videoSources)
                  ? resolved.videoSources.slice(0, 20) : [];
                for (const source of sources) {
                  const url = source.url || source.file;
                  if (typeof url !== 'string' || !url.startsWith('https://')) continue;
                  const subtitles = Array.isArray(source.subtitles) ? source.subtitles : [];
                  const english = subtitles.find(track => /(^|\b)(en|eng|english)(\b|\$)/i.test(
                    String(track.language || track.lang || track.label || '')
                  )) || subtitles[0];
                  output.push({
                    title: String(server || resolved.server || 'Web') + ' / ' +
                      String(source.quality || source.label || 'Auto'),
                    quality: String(source.quality || source.label || 'Auto'),
                    url,
                    headers: Object.assign({}, serverHeaders, source.headers || {}),
                    subtitleUrl: english && (english.url || english.file),
                    subtitleLanguage: english && String(english.language || english.lang || english.label || ''),
                    isDubbed: dub || /dub/i.test(String(selected.item.subOrDub || server || '')),
                  });
                }
              } catch (_) {}
            }
          }
          if (!output.length) throw new Error('No playable stream was returned for this episode.');
          sendMessage('TetoDone', JSON.stringify({ok: true, result: output}));
        } catch (error) {
          sendMessage('TetoDone', JSON.stringify({ok: false, error: String(error && error.message || error)}));
        }
      })();
    ''', sourceUrl: 'tetotv://provider-runner.js');
    if (invocation.isError) throw StateError(invocation.stringResult);
    await runtime.dispatch();
    return await completed.future.timeout(const Duration(seconds: 24));
  } finally {
    disposed = true;
    runtime.dispose();
  }
}

Future<Map<String, Object?>> _safeAddonRequest(dynamic raw) async {
  if (raw is! Map) throw const FormatException('Invalid provider request.');
  final uri = safePublicHttpsUri(raw['url']);
  if (uri == null) {
    throw const FormatException('Provider requests must use public HTTPS.');
  }
  var currentUri = uri;
  await validatePublicNetworkTarget(currentUri);
  final options = raw['options'] is Map ? raw['options'] as Map : const {};
  final method = '${options['method'] ?? 'GET'}'.toUpperCase();
  if (method != 'GET' && method != 'POST') {
    throw const FormatException('Only GET and POST requests are permitted.');
  }
  final headers = <String, String>{'User-Agent': 'TetoTV addon runtime'};
  final rawHeaders = options['headers'];
  if (rawHeaders is Map) {
    for (final entry in rawHeaders.entries.take(24)) {
      final key = '${entry.key}'.trim();
      final value = '${entry.value}'.trim();
      if (key.isNotEmpty && key.length <= 80 && value.length <= 4096) {
        headers[key] = value;
      }
    }
  }
  final body = options['body'] == null ? null : '${options['body']}';
  if (body != null && utf8.encode(body).length > 128 * 1024) {
    throw const FormatException('Provider request body is too large.');
  }
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 7),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
      followRedirects: false,
    ),
  );
  Response<ResponseBody>? response;
  String responseText = '';
  for (var redirect = 0; redirect < 4; redirect++) {
    response = await dio.request<ResponseBody>(
      currentUri.toString(),
      data: body,
      options: Options(
        method: method,
        headers: headers,
        responseType: ResponseType.stream,
      ),
    );
    responseText = await _boundedResponseText(response.data, 2 * 1024 * 1024);
    final status = response.statusCode ?? 0;
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (status < 300 || status >= 400 || location == null) break;
    final redirectUri = safePublicHttpsUri(
      currentUri.resolve(location).toString(),
    );
    if (redirectUri == null) {
      throw const FormatException('Provider redirect was not public HTTPS.');
    }
    currentUri = redirectUri;
    await validatePublicNetworkTarget(currentUri);
  }
  if (response == null) throw const HttpException('No provider response.');
  return {
    'status': response.statusCode ?? 0,
    'statusText': response.statusMessage ?? '',
    'url': response.realUri.toString(),
    'body': responseText,
    'headers': {
      for (final entry in response.headers.map.entries)
        entry.key: entry.value.join(', '),
    },
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
      sendMessage('TetoNetwork', JSON.stringify({id, url: String(url), options: options || {}}));
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
''';
