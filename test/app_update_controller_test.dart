import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anime_tv/features/settings/application/app_update_controller.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:crypto/crypto.dart';
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

  test('APK inspection parses the archive version name', () {
    final inspection = ApkCompatibilityInfo.fromMap(const {
      'compatible': true,
      'issues': <String>[],
      'packageName': 'dev.animetv.anime_tv',
      'versionCode': 410001,
      'versionName': '1.0.0',
    });

    expect(inspection.versionName, '1.0.0');
  });

  test('channel families allow intentional bidirectional switching', () {
    expect(
      shouldOfferAppRelease(
        currentVersion: '2.0.0+410001',
        releaseVersion: '1.0.0',
        channel: AppUpdateChannel.public,
      ),
      isTrue,
      reason: 'Public is an intentional sidegrade from the Beta family.',
    );
    expect(
      shouldOfferAppRelease(
        currentVersion: '1.0.0+410001',
        releaseVersion: '2.0.0',
        channel: AppUpdateChannel.beta,
      ),
      isTrue,
      reason: 'Beta is an intentional sidegrade from the Public family.',
    );
    expect(
      shouldOfferAppRelease(
        currentVersion: '1.0.0+410001',
        releaseVersion: '1.0.0',
        channel: AppUpdateChannel.public,
      ),
      isFalse,
    );
    expect(
      shouldOfferAppRelease(
        currentVersion: '2.0.0+410001',
        releaseVersion: '2.0.0',
        channel: AppUpdateChannel.beta,
      ),
      isFalse,
    );
  });

  test('a release must belong to the selected channel family', () {
    expect(
      shouldOfferAppRelease(
        currentVersion: '2.0.0+410001',
        releaseVersion: '2.0.1',
        channel: AppUpdateChannel.public,
      ),
      isFalse,
    );
    expect(
      shouldOfferAppRelease(
        currentVersion: '1.0.0+410001',
        releaseVersion: '1.0.1',
        channel: AppUpdateChannel.beta,
      ),
      isFalse,
    );
  });

  test('controller downloads either selected cross-family release', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tetotv-channel-switch-',
    );
    addTearDown(() => directory.delete(recursive: true));

    FlutterSecureStorage.setMockInitialValues({});
    final publicFromBeta = AppUpdateController(
      storage,
      _ChannelReleaseSource('1.0.0'),
      () async => '2.0.0+410001',
      () async => const ['arm64-v8a'],
      () async => directory,
      (_) async => 'launched',
      betaReleaseSource: _ChannelReleaseSource('2.0.0'),
    );
    await publicFromBeta.checkForUpdates();
    expect(publicFromBeta.state.phase, AppUpdatePhase.ready);
    expect(publicFromBeta.state.latestVersion, '1.0.0');

    FlutterSecureStorage.setMockInitialValues({
      developerModeStorageKey: 'true',
      updateChannelStorageKey: AppUpdateChannel.beta.name,
      betaUpdateAccessKeyStorageKey: _betaAccessKey,
    });
    final betaFromPublic = AppUpdateController(
      storage,
      _ChannelReleaseSource('1.0.0'),
      () async => '1.0.0+410001',
      () async => const ['arm64-v8a'],
      () async => directory,
      (_) async => 'launched',
      betaReleaseSource: _ChannelReleaseSource('2.0.0'),
    );
    await betaFromPublic.checkForUpdates();
    expect(betaFromPublic.state.phase, AppUpdatePhase.ready);
    expect(betaFromPublic.state.latestVersion, '2.0.0');
    expect(betaFromPublic.state.message, contains('2.0.0 Beta'));
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

  test('broker release checks send Beta key only to fixed endpoint', () async {
    String? authorization;
    Uri? requestedUri;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            authorization = options.headers['Authorization']?.toString();
            requestedUri = options.uri;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: _brokerReleasePayload,
              ),
            );
          },
        ),
      );

    final release = await BrokerAppReleaseSource(
      dio,
      accessKeyLoader: () async => _betaAccessKey,
    ).latest(deviceAbis: const ['arm64-v8a']);

    expect(authorization, 'Beta $_betaAccessKey');
    expect(
      requestedUri.toString(),
      '$tetoTvUpdateBroker/v1/app-updates/latest',
    );
    expect(release.version, '1.7.3');
    expect(release.notes, 'Update notes');
    expect(release.asset.sha256Digest, _zeroDigest);
    expect(
      release.asset.publicUrl,
      '$tetoTvUpdateBroker/v1/app-updates/releases/v1.7.3/assets/'
      '173001/universal.apk',
    );
  });

  test('broker rejects an off-origin APK download URL', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  ..._brokerReleasePayload,
                  'asset': <String, dynamic>{
                    ...(_brokerReleasePayload['asset']!
                        as Map<String, dynamic>),
                    'download_url': 'https://attacker.example/TetoTV.apk',
                  },
                },
              ),
            );
          },
        ),
      );

    await expectLater(
      BrokerAppReleaseSource(
        dio,
        accessKeyLoader: () async => _betaAccessKey,
      ).latest(deviceAbis: const ['arm64-v8a']),
      throwsA(isA<FormatException>()),
    );
  });

  test('broker rejects mutable and metadata-mismatched asset paths', () async {
    final tamperedUrls = <String>[
      '$tetoTvUpdateBroker/v1/app-updates/latest/universal.apk',
      '$tetoTvUpdateBroker/v1/app-updates/releases/v1.7.2/assets/'
          '173001/universal.apk',
      '$tetoTvUpdateBroker/v1/app-updates/releases/v1.7.3/assets/'
          'not-an-id/universal.apk',
      '$tetoTvUpdateBroker/v1/app-updates/releases/v1.7.3/assets/'
          '173001/universal.apk?part=2',
    ];

    for (final tamperedUrl in tamperedUrls) {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    ..._brokerReleasePayload,
                    'asset': <String, dynamic>{
                      ...(_brokerReleasePayload['asset']!
                          as Map<String, dynamic>),
                      'download_url': tamperedUrl,
                    },
                  },
                ),
              );
            },
          ),
        );

      await expectLater(
        BrokerAppReleaseSource(
          dio,
          accessKeyLoader: () async => _betaAccessKey,
        ).latest(deviceAbis: const ['arm64-v8a']),
        throwsA(isA<FormatException>()),
        reason: tamperedUrl,
      );
    }
  });

  test('anonymous GitHub fallback never sends Authorization', () async {
    String? authorization;
    Uri? requestedUri;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            authorization = options.headers['Authorization']?.toString();
            requestedUri = options.uri;
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
    ).latest(deviceAbis: const ['arm64-v8a']);

    expect(release.version, '1.7.3');
    expect(authorization, isNull);
    expect(
      requestedUri.toString(),
      'https://api.github.com/repos/$tetoTvPublicReleaseRepository/releases/latest',
    );
  });

  test('public releases reject off-repository APK URLs', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  ..._githubReleasePayload,
                  'assets': [
                    <String, dynamic>{
                      ...((_githubReleasePayload['assets']! as List).single
                          as Map<String, dynamic>),
                      'browser_download_url':
                          'https://downloads.example/TetoTV-v1.7.3-universal.apk',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    await expectLater(
      GitHubAppReleaseSource(dio).latest(deviceAbis: const ['arm64-v8a']),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'public is the default update channel and developer choices persist',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final publicSource = _ChannelReleaseSource('1.0.0');
      final betaSource = _ChannelReleaseSource('2.0.0');
      final controller = AppUpdateController(
        storage,
        publicSource,
        () async => '2.0.0+20000',
        () async => const ['arm64-v8a'],
        Directory.systemTemp.createTemp,
        (_) async => 'launched',
        betaReleaseSource: betaSource,
      );

      await controller.load();
      expect(controller.state.updateChannel, AppUpdateChannel.public);
      expect(controller.state.developerMode, isFalse);
      await controller.setUpdateChannel(AppUpdateChannel.beta);
      expect(controller.state.updateChannel, AppUpdateChannel.public);

      await controller.enableDeveloperMode();
      await controller.setUpdateChannel(AppUpdateChannel.beta);
      expect(controller.state.updateChannel, AppUpdateChannel.public);
      expect(controller.state.message, contains('Beta access key'));
      await controller.setBetaAccessKey(_betaAccessKey);
      expect(controller.state.hasBetaAccessKey, isTrue);
      expect(controller.state.message, isNot(contains(_betaAccessKey)));
      expect(
        await storage.read(key: betaUpdateAccessKeyStorageKey),
        _betaAccessKey,
      );
      await controller.setUpdateChannel(AppUpdateChannel.beta);
      await controller.checkForUpdates();
      expect(publicSource.latestCalls, 0);
      expect(betaSource.latestCalls, 1);
      expect(
        AppUpdateChannel.beta.versionLabel(betaSource.version),
        '2.0.0 Beta',
      );

      final restored = AppUpdateController(
        storage,
        publicSource,
        () async => '2.0.0+20000',
        () async => const ['arm64-v8a'],
        Directory.systemTemp.createTemp,
        (_) async => 'launched',
        betaReleaseSource: betaSource,
      );
      await restored.load();
      expect(restored.state.developerMode, isTrue);
      expect(restored.state.updateChannel, AppUpdateChannel.beta);
      expect(restored.state.hasBetaAccessKey, isTrue);
      await restored.clearBetaAccessKey();
      expect(restored.state.updateChannel, AppUpdateChannel.public);
      expect(restored.state.hasBetaAccessKey, isFalse);
      expect(await storage.read(key: betaUpdateAccessKeyStorageKey), isNull);
    },
  );

  test('invalid stored Beta key fails closed to Public', () async {
    FlutterSecureStorage.setMockInitialValues({
      developerModeStorageKey: 'true',
      updateChannelStorageKey: AppUpdateChannel.beta.name,
      betaUpdateAccessKeyStorageKey: 'too-short',
    });
    final controller = AppUpdateController(
      storage,
      _ChannelReleaseSource('1.0.0'),
      () async => '2.0.0+410001',
      () async => const ['arm64-v8a'],
      Directory.systemTemp.createTemp,
      (_) async => 'launched',
      betaReleaseSource: _ChannelReleaseSource('2.0.0'),
    );

    await controller.load();

    expect(controller.state.developerMode, isTrue);
    expect(controller.state.updateChannel, AppUpdateChannel.public);
    expect(controller.state.hasBetaAccessKey, isFalse);
    expect(await storage.read(key: betaUpdateAccessKeyStorageKey), isNull);
    expect(
      await storage.read(key: updateChannelStorageKey),
      AppUpdateChannel.public.name,
    );
  });

  test('broker-first source falls back to GitHub anonymously', () async {
    final brokerDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException.badResponse(
                statusCode: 503,
                requestOptions: options,
                response: Response<void>(
                  requestOptions: options,
                  statusCode: 503,
                ),
              ),
            );
          },
        ),
      );
    String? githubAuthorization;
    final githubDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            githubAuthorization = options.headers['Authorization']?.toString();
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

    final release = await BrokerFirstAppReleaseSource(
      BrokerAppReleaseSource(
        brokerDio,
        accessKeyLoader: () async => _betaAccessKey,
      ),
      GitHubAppReleaseSource(githubDio),
    ).latest(deviceAbis: const ['arm64-v8a']);

    expect(release.version, '1.7.3');
    expect(githubAuthorization, isNull);
  });

  test('broker APK downloads send the Beta key without redirects', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tetotv-broker-download-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final adapter = _RecordingDownloadAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final destination = '${directory.path}${Platform.pathSeparator}app.apk';

    await BrokerAppReleaseSource(
      dio,
      accessKeyLoader: () async => _betaAccessKey,
    ).download(
      release: _brokerDownloadRelease,
      destination: destination,
      onProgress: (_, _) {},
    );

    expect(adapter.authorizations, ['Beta $_betaAccessKey']);
    expect(adapter.followRedirects, [isFalse]);
    expect(
      adapter.uris.single.toString(),
      '$tetoTvUpdateBroker/v1/app-updates/releases/v1.7.3/assets/'
      '173001/universal.apk',
    );
    expect(await File(destination).readAsBytes(), adapter.payload);
  });

  test(
    'broker APK download rejects redirects instead of following them',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tetotv-broker-redirect-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final adapter = _RedirectingDownloadAdapter(
        redirectLocation: 'https://attacker.example/tetotv.apk',
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final destination = '${directory.path}${Platform.pathSeparator}app.apk';

      await expectLater(
        BrokerAppReleaseSource(
          dio,
          accessKeyLoader: () async => _betaAccessKey,
        ).download(
          release: _brokerDownloadRelease,
          destination: destination,
          onProgress: (_, _) {},
        ),
        throwsA(isA<DioException>()),
      );

      expect(adapter.followRedirects, [isFalse]);
      expect(adapter.uris, hasLength(1));
      expect(await File(destination).exists(), isFalse);
    },
  );

  test('broker refuses requests when no valid Beta key is stored', () async {
    final dio = Dio();
    final source = BrokerAppReleaseSource(
      dio,
      accessKeyLoader: () async => null,
    );

    await expectLater(
      source.latest(deviceAbis: const ['arm64-v8a']),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Beta access key'),
        ),
      ),
    );
  });

  test(
    'public APK download follows only a trusted redirect manually',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tetotv-public-download-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final adapter = _RedirectingDownloadAdapter(
        redirectLocation:
            'https://release-assets.githubusercontent.com/github-production-'
            'release-asset/123/tetotv.apk?sp=r&sig=signed',
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final destination = '${directory.path}${Platform.pathSeparator}app.apk';

      await GitHubAppReleaseSource(dio).download(
        release: _publicDownloadRelease,
        destination: destination,
        onProgress: (_, _) {},
      );

      expect(adapter.followRedirects, everyElement(isFalse));
      expect(adapter.uris, hasLength(2));
      expect(adapter.uris.last.host, 'release-assets.githubusercontent.com');
      expect(await File(destination).readAsBytes(), adapter.payload);
    },
  );

  test('public APK download rejects an untrusted redirect', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tetotv-public-redirect-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final adapter = _RedirectingDownloadAdapter(
      redirectLocation: 'https://attacker.example/tetotv.apk',
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final destination = '${directory.path}${Platform.pathSeparator}app.apk';

    await expectLater(
      GitHubAppReleaseSource(dio).download(
        release: _publicDownloadRelease,
        destination: destination,
        onProgress: (_, _) {},
      ),
      throwsA(isA<FormatException>()),
    );

    expect(adapter.followRedirects, everyElement(isFalse));
    expect(adapter.uris, hasLength(1));
    expect(await File(destination).exists(), isFalse);
  });

  test('downloads a newer broker release and opens the installer', () async {
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

    expect(source.requestedAbis, const ['arm64-v8a']);
    expect(await storage.read(key: githubUpdateTokenStorageKey), isNull);
    expect(controller.state.phase, AppUpdatePhase.ready);
    expect(controller.state.latestVersion, '1.7.3');
    expect(installedPath, controller.state.downloadedPath);
    expect(File(installedPath!).lengthSync(), 2 * 1024 * 1024);
  });

  test('fresh installs check the broker without a device token', () async {
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

  test('load deletes a legacy private-repository token', () async {
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

    expect(await storage.read(key: githubUpdateTokenStorageKey), isNull);
  });

  test('deletes an APK whose SHA-256 does not match metadata', () async {
    final directory = await Directory.systemTemp.createTemp('tetotv-digest-');
    addTearDown(() => directory.delete(recursive: true));
    var inspected = false;
    final source = _FakeReleaseSource(sha256Digest: _zeroDigest);
    final controller = AppUpdateController(
      storage,
      source,
      () async => '1.7.2',
      () async => const ['arm64-v8a'],
      () async => directory,
      (_) async => 'launched',
      apkInspector: (_) async {
        inspected = true;
        return const ApkCompatibilityInfo(
          compatible: true,
          issues: [],
          versionName: '1.7.3',
        );
      },
    );

    await controller.checkForUpdates(launchInstaller: true);

    final downloaded = File(
      '${directory.path}${Platform.pathSeparator}updates'
      '${Platform.pathSeparator}TetoTV-1.7.3-arm64-v8a.apk',
    );
    expect(controller.state.phase, AppUpdatePhase.error);
    expect(controller.state.message, contains('integrity check'));
    expect(await downloaded.exists(), isFalse);
    expect(inspected, isFalse);
  });

  test('accepts a matching SHA-256 before native APK inspection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tetotv-good-digest-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = List<int>.filled(2 * 1024 * 1024, 7);
    final digest = sha256.convert(bytes).toString();
    var inspected = false;
    final controller = AppUpdateController(
      storage,
      _FakeReleaseSource(sha256Digest: digest),
      () async => '1.7.2',
      () async => const ['arm64-v8a'],
      () async => directory,
      (_) async => 'launched',
      apkInspector: (_) async {
        inspected = true;
        return const ApkCompatibilityInfo(
          compatible: true,
          issues: [],
          versionName: '1.7.3',
        );
      },
    );

    await controller.checkForUpdates();

    expect(controller.state.phase, AppUpdatePhase.ready);
    expect(inspected, isTrue);
  });

  test('deletes an APK whose versionName does not match its release', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tetotv-version-name-',
    );
    addTearDown(() => directory.delete(recursive: true));
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
        compatible: true,
        issues: [],
        versionName: '1.7.4',
      ),
    );

    await controller.checkForUpdates(launchInstaller: true);

    final downloaded = File(
      '${directory.path}${Platform.pathSeparator}updates'
      '${Platform.pathSeparator}TetoTV-1.7.3-arm64-v8a.apk',
    );
    expect(controller.state.phase, AppUpdatePhase.error);
    expect(controller.state.message, contains('selected release version'));
    expect(await downloaded.exists(), isFalse);
    expect(installerOpened, isFalse);
  });

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

  test('matching Beta family automatic checks do not loop', () async {
    FlutterSecureStorage.setMockInitialValues({
      developerModeStorageKey: 'true',
      updateChannelStorageKey: AppUpdateChannel.beta.name,
      betaUpdateAccessKeyStorageKey: _betaAccessKey,
    });
    final publicSource = _ChannelReleaseSource('1.0.0');
    final betaSource = _ChannelReleaseSource('2.0.0');
    final controller = AppUpdateController(
      storage,
      publicSource,
      () async => '2.0.0+410001',
      () async => const ['arm64-v8a'],
      Directory.systemTemp.createTemp,
      (_) async => 'launched',
      betaReleaseSource: betaSource,
    );

    await controller.checkForUpdates(automatic: true);
    await controller.checkForUpdates(automatic: true);

    expect(controller.state.phase, AppUpdatePhase.upToDate);
    expect(betaSource.latestCalls, 1);
    expect(publicSource.latestCalls, 0);
    expect(
      await storage.read(key: '${lastAutomaticUpdateCheckStorageKey}_beta'),
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

  test(
    'opposite-channel install cancellation does not show release notes',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        pendingReleaseNotesVersionStorageKey: '1.0.0',
        pendingReleaseNotesStorageKey: 'Public release notes.',
      });
      final betaController = AppUpdateController(
        storage,
        _FakeReleaseSource(),
        () async => '2.0.0+410001',
        () async => const ['arm64-v8a'],
        Directory.systemTemp.createTemp,
        (_) async => 'launched',
      );

      expect(await betaController.takeInstalledReleaseNotes(), isNull);
      expect(
        await storage.read(key: pendingReleaseNotesStorageKey),
        'Public release notes.',
      );

      final publicController = AppUpdateController(
        storage,
        _FakeReleaseSource(),
        () async => '1.0.0+410001',
        () async => const ['arm64-v8a'],
        Directory.systemTemp.createTemp,
        (_) async => 'launched',
      );
      expect(
        await publicController.takeInstalledReleaseNotes(),
        'Public release notes.',
      );
    },
  );

  test(
    'public releases reject oversized APK metadata before download',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              final asset = Map<String, dynamic>.from(
                (_githubReleasePayload['assets']! as List).single
                    as Map<String, dynamic>,
              )..['size'] = maxPublicReleaseAssetBytes + 1;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    ..._githubReleasePayload,
                    'assets': [asset],
                  },
                ),
              );
            },
          ),
        );

      await expectLater(
        GitHubAppReleaseSource(dio).latest(deviceAbis: const ['arm64-v8a']),
        throwsStateError,
      );
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
      'browser_download_url':
          'https://github.com/LindersOSX/TetoTV-Releases/releases/download/'
          'v1.7.3/TetoTV-v1.7.3-universal.apk',
      'size': 2097152,
    },
  ],
};

