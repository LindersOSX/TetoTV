import 'dart:io';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const githubUpdateTokenStorageKey = 'github_update_token';
const bundledGitHubUpdateTokenDisabledStorageKey =
    'bundled_github_update_token_disabled';
const automaticUpdatesStorageKey = 'automatic_app_updates';
const lastAutomaticUpdateCheckStorageKey = 'last_automatic_update_check';
const tetoTvRepository = 'LindersOSX/TetoTV';

final appUpdateControllerProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      final bridge = AndroidTvBridge.instance;
      final controller = AppUpdateController(
        ref.watch(secureStorageProvider),
        GitHubAppReleaseSource(Dio()),
        () async => (await bridge.getAppVersion()).name,
        () async => (await bridge.getDeviceProfile()).abis,
        getTemporaryDirectory,
        bridge.installApk,
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
    this.hasAccessToken = false,
    this.automaticUpdates = true,
  });

  final AppUpdatePhase phase;
  final String currentVersion;
  final String? latestVersion;
  final AppReleaseInfo? release;
  final String? downloadedPath;
  final String? message;
  final double progress;
  final bool hasAccessToken;
  final bool automaticUpdates;

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
    bool? hasAccessToken,
    bool? automaticUpdates,
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
      hasAccessToken: hasAccessToken ?? this.hasAccessToken,
      automaticUpdates: automaticUpdates ?? this.automaticUpdates,
    );
  }
}

const _notProvided = Object();

class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.apiUrl,
    required this.size,
  });

  final String name;
  final String apiUrl;
  final int size;
}

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.asset,
  });

  final String tagName;
  final String version;
  final String name;
  final AppReleaseAsset asset;
}

abstract class AppReleaseSource {
  Future<AppReleaseInfo> latest({
    required String token,
    required List<String> deviceAbis,
  });

  Future<void> download({
    required AppReleaseInfo release,
    required String token,
    required String destination,
    required void Function(int received, int total) onProgress,
  });
}

class GitHubAppReleaseSource implements AppReleaseSource {
  GitHubAppReleaseSource(this._dio);

  final Dio _dio;

