import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:dio/dio.dart';

/// Reads any Stremio-compatible stream add-on that returns torrent info hashes.
///
/// The default app configuration points at Torrentio's public manifest, but
/// callers may provide another compatible manifest URL. Real-Debrid credentials
/// are intentionally not sent to this source; selected hashes are resolved by
/// the app's own authenticated Real-Debrid client.
class TorrentioReleaseSource implements ReleaseSource {
  TorrentioReleaseSource({
    required String manifestUrl,
    Dio? addonDio,
    Dio? kitsuDio,
  }) : _manifestUri = _validateManifestUrl(manifestUrl),
       _addonDio =
           addonDio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 30),
               headers: const {
                 'Accept': 'application/json',
                 'User-Agent':
                     'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
               },
             ),
           ),
       _kitsuDio =
           kitsuDio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://kitsu.io/api/edge',
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
               headers: const {
                 'Accept': 'application/vnd.api+json',
                 'User-Agent':
                     'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
               },
             ),
           );

  final Uri _manifestUri;
  final Dio _addonDio;
  final Dio _kitsuDio;
  final Map<int, String> _kitsuIds = {};

  @override
  String get id => 'stremio-torrentio';

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) async {
    final kitsuId = await _resolveKitsuId(episode);
    final videoId = 'kitsu:$kitsuId:${episode.episode}';
    final streamUri = _manifestUri.resolve(
      'stream/anime/${Uri.encodeComponent(videoId)}.json',
    );
    final response = await _addonDio.getUri<dynamic>(streamUri);
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const FormatException(
        'The Stremio add-on returned an invalid stream response.',
      );
    }
    return parseStreams(body);
  }

  Future<String> _resolveKitsuId(EpisodeReference episode) async {
    final cached = _kitsuIds[episode.anilistMediaId];
    if (cached != null) return cached;

    if (episode.malMediaId != null) {
      try {
        final response = await _kitsuDio.get<dynamic>(
          '/mappings',
          queryParameters: {
            'filter[externalSite]': 'myanimelist/anime',
            'filter[externalId]': episode.malMediaId.toString(),
          },
        );
        final body = response.data;
        if (body is Map<String, dynamic>) {
          final data = body['data'];
          if (data is List<dynamic> && data.isNotEmpty) {
            final first = data.first;
            if (first is Map<String, dynamic>) {
              final item = first['relationships']?['item']?['data'];
              if (item is Map<String, dynamic>) {
                final id = item['id']?.toString();
                if (id != null && id.isNotEmpty) {
                  _kitsuIds[episode.anilistMediaId] = id;
                  return id;
                }
              }
            }
          }
        }
      } catch (_) {
        // Fall back to title search on failure
      }
    }

    final queries = <String>[
      episode.title,
      ...episode.alternativeTitles,
    ].where((value) => value.trim().isNotEmpty);
    final targets = queries.map(_normalizeTitle).toSet();
    Map<String, dynamic>? best;
    var bestScore = -1;

    for (final query in queries.take(3)) {
      final response = await _kitsuDio.get<dynamic>(
        '/anime',
        queryParameters: {'filter[text]': query, 'page[limit]': 10},
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) continue;
      final data = body['data'];
      if (data is! List<dynamic>) continue;
      for (final value in data) {
        if (value is! Map<String, dynamic>) continue;
        final score = _titleScore(value, targets);
        if (score > bestScore) {
          best = value;
          bestScore = score;
        }
      }
      if (bestScore >= 1000) break;
    }

    final kitsuId = best?['id']?.toString();
    if (kitsuId == null || kitsuId.isEmpty || bestScore < 700) {
      throw StateError('Could not match this title to a Kitsu anime ID.');
    }
    _kitsuIds[episode.anilistMediaId] = kitsuId;
    return kitsuId;
  }

  static List<ReleaseCandidate> parseStreams(Map<String, dynamic> body) {
    final values = body['streams'];
    if (values is! List<dynamic>) return const [];
    final candidates = <ReleaseCandidate>[];

    for (final value in values) {
      if (value is! Map<String, dynamic>) continue;
      final infoHash = value['infoHash']?.toString().trim() ?? '';
      if (!RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(infoHash)) continue;

      final name = value['name']?.toString() ?? 'Torrentio';
      final title = value['title']?.toString() ?? name;
      final hints = value['behaviorHints'];
      final filename = hints is Map<String, dynamic>
          ? hints['filename']?.toString()
          : null;
      final searchable = '$name\n$title\n${filename ?? ''}';
      final lower = searchable.toLowerCase();
      final quality = _firstMatch(
        RegExp(r'\b(2160p|4k|1440p|1080p|720p|480p)\b', caseSensitive: false),
        searchable,
      );
      final codecRaw = _firstMatch(
        RegExp(
          r'\b(AV1|HEVC|x265|H[.]?265|x264|H[.]?264)\b',
          caseSensitive: false,
        ),
        searchable,
      );
      final seeders =
          int.tryParse(_firstMatch(RegExp(r'👤\s*(\d+)'), searchable) ?? '') ??
          0;
      final size = _sizeMatch(searchable);
      final provider = _firstMatch(RegExp(r'⚙️\s*([^\r\n]+)'), searchable);
      final isDubbed =
          lower.contains('dubbed') ||
          lower.contains('dual audio') ||
          lower.contains('dual-audio') ||
          lower.contains('multi audio') ||
          lower.contains('multi-audio');
      final hasSubtitles =
          !isDubbed ||
          lower.contains('multi subs') ||
          lower.contains('multi-subs') ||
          lower.contains('multiple subtitle') ||
          lower.contains('subbed');

      candidates.add(
        ReleaseCandidate(
          infoHash: infoHash.toLowerCase(),
          magnetUri: 'magnet:?xt=urn:btih:${infoHash.toLowerCase()}',
          releaseName: title,
          seeders: seeders,
          sourceId: provider == null ? 'torrentio' : 'torrentio:$provider',
          isBatch:
              lower.contains('batch') ||
              RegExp(r'\b\d{1,3}\s*-\s*\d{1,3}\b').hasMatch(lower),
          preferredFileIndex: switch (value['fileIdx']) {
            final int index => index,
            final num index => index.toInt(),
            _ => null,
          },
          quality: quality?.toUpperCase() == '4K'
              ? '4K'
              : quality?.toLowerCase(),
          codec: _normalizeCodec(codecRaw),
          sizeLabel: size,
          provider: provider,
          isDubbed: isDubbed,
          hasSubtitles: hasSubtitles,
          isHdr: lower.contains('hdr') || lower.contains('dolby vision'),
        ),
      );
    }

    return candidates;
  }

  static Uri _validateManifestUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !uri.path.endsWith('manifest.json')) {
      throw ArgumentError.value(
        value,
        'manifestUrl',
        'Use an HTTPS Stremio manifest URL ending in manifest.json.',
      );
    }
    return uri;
  }

  static int _titleScore(Map<String, dynamic> item, Set<String> targets) {
    final attributes = item['attributes'];
    if (attributes is! Map<String, dynamic>) return 0;
    final titles = <String>[
      attributes['canonicalTitle']?.toString() ?? '',
      if (attributes['titles'] case final Map<String, dynamic> values)
        ...values.values.map((value) => value?.toString() ?? ''),
      if (attributes['abbreviatedTitles'] case final List<dynamic> values)
        ...values.map((value) => value?.toString() ?? ''),
    ].map(_normalizeTitle).where((value) => value.isNotEmpty);

    var score = 0;
    for (final title in titles) {
      for (final target in targets) {
        if (title == target) return 1000;
        if (title.contains(target) || target.contains(title)) {
          score = score < 700 ? 700 : score;
        }
      }
    }
    return score;
  }

  static String _normalizeTitle(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static String? _firstMatch(RegExp expression, String value) =>
      expression.firstMatch(value)?.group(1)?.trim();

  static String? _sizeMatch(String value) {
    final match = RegExp(
      r'💾\s*([0-9.]+)\s*(KB|MB|GB|TB)',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)} ${match.group(2)!.toUpperCase()}';
  }

  static String? _normalizeCodec(String? value) {
    if (value == null) return null;
    final lower = value.toLowerCase();
    if (lower == 'av1') return 'AV1';
    if (lower == 'hevc' || lower.contains('265')) return 'HEVC';
    if (lower.contains('264')) return 'H.264';
    return value.toUpperCase();
  }
}