const _zeroDigest =
    '0000000000000000000000000000000000000000000000000000000000000000';
const _betaAccessKey = 'beta_test_access_key_0123456789abcdef';

const _brokerReleasePayload = <String, dynamic>{
  'version': '1.7.3',
  'tag_name': 'v1.7.3',
  'name': 'TetoTV 1.7.3',
  'release_notes': 'Update notes',
  'published_at': '2026-08-10T00:00:00Z',
  'asset': <String, dynamic>{
    'name': 'TetoTV-v1.7.3-universal.apk',
    'size': 2097152,
    'content_type': 'application/vnd.android.package-archive',
    'download_url':
        '$tetoTvUpdateBroker/v1/app-updates/releases/v1.7.3/assets/'
        '173001/universal.apk',
    'digest': 'sha256:$_zeroDigest',
  },
};

const _brokerDownloadRelease = AppReleaseInfo(
  tagName: 'v1.7.3',
  version: '1.7.3',
  name: 'TetoTV 1.7.3',
  asset: AppReleaseAsset(
    name: 'TetoTV-v1.7.3-universal.apk',
    apiUrl:
        '$tetoTvUpdateBroker/v1/app-updates/releases/v1.7.3/assets/'
        '173001/universal.apk',
    publicUrl:
        '$tetoTvUpdateBroker/v1/app-updates/releases/v1.7.3/assets/'
        '173001/universal.apk',
    size: 4,
  ),
);

