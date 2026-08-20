import 'dart:convert';
import 'dart:typed_data';

import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/public_https_dio.dart';
import 'package:anime_tv/features/marketplace/data/typescript_compiler.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:dio/dio.dart';

class MarketplaceClient {
  MarketplaceClient(
    this._store, {
    Dio? dio,
    AddonTypescriptCompiler? typescriptCompiler,
  }) : _typescriptCompiler = typescriptCompiler ?? AddonTypescriptCompiler(),
       _dio =
           dio ??
           createPinnedPublicHttpsDio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 12),
               responseType: ResponseType.plain,
               followRedirects: false,
               headers: const {'User-Agent': 'TetoTV/1 marketplace'},
             ),
           );

  static const _maxCatalogBytes = 2 * 1024 * 1024;
  static const _maxManifestBytes = 256 * 1024;
  static const _maxPayloadBytes = 768 * 1024;

  final AddonStore _store;
  final AddonTypescriptCompiler _typescriptCompiler;
  final Dio _dio;

  Future<List<MarketplaceAddon>> catalog(
    AddonRepository repository, {
    bool refresh = false,
  }) async {
    if (!refresh) {
      final cached = await _store.cachedCatalog(repository.url);
      if (cached != null) {
        return _parseCatalog(cached, repository.url);
      }
    }
    final uri = safePublicHttpsUri(repository.url);
    if (uri == null) {
      throw const FormatException('Repository must use a public HTTPS URL.');
    }
    try {
      final payload = await _getText(uri, maximumBytes: _maxCatalogBytes);
      final parsed = _parseCatalog(payload, repository.url);
      await _store.cacheCatalog(repository.url, payload);
      return parsed;
    } catch (_) {
      final cached = await _store.cachedCatalog(repository.url);
      if (cached != null) {
        return _parseCatalog(cached, repository.url);
      }
      rethrow;
    }
  }

  Future<InstalledStreamingAddon> downloadAddon(
    MarketplaceAddon summary,
  ) async {
    final complete = await manifest(summary);
    if (!complete.isCompatible ||
        (complete.payloadUri == null && complete.inlinePayload == null)) {
      throw const FormatException(
        'This addon is not a compatible JavaScript or TypeScript provider.',
      );
    }
    final downloadedSource =
        complete.inlinePayload ??
        await _getText(complete.payloadUri!, maximumBytes: _maxPayloadBytes);
    final source = applyAddonConfigDefaults(
      downloadedSource,
      complete.userConfigDefaults,
    );
    final payload = complete.isTypescript
        ? await _typescriptCompiler.compile(source)
        : source;
    if (!_looksLikeProvider(payload)) {
      throw const FormatException(
        'The addon payload does not expose a Provider class.',
      );
    }
    final now = DateTime.now();
    return InstalledStreamingAddon(
      manifest: complete,
      payload: payload,
      enabled: true,
      installedAt: now,
      updatedAt: now,
    );
  }

  Future<MarketplaceAddon> manifest(MarketplaceAddon summary) async {
    final manifestPayload = await _getText(
      summary.manifestUri,
      maximumBytes: _maxManifestBytes,
    );
    final decoded = jsonDecode(manifestPayload);
    return validateAndMergeMarketplaceManifest(summary, decoded);
  }

  Future<String> _getText(Uri uri, {required int maximumBytes}) async {
    if (safePublicHttpsUri(uri.toString()) == null) {
      throw const FormatException('Only public HTTPS resources are allowed.');
    }
    await validatePublicNetworkTarget(uri);
    final response = await _dio.get<ResponseBody>(
      uri.toString(),
      options: Options(responseType: ResponseType.stream),
    );
    final body = response.data;
    if (body == null) {
      throw const FormatException('The downloaded resource is empty.');
    }
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in body.stream) {
      length += chunk.length;
      if (length > maximumBytes) {
        throw const FormatException('The downloaded resource is too large.');
      }
      bytes.add(chunk);
    }
    final data = utf8.decode(bytes.takeBytes(), allowMalformed: false);
    if (data.isEmpty) {
      throw const FormatException('The downloaded resource is empty.');
    }
    return data;
  }

  List<MarketplaceAddon> _parseCatalog(String payload, String repositoryUrl) {
    return parseMarketplaceCatalog(payload, repositoryUrl: repositoryUrl);
  }
}

