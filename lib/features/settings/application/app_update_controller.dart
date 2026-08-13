import 'dart:io';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const githubUpdateTokenStorageKey = 'github_update_token';
const betaUpdateAccessKeyStorageKey = 'beta_update_access_key';
const automaticUpdatesStorageKey = 'automatic_app_updates';
const lastAutomaticUpdateCheckStorageKey = 'last_automatic_update_check';
const pendingReleaseNotesVersionStorageKey = 'pending_release_notes_version';
const pendingReleaseNotesStorageKey = 'pending_release_notes';
const updateChannelStorageKey = 'app_update_channel';
const developerModeStorageKey = 'settings_developer_mode';
const tetoTvPublicReleaseRepository = 'LindersOSX/TetoTV-Releases';
const tetoTvUpdateBroker = 'https://tetotv-updates-lindows.onrender.com';
const maxPublicReleaseAssetBytes = 300 * 1024 * 1024;

final appUpdateControllerProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      final bridge = AndroidTvBridge.instance;
      final storage = ref.watch(secureStorageProvider);
      final controller = AppUpdateController(
        storage,
        GitHubAppReleaseSource(
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
            ),
          ),
          repository: tetoTvPublicReleaseRepository,
        ),
        () async {
          final version = await bridge.getAppVersion();
          if (version.code <= 0 || version.name.contains('+')) {
            return version.name;
          }
          return '${version.name}+${version.code}';
        },
        () async => (await bridge.getDeviceProfile()).abis,
        getTemporaryDirectory,
        bridge.installApk,
        betaReleaseSource: BrokerAppReleaseSource(
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
            ),
          ),
          accessKeyLoader: () =>
              storage.read(key: betaUpdateAccessKeyStorageKey),
        ),
        apkInspector: bridge.inspectApk,
      );
      Future.microtask(controller.load);
      return controller;
    });

enum AppUpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  ready,
  installing,
  error,
}

class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.currentVersion = '…',
    this.latestVersion,
    this.release,
    this.downloadedPath,
    this.message,
    this.progress = 0,
    this.automaticUpdates = true,
    this.updateChannel = AppUpdateChannel.public,
    this.developerMode = false,
    this.hasBetaAccessKey = false,
  });

  final AppUpdatePhase phase;
  final String currentVersion;
  final String? latestVersion;
  final AppReleaseInfo? release;
  final String? downloadedPath;
  final String? message;
  final double progress;
  final bool automaticUpdates;
  final AppUpdateChannel updateChannel;
  final bool developerMode;
  final bool hasBetaAccessKey;

  bool get isBusy =>
      phase == AppUpdatePhase.checking ||
      phase == AppUpdatePhase.downloading ||
      phase == AppUpdatePhase.installing;

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    String? currentVersion,
    Object? latestVersion = _notProvided,
    Object? release = _notProvided,
    Object? downloadedPath = _notProvided,
    Object? message = _notProvided,
    double? progress,
    bool? automaticUpdates,
    AppUpdateChannel? updateChannel,
    bool? developerMode,
    bool? hasBetaAccessKey,
  }) {
    return AppUpdateState(
      phase: phase ?? this.phase,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: identical(latestVersion, _notProvided)
          ? this.latestVersion
          : latestVersion as String?,
      release: identical(release, _notProvided)
          ? this.release
          : release as AppReleaseInfo?,
      downloadedPath: identical(downloadedPath, _notProvided)
          ? this.downloadedPath
          : downloadedPath as String?,
      message: identical(message, _notProvided)
          ? this.message
          : message as String?,
      progress: progress ?? this.progress,
      automaticUpdates: automaticUpdates ?? this.automaticUpdates,
      updateChannel: updateChannel ?? this.updateChannel,
      developerMode: developerMode ?? this.developerMode,
      hasBetaAccessKey: hasBetaAccessKey ?? this.hasBetaAccessKey,
    );
  }
}

enum AppUpdateChannel { public, beta }

extension AppUpdateChannelLabel on AppUpdateChannel {
  String get displayName => switch (this) {
    AppUpdateChannel.public => 'Public',
    AppUpdateChannel.beta => 'Beta',
  };

  String get description => switch (this) {
    AppUpdateChannel.public => 'Stable releases from the public release page',
    AppUpdateChannel.beta => 'Private 2.x preview builds for TetoTV testers',
  };

  String versionLabel(String version) =>
      this == AppUpdateChannel.beta ? '$version Beta' : version;

  int get releaseMajor => switch (this) {
    AppUpdateChannel.public => 1,
    AppUpdateChannel.beta => 2,
  };
}

const _notProvided = Object();

