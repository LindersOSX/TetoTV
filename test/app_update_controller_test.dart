import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anime_tv/features/settings/application/app_update_controller.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const storage = FlutterSecureStorage();

  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  test('compares release versions numerically', () {
    expect(compareAppVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareAppVersions('v1.7.3', '1.7.3'), 0);
    expect(compareAppVersions('1.7.2', '1.7.3'), lessThan(0));
    expect(compareAppVersions('v1.9.0+34901', '1.9.0+34900'), greaterThan(0));
    expect(compareAppVersions('1.9.0+34900', 'v1.9.0'), greaterThan(0));
    expect(normalizeAppVersion('TetoTV v1.9.0+34901'), '1.9.0+34901');
  });

  test('coalesces concurrent secure-storage loads', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final version = Completer<String>();
    var versionLoads = 0;
    final controller = AppUpdateController(
      storage,
      _FakeReleaseSource(),
      () {
        versionLoads++;
        return version.future;
      },
      () async => const ['arm64-v8a'],
      Directory.systemTemp.createTemp,
      (_) async => 'launched',
    );

    final first = controller.load();
    final second = controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(versionLoads, 1);

    version.complete('1.9.0+34900');
    await Future.wait([first, second]);
    expect(controller.state.currentVersion, '1.9.0+34900');
  });

  test('prefers the universal APK across TV device ABIs', () {
    const assets = [
      AppReleaseAsset(
        name: 'TetoTV-universal.apk',
        apiUrl: 'u',
        publicUrl: 'pu',
        size: 1,
      ),
      AppReleaseAsset(
        name: 'TetoTV-arm64-v8a.apk',
        apiUrl: 'a64',
        publicUrl: 'pa64',
        size: 1,
      ),
      AppReleaseAsset(
        name: 'TetoTV-armeabi-v7a.apk',
        apiUrl: 'a32',
        publicUrl: 'pa32',
        size: 1,
      ),
    ];
    expect(selectApkAsset(assets, const ['arm64-v8a']).apiUrl, 'u');
    expect(selectApkAsset(assets, const ['armeabi-v7a']).apiUrl, 'u');
    expect(selectApkAsset(assets, const ['mips']).apiUrl, 'u');
  });

  test('selects a named ABI asset only when universal is unavailable', () {
    const assets = [
      AppReleaseAsset(
        name: 'TetoTV-arm64.apk',
        apiUrl: 'a64',
        publicUrl: 'pa64',
        size: 1,
      ),
      AppReleaseAsset(
        name: 'TetoTV-fire-tv-32bit.apk',
        apiUrl: 'a32',
        publicUrl: 'pa32',
        size: 1,
      ),
    ];
    expect(selectApkAsset(assets, const ['arm64-v8a']).apiUrl, 'a64');
    expect(selectApkAsset(assets, const ['armeabi-v7a']).apiUrl, 'a32');
  });

  test('GitHub public-release checks omit Authorization', () async {
    String? authorization;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            authorization = options.headers['Authorization']?.toString();
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: _githubReleasePayload,
              ),
            );
          },
        ),
      );

    final release = await GitHubAppReleaseSource(
      dio,
    ).latest(token: '', deviceAbis: const ['arm64-v8a']);

    expect(authorization, isNull);
    expect(release.asset.publicUrl, 'https://example.com/TetoTV.apk');
  });

  test('GitHub private-release checks use the optional saved token', () async {
    String? authorization;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            authorization = options.headers['Authorization']?.toString();
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: _githubReleasePayload,
              ),
            );
          },
        ),
      );

    await GitHubAppReleaseSource(
      dio,
    ).latest(token: 'private-read-token', deviceAbis: const ['arm64-v8a']);

    expect(authorization, 'Bearer private-read-token');
  });

  test('stale private token retries the public release anonymously', () async {
    final authorizations = <String?>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final authorization = options.headers['Authorization']?.toString();
            authorizations.add(authorization);
            if (authorization != null) {
              handler.reject(
                DioException.badResponse(
                  statusCode: 404,
                  requestOptions: options,
                  response: Response<void>(
                    requestOptions: options,
                    statusCode: 404,
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: _githubReleasePayload,
              ),
            );
          },
        ),
      );

    final release = await GitHubAppReleaseSource(
      dio,
    ).latest(token: 'expired-private-token', deviceAbis: const ['arm64-v8a']);

    expect(release.version, '1.7.3');
    expect(authorizations, ['Bearer expired-private-token', null]);
  });

  test('public release downloads use the public URL without a token', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tetotv-public-download-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final adapter = _RecordingDownloadAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final destination = '${directory.path}${Platform.pathSeparator}app.apk';

    await GitHubAppReleaseSource(dio).download(
      release: _downloadRelease,
      token: '',
      destination: destination,
      onProgress: (_, _) {},
    );

    expect(adapter.authorizations, [null]);
    expect(adapter.uris.single.toString(), _downloadRelease.asset.publicUrl);
    expect(await File(destination).readAsBytes(), adapter.payload);
  });

  test('private release downloads use the optional read-only token', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tetotv-private-download-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final adapter = _RecordingDownloadAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final destination = '${directory.path}${Platform.pathSeparator}app.apk';

    await GitHubAppReleaseSource(dio).download(
      release: _downloadRelease,
      token: 'private-read-token',
      destination: destination,
      onProgress: (_, _) {},
    );

    expect(adapter.authorizations, ['Bearer private-read-token']);
    expect(adapter.uris.single.toString(), _downloadRelease.asset.apiUrl);
    expect(await File(destination).readAsBytes(), adapter.payload);
  });

  test(
    'stale private download access retries the public URL cleanly',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tetotv-stale-download-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final adapter = _RecordingDownloadAdapter(rejectAuthenticated: true);
      final dio = Dio()..httpClientAdapter = adapter;
      final destination = '${directory.path}${Platform.pathSeparator}app.apk';
      await File(destination).writeAsBytes(const [9, 9, 9]);

      await GitHubAppReleaseSource(dio).download(
        release: _downloadRelease,
        token: 'expired-private-token',
        destination: destination,
        onProgress: (_, _) {},
      );

      expect(adapter.authorizations, ['Bearer expired-private-token', null]);
      expect(adapter.uris.map((uri) => uri.toString()), [
        _downloadRelease.asset.apiUrl,
        _downloadRelease.asset.publicUrl,
      ]);
      expect(await File(destination).readAsBytes(), adapter.payload);
    },
  );

  test('downloads a newer private release and opens the installer', () async {
    final directory = await Directory.systemTemp.createTemp('tetotv-update-');
    addTearDown(() => directory.delete(recursive: true));
    FlutterSecureStorage.setMockInitialValues({
      githubUpdateTokenStorageKey: 'read-only-token',
    });
    final source = _FakeReleaseSource();
    String? installedPath;
    final controller = AppUpdateController(
      storage,
      source,
      () async => '1.7.2',
      () async => const ['arm64-v8a'],
      () async => directory,
      (path) async {
        installedPath = path;
        return 'launched';
      },
    );

    await controller.load();
    await controller.checkForUpdates(launchInstaller: true);

    expect(source.requestedToken, 'read-only-token');
    expect(source.requestedAbis, const ['arm64-v8a']);
    expect(controller.state.phase, AppUpdatePhase.ready);
    expect(controller.state.latestVersion, '1.7.3');
    expect(installedPath, controller.state.downloadedPath);
    expect(File(installedPath!).lengthSync(), 2 * 1024 * 1024);
  });

  test('fresh installs check public releases without a token', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final controller = AppUpdateController(
      storage,
      _FakeReleaseSource(),
      () async => '1.7.3',
      () async => const ['arm64-v8a'],
      Directory.systemTemp.createTemp,
      (_) async => 'launched',
    );

    await controller.checkForUpdates();

    expect(controller.state.phase, AppUpdatePhase.upToDate);
    expect(controller.state.hasAccessToken, isFalse);
  });

  test('blocks an incompatible APK before opening Android installer', () async {
    final directory = await Directory.systemTemp.createTemp('tetotv-inspect-');
    addTearDown(() => directory.delete(recursive: true));
    FlutterSecureStorage.setMockInitialValues({
      githubUpdateTokenStorageKey: 'read-only-token',
    });
    var installerOpened = false;
    final controller = AppUpdateController(
      storage,
      _FakeReleaseSource(),
      () async => '1.7.2',
      () async => const ['arm64-v8a'],
      () async => directory,
      (_) async {
        installerOpened = true;
        return 'launched';
      },
      apkInspector: (_) async => const ApkCompatibilityInfo(
        compatible: false,
        issues: ['Signing certificate does not match.'],
      ),
    );

    await controller.checkForUpdates(launchInstaller: true);

    expect(controller.state.phase, AppUpdatePhase.error);
    expect(controller.state.message, contains('Signing certificate'));
    expect(installerOpened, isFalse);
  });

  test('preserves an optional private-repository token across load', () async {
    FlutterSecureStorage.setMockInitialValues({
      githubUpdateTokenStorageKey: 'user-entered-read-token',
    });
    final source = _FakeReleaseSource();
    final controller = AppUpdateController(
      storage,
      source,
      () async => '1.7.3',
      () async => const ['arm64-v8a'],
      Directory.systemTemp.createTemp,
      (_) async => 'launched',
    );

    await controller.load();
    await controller.checkForUpdates();

    expect(controller.state.hasAccessToken, isTrue);
    expect(source.requestedToken, 'user-entered-read-token');
    expect(
      await storage.read(key: githubUpdateTokenStorageKey),
      'user-entered-read-token',
    );
  });

  test(
    'removing an optional private token remains respected after restart',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        githubUpdateTokenStorageKey: 'user-entered-read-token',
      });
      AppUpdateController createController() => AppUpdateController(
        storage,
        _FakeReleaseSource(),
        () async => '1.7.3',
        () async => const ['arm64-v8a'],
        Directory.systemTemp.createTemp,
        (_) async => 'launched',
      );

      final first = createController();
      await first.load();
      await first.saveAccessToken('');
      final restarted = createController();
      await restarted.load();

      expect(restarted.state.hasAccessToken, isFalse);
      expect(await storage.read(key: githubUpdateTokenStorageKey), isNull);
    },
  );

  test('failed automatic downloads remain eligible for retry', () async {
    FlutterSecureStorage.setMockInitialValues({
      githubUpdateTokenStorageKey: 'read-only-token',
    });
    final directory = await Directory.systemTemp.createTemp('tetotv-retry-');
    addTearDown(() => directory.delete(recursive: true));
    final source = _FakeReleaseSource(throwOnDownload: true);
    final controller = AppUpdateController(
      storage,
      source,
      () async => '1.7.2+100',
      () async => const ['arm64-v8a'],
      () async => directory,
      (_) async => 'launched',
    );

    await controller.checkForUpdates(automatic: true);
    await controller.checkForUpdates(automatic: true);

    expect(source.latestCalls, 2);
    expect(controller.state.phase, AppUpdatePhase.error);
    expect(await storage.read(key: lastAutomaticUpdateCheckStorageKey), isNull);
  });

  test('successful automatic checks respect the retry interval', () async {
    FlutterSecureStorage.setMockInitialValues({
      githubUpdateTokenStorageKey: 'read-only-token',
    });
    final source = _FakeReleaseSource();
    final controller = AppUpdateController(
      storage,
      source,
      () async => '1.7.3',
      () async => const ['arm64-v8a'],
      Directory.systemTemp.createTemp,
      (_) async => 'launched',
    );

    await controller.checkForUpdates(automatic: true);
    await controller.checkForUpdates(automatic: true);

    expect(source.latestCalls, 1);
    expect(controller.state.phase, AppUpdatePhase.upToDate);
    expect(
      await storage.read(key: lastAutomaticUpdateCheckStorageKey),
      isNotNull,
    );
  });

  test(
    'release notes are claimed only after the update is installed',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        pendingReleaseNotesVersionStorageKey: '1.10.3',
        pendingReleaseNotesStorageKey: 'Improved playback.',
      });
      final oldController = AppUpdateController(
        storage,
        _FakeReleaseSource(),
        () async => '1.10.2+50001',
        () async => const ['arm64-v8a'],
        Directory.systemTemp.createTemp,
        (_) async => 'launched',
      );
      expect(await oldController.takeInstalledReleaseNotes(), isNull);

      final updatedController = AppUpdateController(
        storage,
        _FakeReleaseSource(),
        () async => '1.10.3+60001',
        () async => const ['arm64-v8a'],
        Directory.systemTemp.createTemp,
        (_) async => 'launched',
      );
      expect(
        await updatedController.takeInstalledReleaseNotes(),
        'Improved playback.',
      );
      expect(await updatedController.takeInstalledReleaseNotes(), isNull);
    },
  );

  test('future automatic-check timestamps do not suppress retries', () async {
    FlutterSecureStorage.setMockInitialValues({
      githubUpdateTokenStorageKey: 'read-only-token',
      lastAutomaticUpdateCheckStorageKey: DateTime.now()
          .toUtc()
          .add(const Duration(days: 1))
          .toIso8601String(),
    });
    final source = _FakeReleaseSource();
    final controller = AppUpdateController(
      storage,
      source,
      () async => '1.7.3',
      () async => const ['arm64-v8a'],
      Directory.systemTemp.createTemp,
      (_) async => 'launched',
    );

    await controller.checkForUpdates(automatic: true);

    expect(source.latestCalls, 1);
    expect(controller.state.phase, AppUpdatePhase.upToDate);
  });
}

