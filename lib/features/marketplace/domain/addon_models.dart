import 'dart:convert';
import 'dart:io';

const defaultMarketplaceRepositoryUrl =
    'https://raw.githubusercontent.com/ASleepyDrink/Seanime-Stuff/refs/heads/main/marketplace.json';

class AddonRepository {
  const AddonRepository({
    required this.url,
    this.enabled = true,
    this.isDefault = false,
    required this.updatedAt,
  });

  final String url;
  final bool enabled;
  final bool isDefault;
  final DateTime updatedAt;

  AddonRepository copyWith({bool? enabled, DateTime? updatedAt}) =>
      AddonRepository(
        url: url,
        enabled: enabled ?? this.enabled,
        isDefault: isDefault,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class MarketplaceAddon {
  const MarketplaceAddon({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.manifestUri,
    required this.repositoryUrl,
    required this.language,
    required this.type,
    required this.locale,
    this.version,
    this.iconUri,
    this.payloadUri,
  });

  final String id;
  final String name;
  final String description;
  final String author;
  final Uri manifestUri;
  final String repositoryUrl;
  final String language;
  final String type;
  final String locale;
  final String? version;
  final Uri? iconUri;
  final Uri? payloadUri;

  bool get isOnlineStreamProvider => type == 'onlinestream-provider';
  bool get isJavascript => language.toLowerCase() == 'javascript';
  bool get isCompatible => isOnlineStreamProvider && isJavascript;

  MarketplaceAddon mergeManifest(MarketplaceAddon manifest) => MarketplaceAddon(
    id: id,
    name: manifest.name,
    description: manifest.description,
    author: manifest.author,
    manifestUri: manifestUri,
    repositoryUrl: repositoryUrl,
    language: manifest.language,
    type: manifest.type,
    locale: manifest.locale,
    version: manifest.version,
    iconUri: manifest.iconUri ?? iconUri,
    payloadUri: manifest.payloadUri,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'author': author,
    'manifestURI': manifestUri.toString(),
    'repositoryURL': repositoryUrl,
    'language': language,
    'type': type,
    'lang': locale,
    'version': version,
    'icon': iconUri?.toString(),
    'payloadURI': payloadUri?.toString(),
  };

  static MarketplaceAddon? tryParse(
    Object? value, {
    required String repositoryUrl,
  }) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry('$key', value));
    final id = _clean(json['id'], 80);
    final name = _clean(json['name'], 120);
    final manifest = safePublicHttpsUri(json['manifestURI']);
    if (id == null ||
        name == null ||
        manifest == null ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id)) {
      return null;
    }
    return MarketplaceAddon(
      id: id,
      name: name,
      description: _clean(json['description'], 600) ?? '',
      author: _clean(json['author'], 120) ?? 'Unknown',
      manifestUri: manifest,
      repositoryUrl: repositoryUrl,
      language: (_clean(json['language'], 24) ?? '').toLowerCase(),
      type: (_clean(json['type'], 48) ?? '').toLowerCase(),
      locale: (_clean(json['lang'], 12) ?? 'unknown').toLowerCase(),
      version: _clean(json['version'], 32),
      iconUri: safePublicHttpsUri(json['icon']),
      payloadUri: safePublicHttpsUri(json['payloadURI']),
    );
  }
}

class InstalledStreamingAddon {
  const InstalledStreamingAddon({
    required this.manifest,
    required this.payload,
    required this.enabled,
    required this.installedAt,
    required this.updatedAt,
  });

  final MarketplaceAddon manifest;
  final String payload;
  final bool enabled;
  final DateTime installedAt;
  final DateTime updatedAt;

  InstalledStreamingAddon copyWith({bool? enabled}) => InstalledStreamingAddon(
    manifest: manifest,
    payload: payload,
    enabled: enabled ?? this.enabled,
    installedAt: installedAt,
    updatedAt: updatedAt,
  );

  factory InstalledStreamingAddon.fromRow(Map<String, Object?> row) {
    final raw = jsonDecode(row['manifest_json']! as String);
    final manifest = MarketplaceAddon.tryParse(
      raw,
      repositoryUrl: row['repository_url']! as String,
    );
    if (manifest == null) throw const FormatException('Invalid addon manifest');
    return InstalledStreamingAddon(
      manifest: manifest,
      payload: row['payload']! as String,
      enabled: row['enabled'] == 1,
      installedAt: DateTime.fromMillisecondsSinceEpoch(
        row['installed_at']! as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    );
  }
}

class WebStreamResult {
  const WebStreamResult({
    required this.providerId,
    required this.providerName,
    required this.title,
    required this.uri,
    this.quality,
    this.headers = const {},
    this.subtitleUri,
    this.subtitleLanguage,
    this.isDubbed = false,
  });

  final String providerId;
  final String providerName;
  final String title;
  final Uri uri;
  final String? quality;
  final Map<String, String> headers;
  final Uri? subtitleUri;
  final String? subtitleLanguage;
  final bool isDubbed;
}

class WebProviderFailure {
  const WebProviderFailure({required this.providerName, required this.message});

  final String providerName;
  final String message;
}

class WebStreamAggregation {
  const WebStreamAggregation({
    this.streams = const [],
    this.failures = const [],
  });

  final List<WebStreamResult> streams;
  final List<WebProviderFailure> failures;
}

Uri? safePublicHttpsUri(Object? value) {
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) return null;
  final host = uri.host.toLowerCase();
  if (host.isEmpty ||
      host == 'localhost' ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host == '0.0.0.0' ||
      host == '::1' ||
      host.startsWith('127.') ||
      host.startsWith('10.') ||
      host.startsWith('192.168.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host)) {
    return null;
  }
  return uri;
}

Future<void> validatePublicNetworkTarget(Uri uri) async {
  if (safePublicHttpsUri(uri.toString()) == null) {
    throw const FormatException('Only public HTTPS resources are allowed.');
  }
  final addresses = await InternetAddress.lookup(
    uri.host,
  ).timeout(const Duration(seconds: 4));
  if (addresses.isEmpty || addresses.any(_isPrivateAddress)) {
    throw const FormatException(
      'The resource host does not resolve to a public address.',
    );
  }
}

bool _isPrivateAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal) return true;
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return bytes[0] == 10 ||
        bytes[0] == 127 ||
        (bytes[0] == 169 && bytes[1] == 254) ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        bytes[0] == 0;
  }
  return (bytes.isNotEmpty && (bytes[0] & 0xFE) == 0xFC);
}

String? _clean(Object? value, int maximum) {
  if (value is! String) return null;
  final cleaned = value.replaceAll(RegExp(r'[\x00-\x1F]'), ' ').trim();
  if (cleaned.isEmpty) return null;
  return cleaned.length <= maximum ? cleaned : cleaned.substring(0, maximum);
}