class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.apiUrl,
    required this.publicUrl,
    required this.size,
    this.sha256Digest,
  });

  final String name;
  final String apiUrl;
  final String publicUrl;
  final int size;
  final String? sha256Digest;
}

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.asset,
    this.notes = '',
  });

  final String tagName;
  final String version;
  final String name;
  final AppReleaseAsset asset;
  final String notes;
}

abstract class AppReleaseSource {
  Future<AppReleaseInfo> latest({required List<String> deviceAbis});

  Future<void> download({
    required AppReleaseInfo release,
    required String destination,
    required void Function(int received, int total) onProgress,
  });
}

/// Reads private release metadata and APK bytes through the fixed TetoTV
/// update broker. GitHub credentials remain server-side. The separately issued
/// tester key is loaded only from secure storage and sent only to this fixed
/// broker origin.
class BrokerAppReleaseSource implements AppReleaseSource {
  BrokerAppReleaseSource(this._dio, {required this.accessKeyLoader});

  final Dio _dio;
  final Future<String?> Function() accessKeyLoader;

  static final Uri _latestUri = Uri.parse(
    '$tetoTvUpdateBroker/v1/app-updates/latest',
  );

  @override
  Future<AppReleaseInfo> latest({required List<String> deviceAbis}) async {
    final headers = await _authorizedHeaders('application/json');
    final response = await _dio.get<Map<String, dynamic>>(
      _latestUri.toString(),
      options: Options(
        headers: headers,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status == HttpStatus.ok,
      ),
    );
    final data = response.data;
    if (data == null) {
      throw StateError('The update service returned an empty release.');
    }
    final rawAsset = data['asset'];
    if (rawAsset is! Map) {
      throw FormatException('The update service returned no APK metadata.');
    }
    final assetData = rawAsset.cast<Object?, Object?>();
    final assetName = _requiredString(assetData['name'], 'asset name');
    if (path.basename(assetName) != assetName ||
        !assetName.toLowerCase().endsWith('.apk')) {
      throw FormatException('The update service returned an invalid APK name.');
    }
    final size = (assetData['size'] as num?)?.toInt() ?? 0;
    if (size <= 0) {
      throw FormatException('The update service returned an invalid APK size.');
    }
    final contentType = _requiredString(
      assetData['content_type'],
      'asset content type',
    ).toLowerCase();
    if (contentType != 'application/vnd.android.package-archive' &&
        contentType != 'application/octet-stream') {
      throw FormatException(
        'The update service returned an invalid APK content type.',
      );
    }
    final tag = _requiredString(data['tag_name'], 'release tag');
    final downloadUri = _trustedBrokerAssetUri(
      _requiredString(assetData['download_url'], 'asset download URL'),
      tag,
    );
    final digest = _parseSha256Digest(assetData['digest']);
    final advertisedVersion = _requiredString(data['version'], 'version');
    final tagVersion = normalizeAppVersion(tag);
    final version = normalizeAppVersion(advertisedVersion);
    if (version.isEmpty || compareAppVersions(version, tagVersion) != 0) {
      throw FormatException('The update service returned mismatched versions.');
    }
    return AppReleaseInfo(
      tagName: tag,
      version: version,
      name: _optionalString(data['name']) ?? tag,
      notes: _optionalString(data['release_notes']) ?? '',
      asset: AppReleaseAsset(
        name: assetName,
        apiUrl: downloadUri.toString(),
        publicUrl: downloadUri.toString(),
        size: size,
        sha256Digest: digest,
      ),
    );
  }

  @override
  Future<void> download({
    required AppReleaseInfo release,
    required String destination,
    required void Function(int received, int total) onProgress,
  }) async {
    final uri = _trustedBrokerAssetUri(
      release.asset.publicUrl,
      release.tagName,
    );
    final headers = await _authorizedHeaders(
      'application/vnd.android.package-archive',
    );
    await _dio.download(
      uri.toString(),
      destination,
      options: Options(
        headers: headers,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status == HttpStatus.ok,
        receiveTimeout: const Duration(minutes: 20),
      ),
      onReceiveProgress: onProgress,
      deleteOnError: true,
    );
  }

  Future<Map<String, String>> _authorizedHeaders(String accept) async {
    final key = (await accessKeyLoader())?.trim() ?? '';
    if (!isValidBetaUpdateAccessKey(key)) {
      throw StateError(
        'A valid Beta access key is required for private updates.',
      );
    }
    return {
      'Accept': accept,
      'Authorization': 'Beta $key',
      'User-Agent': 'TetoTV-Android-Updater',
    };
  }

