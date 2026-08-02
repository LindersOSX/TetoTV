import 'dart:io';

import 'package:anime_tv/features/settings/application/app_update_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const storage = FlutterSecureStorage();

  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  test('compares release versions numerically', () {
    expect(compareAppVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareAppVersions('v1.7.3', '1.7.3'), 0);
    expect(compareAppVersions('1.7.2', '1.7.3'), lessThan(0));
  });

  test('selects the APK matching the TV ABI and falls back to universal', () {
    const assets = [
      AppReleaseAsset(name: 'TetoTV-universal.apk', apiUrl: 'u', size: 1),
      AppReleaseAsset(name: 'TetoTV-arm64-v8a.apk', apiUrl: 'a64', size: 1),
      AppReleaseAsset(name: 'TetoTV-armeabi-v7a.apk', apiUrl: 'a32', size: 1),
    ];
    expect(selectApkAsset(assets, const ['arm64-v8a']).apiUrl, 'a64');
    expect(selectApkAsset(assets, const ['armeabi-v7a']).apiUrl, 'a32');
    expect(selectApkAsset(assets, const ['mips']).apiUrl, 'u');
  });

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

  test('manual checks explain that a private token is required', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final controller = AppUpdateController(
      storage,
      _FakeReleaseSource(),
      () async => '1.7.2',
      () async => const ['arm64-v8a'],
      Directory.systemTemp.createTemp,
      (_) async => 'launched',
    );

    await controller.checkForUpdates();

    expect(controller.state.phase, AppUpdatePhase.error);
    expect(controller.state.message, contains('read-only GitHub token'));
  });

  test('imports a build-provisioned token into encrypted storage', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final source = _FakeReleaseSource();
    final controller = AppUpdateController(
      storage,
      source,
      () async => '1.7.3',
      () async => const ['arm64-v8a'],
      Directory.systemTemp.createTemp,
      (_) async => 'launched',
      bundledAccessToken: 'bundled-read-token',
    );

    await controller.load();
    await controller.checkForUpdates();

    expect(controller.state.hasAccessToken, isTrue);
    expect(source.requestedToken, 'bundled-read-token');
    expect(
      await storage.read(key: githubUpdateTokenStorageKey),
      'bundled-read-token',
    );
  });

  test(
    'removing a provisioned token remains respected after restart',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      AppUpdateController createController() => AppUpdateController(
        storage,
        _FakeReleaseSource(),
        () async => '1.7.3',
        () async => const ['arm64-v8a'],
        Directory.systemTemp.createTemp,
        (_) async => 'launched',
        bundledAccessToken: 'bundled-read-token',
      );

      final first = createController();
      await first.load();
      await first.saveAccessToken('');
      final restarted = createController();
      await restarted.load();

      expect(restarted.state.hasAccessToken, isFalse);
      expect(
        await storage.read(key: bundledGitHubUpdateTokenDisabledStorageKey),
        'true',
      );
    },
  );
}

class _FakeReleaseSource implements AppReleaseSource {
  String? requestedToken;
  List<String>? requestedAbis;

  @override
  Future<AppReleaseInfo> latest({
    required String token,
    required List<String> deviceAbis,
  }) async {
    requestedToken = token;
    requestedAbis = deviceAbis;
    return const AppReleaseInfo(
      tagName: 'v1.7.3',
      version: '1.7.3',
      name: 'TetoTV 1.7.3',
      asset: AppReleaseAsset(
        name: 'TetoTV-1.7.3-arm64-v8a.apk',
        apiUrl: 'asset',
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
    final bytes = List<int>.filled(release.asset.size, 7);
    await File(destination).writeAsBytes(bytes, flush: true);
    onProgress(bytes.length, bytes.length);
  }
}
