import 'dart:async';
import 'dart:io';

import 'package:anime_tv/features/settings/application/app_update_controller.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
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
      AppReleaseAsset(name: 'TetoTV-universal.apk', apiUrl: 'u', size: 1),
      AppReleaseAsset(name: 'TetoTV-arm64-v8a.apk', apiUrl: 'a64', size: 1),
      AppReleaseAsset(name: 'TetoTV-armeabi-v7a.apk', apiUrl: 'a32', size: 1),
    ];
    expect(selectApkAsset(assets, const ['arm64-v8a']).apiUrl, 'u');
    expect(selectApkAsset(assets, const ['armeabi-v7a']).apiUrl, 'u');
    expect(selectApkAsset(assets, const ['mips']).apiUrl, 'u');
  });

  test('selects a named ABI asset only when universal is unavailable', () {
    const assets = [
      AppReleaseAsset(name: 'TetoTV-arm64.apk', apiUrl: 'a64', size: 1),
      AppReleaseAsset(name: 'TetoTV-fire-tv-32bit.apk', apiUrl: 'a32', size: 1),
    ];
    expect(selectApkAsset(assets, const ['arm64-v8a']).apiUrl, 'a64');
    expect(selectApkAsset(assets, const ['armeabi-v7a']).apiUrl, 'a32');
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