  static Uri _trustedBrokerAssetUri(String value, String tag) {
    if (!RegExp(r'^v[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(tag)) {
      throw FormatException(
        'The update service returned an invalid release tag.',
      );
    }
    final uri = Uri.tryParse(value);
    final base = Uri.parse(tetoTvUpdateBroker);
    if (uri == null ||
        uri.scheme != base.scheme ||
        uri.host != base.host ||
        uri.port != base.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException(
        'The update service returned an untrusted APK download URL.',
      );
    }
    final segments = uri.pathSegments;
    if (segments.length != 7 ||
        segments[0] != 'v1' ||
        segments[1] != 'app-updates' ||
        segments[2] != 'releases' ||
        segments[3] != tag ||
        segments[4] != 'assets' ||
        segments[6] != 'universal.apk') {
      throw FormatException(
        'The update service returned an invalid APK download path.',
      );
    }
    final assetIdText = segments[5];
    final assetId = int.tryParse(assetIdText);
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(assetIdText) ||
        assetId == null ||
        assetId > 9007199254740991) {
      throw FormatException(
        'The update service returned an invalid APK asset ID.',
      );
    }
    final expected = Uri.parse(
      '$tetoTvUpdateBroker/v1/app-updates/releases/$tag/assets/'
      '$assetIdText/universal.apk',
    );
    if (uri != expected) {
      throw FormatException(
        'The update service returned a non-canonical APK download URL.',
      );
    }
    return uri;
  }
}

/// Prefers the credential-free broker. The anonymous GitHub path is retained
/// solely as a future public-repository fallback; it never receives a token.
class BrokerFirstAppReleaseSource implements AppReleaseSource {
  BrokerFirstAppReleaseSource(this._broker, this._anonymousGitHub);

  final BrokerAppReleaseSource _broker;
  final GitHubAppReleaseSource _anonymousGitHub;

  @override
  Future<AppReleaseInfo> latest({required List<String> deviceAbis}) async {
    try {
      return await _broker.latest(deviceAbis: deviceAbis);
    } on DioException catch (brokerError, brokerStack) {
      try {
        return await _anonymousGitHub.latest(deviceAbis: deviceAbis);
      } catch (_) {
        Error.throwWithStackTrace(brokerError, brokerStack);
      }
    }
  }

  @override
  Future<void> download({
    required AppReleaseInfo release,
    required String destination,
    required void Function(int received, int total) onProgress,
  }) {
    final uri = Uri.tryParse(release.asset.publicUrl);
    final isBrokerAsset =
        uri != null &&
        uri.scheme == 'https' &&
        uri.host == Uri.parse(tetoTvUpdateBroker).host;
    return isBrokerAsset
        ? _broker.download(
            release: release,
            destination: destination,
            onProgress: onProgress,
          )
        : _anonymousGitHub.download(
            release: release,
            destination: destination,
            onProgress: onProgress,
          );
  }
}

class GitHubAppReleaseSource implements AppReleaseSource {
  GitHubAppReleaseSource(
    this._dio, {
    this.repository = tetoTvPublicReleaseRepository,
  });

  final Dio _dio;
  final String repository;

  @override
  Future<AppReleaseInfo> latest({required List<String> deviceAbis}) async {
    final response = await _latestResponse();
    final data = response.data;
    if (data == null) throw StateError('GitHub returned an empty release.');
    if (data['draft'] == true || data['prerelease'] == true) {
      throw FormatException('The public update is not a completed release.');
    }
    final tag = _requiredString(data['tag_name'], 'release tag');
    if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
      throw FormatException('The public update has an invalid release tag.');
    }
    final expectedAssetName = 'TetoTV-$tag-universal.apk';
    final assets = (data['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) => item['name'] == expectedAssetName)
        .map(
          (item) => AppReleaseAsset(
            name: item['name'] as String? ?? '',
            apiUrl: item['url'] as String? ?? '',
            publicUrl: _trustedReleaseAssetUri(
              item['browser_download_url'] as String? ?? '',
              tag,
              expectedAssetName,
            ).toString(),
            size: (item['size'] as num?)?.toInt() ?? 0,
            sha256Digest: _parseSha256Digest(item['digest']),
          ),
        )
        .where(
          (asset) =>
              asset.name.isNotEmpty &&
              asset.apiUrl.isNotEmpty &&
              asset.publicUrl.isNotEmpty &&
              asset.size >= 1024 * 1024 &&
              asset.size <= maxPublicReleaseAssetBytes,
        )
        .toList(growable: false);
    if (assets.isEmpty) {
      throw StateError(
        'The latest public release has no signed universal APK attached.',
      );
    }
    if (assets.length != 1) {
      throw FormatException(
        'The latest public release has duplicate universal APKs.',
      );
    }
    final asset = selectApkAsset(assets, deviceAbis);
    return AppReleaseInfo(
      tagName: tag,
      version: normalizeAppVersion(tag),
      name: data['name'] as String? ?? tag,
      asset: asset,
      notes: data['body'] as String? ?? '',
    );
  }

  @override
  Future<void> download({
    required AppReleaseInfo release,
    required String destination,
    required void Function(int received, int total) onProgress,
  }) => _download(
    url: _trustedReleaseAssetUri(
      release.asset.publicUrl,
      release.tagName,
      release.asset.name,
    ).toString(),
    destination: destination,
    onProgress: onProgress,
  );

  Future<Response<Map<String, dynamic>>> _latestResponse() =>
      _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$repository/releases/latest',
        options: Options(headers: _headers('application/vnd.github+json')),
      );