const _publicDownloadRelease = AppReleaseInfo(
  tagName: 'v1.7.3',
  version: '1.7.3',
  name: 'TetoTV 1.7.3',
  asset: AppReleaseAsset(
    name: 'TetoTV-v1.7.3-universal.apk',
    apiUrl: 'https://api.github.com/assets/173001',
    publicUrl:
        'https://github.com/LindersOSX/TetoTV-Releases/releases/download/'
        'v1.7.3/TetoTV-v1.7.3-universal.apk',
    size: 4,
  ),
);

class _RecordingDownloadAdapter implements HttpClientAdapter {
  final payload = const [1, 2, 3, 4];
  final authorizations = <String?>[];
  final uris = <Uri>[];
  final followRedirects = <bool>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authorization = options.headers['Authorization']?.toString();
    authorizations.add(authorization);
    uris.add(options.uri);
    followRedirects.add(options.followRedirects);
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

class _RedirectingDownloadAdapter implements HttpClientAdapter {
  _RedirectingDownloadAdapter({required this.redirectLocation});

  final String redirectLocation;
  final payload = const [1, 2, 3, 4];
  final uris = <Uri>[];
  final followRedirects = <bool>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    uris.add(options.uri);
    followRedirects.add(options.followRedirects);
    if (uris.length == 1) {
      return ResponseBody.fromBytes(
        const [],
        HttpStatus.found,
        headers: {
          HttpHeaders.locationHeader: [redirectLocation],
          Headers.contentLengthHeader: ['0'],
        },
      );
    }
    return ResponseBody.fromBytes(
      payload,
      HttpStatus.ok,
      headers: {
        Headers.contentLengthHeader: [payload.length.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeReleaseSource implements AppReleaseSource {
  _FakeReleaseSource({this.throwOnDownload = false, this.sha256Digest});

  final bool throwOnDownload;
  final String? sha256Digest;
  List<String>? requestedAbis;
  int latestCalls = 0;

  @override
  Future<AppReleaseInfo> latest({required List<String> deviceAbis}) async {
    latestCalls++;
    requestedAbis = deviceAbis;
    return AppReleaseInfo(
      tagName: 'v1.7.3',
      version: '1.7.3',
      name: 'TetoTV 1.7.3',
      asset: AppReleaseAsset(
        name: 'TetoTV-1.7.3-arm64-v8a.apk',
        apiUrl: 'asset',
        publicUrl: 'https://example.com/TetoTV.apk',
        size: 2 * 1024 * 1024,
        sha256Digest: sha256Digest,
      ),
    );
  }

  @override
  Future<void> download({
    required AppReleaseInfo release,
    required String destination,
    required void Function(int received, int total) onProgress,
  }) async {
    if (throwOnDownload) throw StateError('simulated download failure');
    final bytes = List<int>.filled(release.asset.size, 7);
    await File(destination).writeAsBytes(bytes, flush: true);
    onProgress(bytes.length, bytes.length);
  }
}

class _ChannelReleaseSource implements AppReleaseSource {
  _ChannelReleaseSource(this.version);

  final String version;
  int latestCalls = 0;

  @override
  Future<AppReleaseInfo> latest({required List<String> deviceAbis}) async {
    latestCalls += 1;
    return AppReleaseInfo(
      tagName: 'v$version',
      version: version,
      name: 'TetoTV $version',
      asset: AppReleaseAsset(
        name: 'TetoTV-v$version-universal.apk',
        apiUrl: 'https://example.com/TetoTV.apk',
        publicUrl: 'https://example.com/TetoTV.apk',
        size: 2 * 1024 * 1024,
      ),
    );
  }

  @override
  Future<void> download({
    required AppReleaseInfo release,
    required String destination,
    required void Function(int received, int total) onProgress,
  }) async {
    final bytes = List<int>.filled(release.asset.size, 9);
    await File(destination).writeAsBytes(bytes, flush: true);
    onProgress(bytes.length, bytes.length);
  }
}