const _githubReleasePayload = <String, dynamic>{
  'tag_name': 'v1.7.3',
  'name': 'TetoTV 1.7.3',
  'body': 'Update notes',
  'assets': [
    {
      'name': 'TetoTV-v1.7.3-universal.apk',
      'url': 'https://api.github.com/assets/1',
      'browser_download_url': 'https://example.com/TetoTV.apk',
      'size': 2097152,
    },
  ],
};

const _downloadRelease = AppReleaseInfo(
  tagName: 'v1.7.3',
  version: '1.7.3',
  name: 'TetoTV 1.7.3',
  asset: AppReleaseAsset(
    name: 'TetoTV-v1.7.3-universal.apk',
    apiUrl: 'https://api.github.com/repos/example/releases/assets/1',
    publicUrl: 'https://github.com/example/releases/download/app.apk',
    size: 4,
  ),
);

class _RecordingDownloadAdapter implements HttpClientAdapter {
  _RecordingDownloadAdapter({this.rejectAuthenticated = false});

  final bool rejectAuthenticated;
  final payload = const [1, 2, 3, 4];
  final authorizations = <String?>[];
  final uris = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authorization = options.headers['Authorization']?.toString();
    authorizations.add(authorization);
    uris.add(options.uri);
    if (rejectAuthenticated && authorization != null) {
      return ResponseBody.fromBytes(
        const [9, 9],
        404,
        headers: {
          Headers.contentLengthHeader: const ['2'],
        },
      );
    }
    return ResponseBody.fromBytes(
      payload,
      200,
      headers: {
        Headers.contentLengthHeader: [payload.length.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeReleaseSource implements AppReleaseSource {
  _FakeReleaseSource({this.throwOnDownload = false});

  final bool throwOnDownload;
  String? requestedToken;
  List<String>? requestedAbis;
  int latestCalls = 0;

  @override
  Future<AppReleaseInfo> latest({
    required String token,
    required List<String> deviceAbis,
  }) async {
    latestCalls++;
    requestedToken = token;
    requestedAbis = deviceAbis;
    return const AppReleaseInfo(
      tagName: 'v1.7.3',
      version: '1.7.3',
      name: 'TetoTV 1.7.3',
      asset: AppReleaseAsset(
        name: 'TetoTV-1.7.3-arm64-v8a.apk',
        apiUrl: 'asset',
        publicUrl: 'https://example.com/TetoTV.apk',
        size: 2 * 1024 * 1024,
      ),
    );
  }

  @override
  Future<void> download({
    required AppReleaseInfo release,
    required String token,
    required String destination,
    required void Function(int received, int total) onProgress,
  }) async {
    if (throwOnDownload) throw StateError('simulated download failure');
    final bytes = List<int>.filled(release.asset.size, 7);
    await File(destination).writeAsBytes(bytes, flush: true);
    onProgress(bytes.length, bytes.length);
  }
}