  Uri _trustedReleaseAssetUri(String value, String tag, String assetName) {
    final repositoryParts = repository.split('/');
    if (repositoryParts.length != 2 ||
        repositoryParts.any(
          (part) => !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(part),
        )) {
      throw FormatException('The public update repository is invalid.');
    }
    if (assetName != 'TetoTV-$tag-universal.apk' ||
        !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
      throw FormatException('The public update asset identity is invalid.');
    }
    final uri = Uri.tryParse(value);
    final expectedPath =
        '/${repositoryParts[0]}/${repositoryParts[1]}/releases/download/'
        '$tag/$assetName';
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.path != expectedPath ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException(
        'The public update returned an untrusted APK download URL.',
      );
    }
    return uri;
  }

  Future<void> _download({
    required String url,
    required String destination,
    required void Function(int received, int total) onProgress,
  }) async {
    var currentUri = Uri.parse(url);
    try {
      for (var redirectCount = 0; redirectCount <= 3; redirectCount++) {
        final response = await _dio.download(
          currentUri.toString(),
          destination,
          options: Options(
            headers: _headers('application/octet-stream'),
            followRedirects: false,
            maxRedirects: 0,
            validateStatus: (status) =>
                status == HttpStatus.ok || _isRedirectStatus(status),
            receiveTimeout: const Duration(minutes: 20),
          ),
          onReceiveProgress: onProgress,
          deleteOnError: true,
        );
        if (response.statusCode == HttpStatus.ok) return;
        if (redirectCount >= 3) {
          throw const FormatException(
            'The public update download redirected too many times.',
          );
        }
        currentUri = _trustedGitHubAssetRedirectUri(
          response.headers.value(HttpHeaders.locationHeader),
        );
      }
      throw const FormatException(
        'The public update download did not return an APK.',
      );
    } catch (_) {
      await _deleteUpdateFile(File(destination));
      rethrow;
    }
  }

  static bool _isRedirectStatus(int? status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;

  static Uri _trustedGitHubAssetRedirectUri(String? value) {
    final uri = value == null ? null : Uri.tryParse(value.trim());
    const trustedHosts = {
      'objects.githubusercontent.com',
      'release-assets.githubusercontent.com',
    };
    if (uri == null ||
        !uri.isAbsolute ||
        uri.scheme != 'https' ||
        !trustedHosts.contains(uri.host.toLowerCase()) ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.path.isEmpty ||
        uri.hasFragment) {
      throw const FormatException(
        'The public update returned an untrusted download redirect.',
      );
    }
    return uri;
  }

  static Map<String, String> _headers(String accept) => {
    'Accept': accept,
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'TetoTV-AndroidTV-Updater',
  };
}

String _requiredString(Object? value, String field) {
  final result = _optionalString(value);
  if (result == null) throw FormatException('Missing update $field.');
  return result;
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final result = value.trim();
  return result.isEmpty ? null : result;
}