  @override
  Future<AppReleaseInfo> latest({
    required String token,
    required List<String> deviceAbis,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/$tetoTvRepository/releases/latest',
      options: Options(headers: _headers(token, 'application/vnd.github+json')),
    );
    final data = response.data;
    if (data == null) throw StateError('GitHub returned an empty release.');
    final assets = (data['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) => (item['name'] as String? ?? '').endsWith('.apk'))
        .map(
          (item) => AppReleaseAsset(
            name: item['name'] as String? ?? '',
            apiUrl: item['url'] as String? ?? '',
            size: (item['size'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((asset) => asset.name.isNotEmpty && asset.apiUrl.isNotEmpty)
        .toList(growable: false);
    if (assets.isEmpty) {
      throw StateError('The latest GitHub release has no APK attached.');
    }
    final asset = selectApkAsset(assets, deviceAbis);
    final tag = data['tag_name'] as String? ?? '';
    return AppReleaseInfo(
      tagName: tag,
      version: normalizeAppVersion(tag),
      name: data['name'] as String? ?? tag,
      asset: asset,
    );
  }

  @override
  Future<void> download({
    required AppReleaseInfo release,
    required String token,
    required String destination,
    required void Function(int received, int total) onProgress,
  }) {
    return _dio.download(
      release.asset.apiUrl,
      destination,
      options: Options(
        headers: _headers(token, 'application/octet-stream'),
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 20),
      ),
      onReceiveProgress: onProgress,
      deleteOnError: true,
    );
  }

  static Map<String, String> _headers(String token, String accept) => {
    'Accept': accept,
    'Authorization': 'Bearer $token',
    'X-GitHub-Api-Version': '2026-03-10',
    'User-Agent': 'TetoTV-AndroidTV-Updater',
  };
}

AppReleaseAsset selectApkAsset(
  List<AppReleaseAsset> assets,
  List<String> deviceAbis,
) {
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
  }
  for (final asset in assets) {
    if (asset.name.toLowerCase().contains('universal')) return asset;
  }
  return assets.first;
}

String normalizeAppVersion(String value) {
  final match = RegExp(r'\d+(?:\.\d+){0,3}').firstMatch(value);
  return match?.group(0) ?? value.trim().replaceFirst(RegExp(r'^[vV]'), '');
}

int compareAppVersions(String left, String right) {
  List<int> parts(String value) => normalizeAppVersion(
    value,
  ).split('.').map((item) => int.tryParse(item) ?? 0).toList();
  final a = parts(left);
  final b = parts(right);
  final length = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < length; index++) {
    final leftPart = index < a.length ? a[index] : 0;
    final rightPart = index < b.length ? b[index] : 0;
    if (leftPart != rightPart) return leftPart.compareTo(rightPart);
  }
  return 0;
}

typedef CurrentVersionLoader = Future<String> Function();
typedef DeviceAbisLoader = Future<List<String>> Function();
typedef CacheDirectoryLoader = Future<Directory> Function();
typedef ApkInstaller = Future<String> Function(String path);

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(
    this._storage,
    this._releaseSource,
    this._currentVersionLoader,
    this._deviceAbisLoader,
    this._cacheDirectoryLoader,
    this._apkInstaller, {
    this.automaticCheckInterval = const Duration(hours: 12),
    this.bundledAccessToken = const String.fromEnvironment(
      'TETOTV_GITHUB_UPDATE_TOKEN',
    ),
  }) : super(const AppUpdateState());

  final FlutterSecureStorage _storage;
  final AppReleaseSource _releaseSource;
  final CurrentVersionLoader _currentVersionLoader;
  final DeviceAbisLoader _deviceAbisLoader;
  final CacheDirectoryLoader _cacheDirectoryLoader;
  final ApkInstaller _apkInstaller;
  final Duration automaticCheckInterval;
  final String bundledAccessToken;

  String _token = '';
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final values = await Future.wait([
      _storage.read(key: githubUpdateTokenStorageKey),
      _storage.read(key: automaticUpdatesStorageKey),
      _currentVersionLoader(),
      _storage.read(key: bundledGitHubUpdateTokenDisabledStorageKey),
    ]);
    final storedToken = (values[0] ?? '').trim();
    final provisionedToken = bundledAccessToken.trim();
    final bundledTokenDisabled = values[3] == 'true';
    _token = storedToken;
    if (_token.isEmpty &&
        provisionedToken.isNotEmpty &&
        !bundledTokenDisabled) {
      _token = provisionedToken;
      await _storage.write(key: githubUpdateTokenStorageKey, value: _token);
    }
    _loaded = true;
    state = state.copyWith(
      currentVersion: values[2] ?? 'unknown',
      hasAccessToken: _token.isNotEmpty,
      automaticUpdates: values[1] != 'false',
    );
  }

  Future<void> saveAccessToken(String token) async {
    await load();
    _token = token.trim();
    if (_token.isEmpty) {
      await _storage.delete(key: githubUpdateTokenStorageKey);
      if (bundledAccessToken.trim().isNotEmpty) {
        await _storage.write(
          key: bundledGitHubUpdateTokenDisabledStorageKey,
          value: 'true',
        );
      }
    } else {
      await _storage.write(key: githubUpdateTokenStorageKey, value: _token);
      await _storage.delete(key: bundledGitHubUpdateTokenDisabledStorageKey);
    }
    state = state.copyWith(
      phase: AppUpdatePhase.idle,
      hasAccessToken: _token.isNotEmpty,
      message: _token.isEmpty
          ? 'Private GitHub access removed.'
          : 'Private GitHub access saved securely on this TV.',
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

  Future<void> checkForUpdates({
    bool automatic = false,
    bool launchInstaller = false,
  }) async {
    await load();
    if (state.isBusy) return;
    if (automatic) {
      if (!state.automaticUpdates || _token.isEmpty) return;
      final saved = await _storage.read(
        key: lastAutomaticUpdateCheckStorageKey,
      );
      final lastCheck = DateTime.tryParse(saved ?? '');
      if (lastCheck != null &&
          DateTime.now().difference(lastCheck) < automaticCheckInterval) {
        return;
      }
    }
    if (_token.isEmpty) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message:
            'Add a read-only GitHub token before checking this private repository.',
      );
      return;
    }
    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      progress: 0,
      message: automatic ? null : 'Checking the private GitHub release…',
    );
    try {
      final release = await _releaseSource.latest(
        token: _token,
        deviceAbis: await _deviceAbisLoader(),
      );
      await _storage.write(
        key: lastAutomaticUpdateCheckStorageKey,
        value: DateTime.now().toUtc().toIso8601String(),
      );
      if (compareAppVersions(release.version, state.currentVersion) <= 0) {
        state = state.copyWith(
          phase: AppUpdatePhase.upToDate,
          latestVersion: release.version,
          release: release,
          downloadedPath: null,
          message: 'TetoTV ${state.currentVersion} is up to date.',
        );
        return;
      }
      state = state.copyWith(
        phase: AppUpdatePhase.available,
        latestVersion: release.version,
        release: release,
        downloadedPath: null,
        message: 'TetoTV ${release.version} is available.',
      );
      await downloadUpdate(release: release, launchInstaller: launchInstaller);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message: status == 401 || status == 403 || status == 404
            ? 'GitHub could not open the private release. Check the read-only token.'
            : 'Update check failed: ${error.message ?? 'network error'}',
      );
    } catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message: 'Update check failed: $error',
      );
    }
  }

  Future<void> downloadUpdate({
    AppReleaseInfo? release,
    bool launchInstaller = false,
  }) async {
    await load();
    final selected = release ?? state.release;
    if (selected == null || state.isBusy) return;
    state = state.copyWith(
      phase: AppUpdatePhase.downloading,
      progress: 0,
      message: 'Downloading TetoTV ${selected.version}…',
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
      await _releaseSource.download(
        release: selected,
        token: _token,
        destination: destination,
        onProgress: (received, total) {
          if (total <= 0 || !mounted) return;
          final percent = ((received / total) * 100).floor().clamp(0, 100);
          if (percent == lastPercent) return;
          lastPercent = percent;
          state = state.copyWith(
            phase: AppUpdatePhase.downloading,
            progress: percent / 100,
            message: 'Downloading TetoTV ${selected.version}… $percent%',
          );
        },
      );
      final file = File(destination);
      final size = await file.length();
      final expected = selected.asset.size;
      if (size < 1024 * 1024 || (expected > 0 && size != expected)) {
        await file.delete().catchError((_) => file);
        throw StateError('The downloaded APK was incomplete.');
      }
      state = state.copyWith(
        phase: AppUpdatePhase.ready,
        progress: 1,
        downloadedPath: destination,
        message: 'TetoTV ${selected.version} is ready to install.',
      );
      if (launchInstaller) await installDownloadedUpdate();
    } catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        message: 'Update download failed: $error',
      );
    }
  }

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