/// Parses both Seanime's canonical top-level list and common named wrappers
/// used by independently maintained repositories. The executable manifest is
/// still fetched and validated separately, so accepting a wrapper does not
/// weaken the repository/code trust boundary.
List<MarketplaceAddon> parseMarketplaceCatalog(
  String payload, {
  required String repositoryUrl,
}) {
  if (utf8.encode(payload).length > MarketplaceClient._maxCatalogBytes) {
    throw const FormatException('Repository catalog is too large.');
  }
  final decoded = jsonDecode(payload);
  final entries = switch (decoded) {
    final List<dynamic> values => values,
    final Map<dynamic, dynamic> wrapper => _catalogEntriesFromWrapper(wrapper),
    _ => null,
  };
  if (entries == null) {
    throw const FormatException(
      'Repository catalog must be a JSON list or contain an addons/providers list.',
    );
  }
  final unique = <String, MarketplaceAddon>{};
  for (final entry in entries.take(1000)) {
    final addon = MarketplaceAddon.tryParse(
      entry,
      repositoryUrl: repositoryUrl,
    );
    if (addon != null && addon.isOnlineStreamProvider) {
      unique.putIfAbsent(marketplaceAddonIdentityKey(addon.id), () => addon);
    }
  }
  return unique.values.toList(growable: false);
}

List<dynamic>? _catalogEntriesFromWrapper(Map<dynamic, dynamic> wrapper) {
  Map<dynamic, dynamic> current = wrapper;
  for (var depth = 0; depth < 8; depth++) {
    for (final key in const ['addons', 'providers', 'extensions', 'items']) {
      final value = current[key];
      if (value is List) return value;
    }
    final data = current['data'];
    if (data is List) return data;
    if (data is! Map) return null;
    current = data;
  }
  return null;
}

/// Seanime add-on IDs are case-sensitive in JavaScript only by convention.
/// Repositories in the wild already contain casing-only catalog/manifest
/// drift (for example `animeAV1` versus `animeav1`). Treating that as the same
/// identity keeps the original repository provenance while avoiding a false
/// install rejection.
MarketplaceAddon validateAndMergeMarketplaceManifest(
  MarketplaceAddon summary,
  Object? decoded,
) {
  final manifest = MarketplaceAddon.tryParse(
    decoded,
    repositoryUrl: summary.repositoryUrl,
  );
  if (manifest == null || !marketplaceAddonIdsMatch(manifest.id, summary.id)) {
    throw const FormatException(
      'The addon manifest is invalid or its ID changed.',
    );
  }
  return summary.mergeManifest(manifest);
}

bool _looksLikeProvider(String payload) =>
    RegExp(r'\bclass\s+Provider\b').hasMatch(payload) &&
    utf8.encode(payload).length <= MarketplaceClient._maxPayloadBytes;

String applyAddonConfigDefaults(String source, Map<String, String> defaults) {
  var encodedLength = 0;
  final output = StringBuffer();

  void writeBounded(String value) {
    encodedLength += utf8.encode(value).length;
    if (encodedLength > MarketplaceClient._maxPayloadBytes) {
      throw const FormatException('The configured addon payload is too large.');
    }
    output.write(value);
  }

  final placeholder = RegExp(r'\{\{([A-Za-z0-9._-]+)\}\}');
  var cursor = 0;
  for (final match in placeholder.allMatches(source)) {
    writeBounded(source.substring(cursor, match.start));
    final key = match.group(1)!;
    writeBounded(defaults[key] ?? match.group(0)!);
    cursor = match.end;
  }
  writeBounded(source.substring(cursor));
  return output.toString();
}