bool isValidBetaUpdateAccessKey(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(value);

String? _parseSha256Digest(Object? value) {
  if (value == null) return null;
  final raw = _requiredString(value, 'asset digest').toLowerCase();
  final match = RegExp(r'^sha256:([0-9a-f]{64})$').firstMatch(raw);
  if (match == null) {
    throw FormatException('The update service returned an invalid APK digest.');
  }
  return match.group(1);
}

AppReleaseAsset selectApkAsset(
  List<AppReleaseAsset> assets,
  List<String> deviceAbis,
) {
  // Prefer one cross-device artifact for in-app updates. Besides avoiding
  // inaccurate ABI reports on vendor TV firmware, this lets a device move
  // safely between an older split APK and the newer universal APK.
  for (final asset in assets) {
    if (asset.name.toLowerCase().contains('universal')) return asset;
  }
  final normalizedAbis = deviceAbis.map((abi) => abi.toLowerCase()).toList();
  final preferredMarker = normalizedAbis.any((abi) => abi.contains('arm64'))
      ? 'arm64-v8a'
      : normalizedAbis.any((abi) => abi.contains('armeabi'))
      ? 'armeabi-v7a'
      : normalizedAbis.any((abi) => abi.contains('x86_64'))
      ? 'x86_64'
      : null;
  if (preferredMarker != null) {
    for (final asset in assets) {
      if (asset.name.toLowerCase().contains(preferredMarker)) return asset;
    }
    final aliases = switch (preferredMarker) {
      'arm64-v8a' => const ['arm64'],
      'armeabi-v7a' => const ['fire-tv-32bit', 'arm32'],
      _ => const <String>[],
    };
    for (final alias in aliases) {
      for (final asset in assets) {
        if (asset.name.toLowerCase().contains(alias)) return asset;
      }
    }
  }
  return assets.first;
}

String normalizeAppVersion(String value) {
  final match = RegExp(
    r'\d+(?:\.\d+){0,3}(?:\+[0-9A-Za-z.-]+)?',
  ).firstMatch(value);
  return match?.group(0) ?? value.trim().replaceFirst(RegExp(r'^[vV]'), '');
}

int compareAppVersions(String left, String right) {
  ({List<int> core, List<int> build}) parts(String value) {
    final normalized = normalizeAppVersion(value);
    final split = normalized.split('+');
    final core = split.first
        .split('.')
        .map((item) => int.tryParse(item) ?? 0)
        .toList(growable: false);
    final build = split.length < 2
        ? const <int>[]
        : split[1]
              .split(RegExp(r'[^0-9]+'))
              .where((item) => item.isNotEmpty)
              .map((item) => int.tryParse(item) ?? 0)
              .toList(growable: false);
    return (core: core, build: build);
  }

  int compareParts(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final leftPart = index < a.length ? a[index] : 0;
      final rightPart = index < b.length ? b[index] : 0;
      if (leftPart != rightPart) return leftPart.compareTo(rightPart);
    }
    return 0;
  }

  final a = parts(left);
  final b = parts(right);
  final coreResult = compareParts(a.core, b.core);
  if (coreResult != 0) return coreResult;

  // TetoTV tags may append the Android versionCode as SemVer build metadata.
  // SemVer normally ignores this suffix for precedence, but the updater must
  // distinguish two APK builds that share the same user-facing version name.
  return compareParts(a.build, b.build);
}

int? appVersionMajor(String value) {
  final normalized = normalizeAppVersion(value);
  return int.tryParse(normalized.split('.').first);
}

/// Decides whether the selected channel's release should be offered.
///
/// Public and Beta are two installable variants of the same signed app. Their
/// user-facing versions deliberately live in different major families (1.x
/// and 2.x), while paired builds may share the same monotonically allocated
/// Android versionCode. Crossing families is therefore an explicit channel
/// switch, not a SemVer upgrade/downgrade. Once the installed family matches
/// the selected channel, normal numeric comparison resumes so automatic checks
/// cannot repeatedly offer the already-installed counterpart.
bool shouldOfferAppRelease({
  required String currentVersion,
  required String releaseVersion,
  required AppUpdateChannel channel,
}) {
  final releaseMajor = appVersionMajor(releaseVersion);
  if (releaseMajor != channel.releaseMajor) return false;
  final currentMajor = appVersionMajor(currentVersion);
  final isKnownOtherChannel =
      currentMajor != null &&
      currentMajor != channel.releaseMajor &&
      AppUpdateChannel.values.any(
        (candidate) => candidate.releaseMajor == currentMajor,
      );
  if (isKnownOtherChannel) return true;
  return compareAppVersions(releaseVersion, currentVersion) > 0;
}

