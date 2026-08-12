import 'package:anime_tv/core/diagnostics/anonymous_crash_reporter.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reporting stays completely dormant until explicit opt in', () async {
    final client = _CrashClient();
    final platform = _CrashPlatform();
    final reporter = AnonymousCrashReporter(client, platform);

    await reporter.record(
      kind: 'flutter',
      error: StateError('should stay local'),
      stack: StackTrace.current,
    );

    expect(client.reports, isEmpty);
    expect(platform.stored, isEmpty);
    expect(platform.enabled, isFalse);
  });

  test('opted-in report is redacted, delivered, and acknowledged', () async {
    final client = _CrashClient();
    final platform = _CrashPlatform();
    final reporter = AnonymousCrashReporter(client, platform);
    reporter.setEnabled(true);

    await reporter.record(
      kind: 'flutter',
      error: StateError('failed at https://secret.example/path?token=abc'),
      stack: StackTrace.fromString(
        'Bearer very-secret-token\nhttps://source.example/episode',
      ),
    );

    expect(platform.enabled, isTrue);
    expect(client.reports, hasLength(1));
    final report = client.reports.single;
    expect(report.message, contains('[URL]'));
    expect(report.message, isNot(contains('secret.example')));
    expect(report.stack, contains('Bearer [REDACTED]'));
    expect(report.stack, isNot(contains('source.example')));
    expect(report.toWireJson(), isNot(contains('report_id')));
    expect(report.toWireJson()['event_id'], report.reportId);
    expect(platform.acknowledged, [report.reportId]);
    expect(report.deviceClass, 'tv');
  });

  test('failed delivery remains queued and is retried next launch', () async {
    final platform = _CrashPlatform();
    final failing = _CrashClient(fail: true);
    final first = AnonymousCrashReporter(failing, platform);
    first.setEnabled(true);
    await first.record(
      kind: 'platform',
      error: ArgumentError('boom'),
      stack: StackTrace.current,
    );

    expect(platform.pendingReport, isNotNull);
    expect(platform.acknowledged, isEmpty);

    final succeeding = _CrashClient();
    final second = AnonymousCrashReporter(succeeding, platform);
    second.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(succeeding.reports, hasLength(1));
    expect(platform.pendingReport, isNull);
    expect(platform.acknowledged, hasLength(1));
  });

  test('opting out clears any queued report', () async {
    final platform = _CrashPlatform()
      ..pendingReport = {
        'report_id': 'dart-1',
        'kind': 'flutter',
        'message': 'queued',
        'stack': '',
        'occurred_at': '2026-08-12T12:00:00.000Z',
      };
    final reporter = AnonymousCrashReporter(_CrashClient(), platform);
    reporter.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    reporter.setEnabled(false);
    await Future<void>.delayed(Duration.zero);

    expect(platform.enabled, isFalse);
    expect(platform.pendingReport, isNull);
    expect(platform.clearCalls, greaterThanOrEqualTo(1));
  });
}

class _CrashClient implements AnonymousCrashReportClient {
  _CrashClient({this.fail = false});

  final bool fail;
  final reports = <AnonymousCrashReport>[];

  @override
  Future<void> send(AnonymousCrashReport report) async {
    reports.add(report);
    if (fail) throw StateError('broker unavailable');
  }
}

class _CrashPlatform implements AnonymousCrashPlatform {
  bool enabled = false;
  int clearCalls = 0;
  final stored = <Map<String, Object?>>[];
  final acknowledged = <String>[];
  Map<String, Object?>? pendingReport;

  @override
  Future<void> acknowledge(String reportId) async {
    acknowledged.add(reportId);
    if (pendingReport?['report_id'] == reportId) pendingReport = null;
  }

  @override
  Future<AppVersionInfo> appVersion() async =>
      const AppVersionInfo(name: '1.2.3', code: 123001);

  @override
  Future<void> clear() async {
    clearCalls += 1;
    pendingReport = null;
  }

  @override
  Future<TvDeviceProfile> deviceProfile() async => const TvDeviceProfile(
    manufacturer: 'Not sent',
    model: 'Not sent',
    sdk: 36,
    abis: ['arm64-v8a'],
    displayModes: [],
    hdrTypes: [],
    codecs: [],
    audioOutputs: [],
  );

  @override
  Future<bool> isTelevision() async => true;

  @override
  Future<Map<String, Object?>?> pending() async => pendingReport;

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<bool> store(Map<String, Object?> report) async {
    if (!enabled) return false;
    stored.add(report);
    pendingReport = Map<String, Object?>.from(report);
    return true;
  }
}