typedef CurrentVersionLoader = Future<String> Function();
typedef DeviceAbisLoader = Future<List<String>> Function();
typedef CacheDirectoryLoader = Future<Directory> Function();
typedef ApkInstaller = Future<String> Function(String path);
typedef ApkInspector = Future<ApkCompatibilityInfo> Function(String path);

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(
    this._storage,
    this._releaseSource,
    this._currentVersionLoader,
    this._deviceAbisLoader,
    this._cacheDirectoryLoader,
    this._apkInstaller, {
    AppReleaseSource? betaReleaseSource,
    this.automaticCheckInterval = const Duration(hours: 12),
    this.apkInspector,
  }) : _betaReleaseSource = betaReleaseSource ?? _releaseSource,
       super(const AppUpdateState());

  final FlutterSecureStorage _storage;
  final AppReleaseSource _releaseSource;
  final AppReleaseSource _betaReleaseSource;
  final CurrentVersionLoader _currentVersionLoader;
  final DeviceAbisLoader _deviceAbisLoader;
  final CacheDirectoryLoader _cacheDirectoryLoader;
  final ApkInstaller _apkInstaller;
  final Duration automaticCheckInterval;
  final ApkInspector? apkInspector;

  bool _loaded = false;
  Future<void>? _loadRequest;

  Future<void> load() {
    if (_loaded) return Future.value();
    final active = _loadRequest;
    if (active != null) return active;
    final request = _performLoad();
    _loadRequest = request;
    return request.whenComplete(() {
      if (identical(_loadRequest, request)) _loadRequest = null;
    });
  }

  Future<void> _performLoad() async {
    final values = await Future.wait([
      _storage.read(key: githubUpdateTokenStorageKey),
      _storage.read(key: automaticUpdatesStorageKey),
      _storage.read(key: updateChannelStorageKey),
      _storage.read(key: developerModeStorageKey),
      _storage.read(key: betaUpdateAccessKeyStorageKey),
      _currentVersionLoader(),
    ]);
    // Versions before the broker migration could store a GitHub credential on
    // the device. It is no longer used and is removed during the first load.
    if (values[0] != null) {
      await _storage.delete(key: githubUpdateTokenStorageKey);
    }
    final storedBetaAccessKey = (values[4] ?? '').trim();
    final hasBetaAccessKey = isValidBetaUpdateAccessKey(storedBetaAccessKey);
    if (values[4] != null && !hasBetaAccessKey) {
      await _storage.delete(key: betaUpdateAccessKeyStorageKey);
    }
    final developerMode = values[3] == 'true';
    final requestedBeta =
        developerMode && values[2] == AppUpdateChannel.beta.name;
    if (requestedBeta && !hasBetaAccessKey) {
      await _storage.write(
        key: updateChannelStorageKey,
        value: AppUpdateChannel.public.name,
      );
    }
    _loaded = true;
    if (!mounted) return;
    state = state.copyWith(
      currentVersion: values[5] ?? 'unknown',
      automaticUpdates: values[1] != 'false',
      developerMode: developerMode,
      hasBetaAccessKey: hasBetaAccessKey,
      updateChannel: requestedBeta && hasBetaAccessKey
          ? AppUpdateChannel.beta
          : AppUpdateChannel.public,
    );
  }

  Future<void> enableDeveloperMode() async {
    await load();
    if (state.developerMode) return;
    await _storage.write(key: developerModeStorageKey, value: 'true');
    state = state.copyWith(
      developerMode: true,
      message: 'Developer mode enabled. Update channels are now available.',
    );
  }

  Future<void> setUpdateChannel(AppUpdateChannel channel) async {
    await load();
    if (channel == AppUpdateChannel.beta && !state.developerMode) return;
    if (channel == AppUpdateChannel.beta && !state.hasBetaAccessKey) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message:
            'Set a private Beta access key before selecting the Beta channel.',
      );
      return;
    }
    if (state.isBusy || state.updateChannel == channel) return;
    await _storage.write(key: updateChannelStorageKey, value: channel.name);
    state = state.copyWith(
      updateChannel: channel,
      phase: AppUpdatePhase.idle,
      latestVersion: null,
      release: null,
      downloadedPath: null,
      progress: 0,
      message: '${channel.displayName} update channel selected.',
    );
  }

  Future<void> setBetaAccessKey(String value) async {
    await load();
    if (state.isBusy) return;
    final key = value.trim();
    if (!isValidBetaUpdateAccessKey(key)) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message:
            'Beta access keys must be 32-128 letters, numbers, hyphens, or underscores.',
      );
      return;
    }
    await _storage.write(key: betaUpdateAccessKeyStorageKey, value: key);
    state = state.copyWith(
      hasBetaAccessKey: true,
      phase: AppUpdatePhase.idle,
      latestVersion: null,
      release: null,
      downloadedPath: null,
      progress: 0,
      message: 'Beta access key saved securely. The key will not be displayed.',
    );
  }

  Future<void> clearBetaAccessKey() async {
    await load();
    if (state.isBusy) return;
    await Future.wait([
      _storage.delete(key: betaUpdateAccessKeyStorageKey),
      _storage.write(
        key: updateChannelStorageKey,
        value: AppUpdateChannel.public.name,
      ),
    ]);
    state = state.copyWith(
      hasBetaAccessKey: false,
      updateChannel: AppUpdateChannel.public,
      phase: AppUpdatePhase.idle,
      latestVersion: null,
      release: null,
      downloadedPath: null,
      progress: 0,
      message: 'Beta access key cleared. Public updates remain selected.',
    );
  }

  Future<void> setAutomaticUpdates(bool enabled) async {
    await load();
    await _storage.write(
      key: automaticUpdatesStorageKey,
      value: enabled.toString(),
    );
    state = state.copyWith(
      automaticUpdates: enabled,
      message: enabled
          ? 'Automatic update checks are on.'
          : 'Automatic update checks are off.',
    );
  }

  /// Returns release notes once, after Android has successfully installed the
  /// version they belong to. Merely downloading an APK never triggers them.
  Future<String?> takeInstalledReleaseNotes() async {
    await load();
    final values = await Future.wait([
      _storage.read(key: pendingReleaseNotesVersionStorageKey),
      _storage.read(key: pendingReleaseNotesStorageKey),
    ]);
    final targetVersion = (values[0] ?? '').trim();
    final notes = (values[1] ?? '').trim();
    if (targetVersion.isEmpty || notes.isEmpty) return null;
    // A Public/Beta channel switch may intentionally target a lower SemVer
    // while keeping the same Android versionCode. Do not mistake the currently
    // installed opposite channel for a successful install of that target.
    if (appVersionMajor(state.currentVersion) !=
        appVersionMajor(targetVersion)) {
      return null;
    }
    if (compareAppVersions(state.currentVersion, targetVersion) < 0) {
      return null;
    }
    await Future.wait([
      _storage.delete(key: pendingReleaseNotesVersionStorageKey),
      _storage.delete(key: pendingReleaseNotesStorageKey),
    ]);
    return notes;
  }

  Future<void> checkForUpdates({
    bool automatic = false,
    bool launchInstaller = false,
  }) async {
    await load();
    if (state.isBusy) return;
    if (state.updateChannel == AppUpdateChannel.beta &&
        !state.hasBetaAccessKey) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message:
            'Set a private Beta access key in Developer mode before checking Beta updates.',
      );
      return;
    }
    if (automatic) {
      if (!state.automaticUpdates) return;
      final saved = await _storage.read(key: _automaticCheckStorageKey);
      final lastCheck = DateTime.tryParse(saved ?? '');
      if (lastCheck != null) {
        final elapsed = DateTime.now().toUtc().difference(lastCheck.toUtc());
        if (!elapsed.isNegative && elapsed < automaticCheckInterval) return;
      }
    }
    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      progress: 0,
      message: automatic ? null : 'Checking the secure update service…',
    );
    try {
      final releaseSource = _sourceFor(state.updateChannel);
      final release = await releaseSource.latest(
        deviceAbis: await _deviceAbisLoader(),
      );
      if (appVersionMajor(release.version) !=
          state.updateChannel.releaseMajor) {
        throw FormatException(
          'The ${state.updateChannel.displayName} update service returned a '
          'release from the wrong version family.',
        );
      }
      if (!shouldOfferAppRelease(
        currentVersion: state.currentVersion,
        releaseVersion: release.version,
        channel: state.updateChannel,
      )) {
        state = state.copyWith(
          phase: AppUpdatePhase.upToDate,
          latestVersion: release.version,
          release: release,
          downloadedPath: null,
          message: 'TetoTV ${state.currentVersion} is up to date.',
        );
        await _recordSuccessfulAutomaticCheck(automatic);
        return;
      }
      state = state.copyWith(
        phase: AppUpdatePhase.available,
        latestVersion: release.version,
        release: release,
        downloadedPath: null,
        message:
            'TetoTV ${state.updateChannel.versionLabel(release.version)} '
            'is available on the '
            '${state.updateChannel.displayName} channel.',
      );
      await downloadUpdate(
        release: release,
        releaseSource: releaseSource,
        launchInstaller: launchInstaller,
      );
      if (state.phase == AppUpdatePhase.ready) {
        await _recordSuccessfulAutomaticCheck(automatic);
      }
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message:
            state.updateChannel == AppUpdateChannel.beta &&
                (status == 401 || status == 403)
            ? 'The Beta access key was rejected. Replace it in Developer mode.'
            : status == 404
            ? 'No TetoTV update is available right now.'
            : 'Update check failed: ${_safeUpdateError(error)}',
      );
    } catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message: 'Update check failed: ${_safeUpdateError(error)}',
      );
    }
  }

  Future<void> _recordSuccessfulAutomaticCheck(bool automatic) async {
    if (!automatic) return;
    try {
      await _storage.write(
        key: _automaticCheckStorageKey,
        value: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // A failed bookkeeping write must not turn a valid update check into an
      // error. The next launch may simply check GitHub again.
    }
  }

  Future<void> downloadUpdate({
    AppReleaseInfo? release,
    AppReleaseSource? releaseSource,
    bool launchInstaller = false,
  }) async {
    await load();
    final selected = release ?? state.release;
    if (selected == null || state.isBusy) return;
    state = state.copyWith(
      phase: AppUpdatePhase.downloading,
      progress: 0,
      message:
          'Downloading TetoTV '
          '${state.updateChannel.versionLabel(selected.version)}…',
    );
    try {
      final cache = await _cacheDirectoryLoader();
      final directory = Directory(path.join(cache.path, 'updates'));
      await directory.create(recursive: true);
      final destination = path.join(
        directory.path,
        path.basename(selected.asset.name),
      );
      var lastPercent = -1;
      await (releaseSource ?? _sourceFor(state.updateChannel)).download(
        release: selected,
        destination: destination,
        onProgress: (received, total) {
          if (total <= 0 || !mounted) return;
          final percent = ((received / total) * 100).floor().clamp(0, 100);
          if (percent == lastPercent) return;
          lastPercent = percent;
          state = state.copyWith(
            phase: AppUpdatePhase.downloading,
            progress: percent / 100,
            message:
                'Downloading TetoTV '
                '${state.updateChannel.versionLabel(selected.version)}… '
                '$percent%',
          );
        },
      );
      final file = File(destination);
      final size = await file.length();
      final expected = selected.asset.size;
      if (size < 1024 * 1024 || (expected > 0 && size != expected)) {
        await _deleteUpdateFile(file);
        throw StateError('The downloaded APK was incomplete.');
      }
      final expectedDigest = selected.asset.sha256Digest;
      if (expectedDigest != null) {
        final actualDigest = (await sha256.bind(file.openRead()).first)
            .toString()
            .toLowerCase();
        if (actualDigest != expectedDigest.toLowerCase()) {
          await _deleteUpdateFile(file);
          throw StateError('The downloaded APK failed its integrity check.');
        }
      }
      final inspection = await apkInspector?.call(destination);
      if (inspection != null) {
        if (!inspection.compatible) {
          await _deleteUpdateFile(file);
          throw StateError(
            'This APK is not compatible: ${inspection.issues.join(' ')}',
          );
        }
        if (inspection.versionName != selected.version) {
          await _deleteUpdateFile(file);
          throw StateError(
            'The downloaded APK did not match the selected release version.',
          );
        }
      }
      if (selected.notes.trim().isNotEmpty) {
        try {
          await Future.wait([
            _storage.write(
              key: pendingReleaseNotesVersionStorageKey,
              value: selected.version,
            ),
            _storage.write(
              key: pendingReleaseNotesStorageKey,
              value: selected.notes.trim(),
            ),
          ]);
        } catch (_) {
          // Release-note bookkeeping must never block a valid app update.
        }
      }
      state = state.copyWith(
        phase: AppUpdatePhase.ready,
        progress: 1,
        downloadedPath: destination,
        message:
            'TetoTV ${state.updateChannel.versionLabel(selected.version)} '
            'is ready to install.',
      );
      if (launchInstaller) await installDownloadedUpdate();
    } catch (error) {
      final betaAccessRejected =
          state.updateChannel == AppUpdateChannel.beta &&
          error is DioException &&
          (error.response?.statusCode == 401 ||
              error.response?.statusCode == 403);
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message: betaAccessRejected
            ? 'The Beta access key was rejected. Replace it in Developer mode.'
            : 'Update download failed: ${_safeUpdateError(error)}',
      );
    }
  }

  AppReleaseSource _sourceFor(AppUpdateChannel channel) =>
      channel == AppUpdateChannel.beta ? _betaReleaseSource : _releaseSource;

  String get _automaticCheckStorageKey =>
      state.updateChannel == AppUpdateChannel.public
      ? lastAutomaticUpdateCheckStorageKey
      : '${lastAutomaticUpdateCheckStorageKey}_${state.updateChannel.name}';

  Future<void> installDownloadedUpdate() async {
    final apkPath = state.downloadedPath;
    if (apkPath == null || state.isBusy) return;
    state = state.copyWith(
      phase: AppUpdatePhase.installing,
      message: 'Opening the Android installer…',
    );
    try {
      await _apkInstaller(apkPath);
      state = state.copyWith(
        phase: AppUpdatePhase.ready,
        message: 'Approve the TetoTV update in the Android installer.',
      );
    } catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message: 'Could not open the Android installer: $error',
      );
    }
  }
}

String _safeUpdateError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    return status == null
        ? 'network error'
        : 'update service returned HTTP $status';
  }
  if (error is StateError || error is FormatException) {
    var message = error.toString();
    message = message
        .replaceFirst(RegExp(r'^(Bad state|FormatException):\s*'), '')
        .replaceAll(RegExp(r'github_pat_[A-Za-z0-9_]+'), '[redacted]')
        .replaceAll(
          RegExp(
            r'(authorization|token)\s*[:=]\s*[^\s,;]+',
            caseSensitive: false,
          ),
          r'$1=[redacted]',
        );
    return message.length <= 240 ? message : '${message.substring(0, 240)}…';
  }
  return 'unexpected error';
}

Future<void> _deleteUpdateFile(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Best effort: Android's installer is never opened after validation fails.
  }
}
