import 'dart:convert';
import 'dart:math';

import 'package:anime_tv/core/config/app_config.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:dio/dio.dart';

class ExplicitDiagnosticsReport {
  const ExplicitDiagnosticsReport({
    required this.eventId,
    required this.submittedAt,
    required this.appVersion,
    required this.buildNumber,
    required this.androidSdk,
    required this.abi,
    required this.deviceClass,
    required this.report,
  });

  final String eventId;
  final DateTime submittedAt;
  final String appVersion;
  final int buildNumber;
  final int androidSdk;
  final String abi;
  final String deviceClass;
  final String report;

  factory ExplicitDiagnosticsReport.fromSnapshot({
    required AppVersionInfo version,
    required TvDeviceProfile profile,
    required bool isTelevision,
    required Map<String, Object?> diagnostics,
    DateTime? submittedAt,
    Random? random,
  }) {
    final timestamp = (submittedAt ?? DateTime.now()).toUtc();
    return ExplicitDiagnosticsReport(
      eventId: _newEventId(random ?? Random.secure()),
      submittedAt: timestamp,
      appVersion: _safeVersion(version.name),
      buildNumber: version.code.clamp(1, 999999999),
      androidSdk: profile.sdk.clamp(24, 99),
      abi: _safeAbi(profile.abis.firstOrNull ?? 'unknown'),
      deviceClass: isTelevision ? 'tv' : 'phone',
      report: buildRedactedDiagnosticsText(
        version: version,
        profile: profile,
        isTelevision: isTelevision,
        diagnostics: diagnostics,
        generatedAt: timestamp,
      ),
    );
  }

  Map<String, Object?> toWireJson() => {
    'schema_version': 1,
    // This random value belongs to this button press only. It is neither an
    // installation ID nor a device ID and exists only to make retries safe.
    'event_id': eventId,
    'submitted_at': submittedAt.toIso8601String(),
    'app_version': appVersion,
    'build_number': buildNumber,
    'android_sdk': androidSdk,
    'abi': abi,
    'device_class': deviceClass,
    'report': report,
  };
}

class ExplicitDiagnosticsAcknowledgement {
  const ExplicitDiagnosticsAcknowledgement({
    required this.reference,
    required this.duplicate,
  });

  final String reference;
  final bool duplicate;
}

class DiagnosticsShareException implements Exception {
  const DiagnosticsShareException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef DiagnosticsRetryDelay = Future<void> Function(Duration duration);

abstract interface class ExplicitDiagnosticsReportApi {
  Future<ExplicitDiagnosticsAcknowledgement> send(
    ExplicitDiagnosticsReport report,
  );
}

class ExplicitDiagnosticsReportClient implements ExplicitDiagnosticsReportApi {
  ExplicitDiagnosticsReportClient({
    Dio? dio,
    String? baseUrl,
    DiagnosticsRetryDelay? retryDelay,
  }) : _origin = _validatedOrigin(
         (baseUrl ?? AppConfig.diagnosticReportBaseUrl).trim(),
       ),
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 6),
               sendTimeout: const Duration(seconds: 6),
               receiveTimeout: const Duration(seconds: 10),
             ),
           );

  final String _origin;
  final Dio _dio;
  final DiagnosticsRetryDelay _retryDelay;

  @override
  Future<ExplicitDiagnosticsAcknowledgement> send(
    ExplicitDiagnosticsReport report,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      late final Response<Object?> response;
      try {
        response = await _dio.post<Object?>(
          '$_origin/v1/diagnostic-reports',
          data: report.toWireJson(),
          options: Options(
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            sendTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 10),
            followRedirects: false,
            maxRedirects: 0,
            responseType: ResponseType.json,
            validateStatus: (_) => true,
          ),
        );
      } on DioException catch (error) {
        if (attempt < 2 && _retryableDioFailure(error)) {
          await _retryDelay(Duration(milliseconds: 350 * (attempt + 1)));
          continue;
        }
        throw const DiagnosticsShareException(
          'The diagnostic service could not be reached. Check the connection and try again.',
        );
      }

      final status = response.statusCode ?? 0;
      if (status == 202) {
        final data = response.data;
        if (data is Map) {
          final delivery = data['status'];
          final reference = data['incident_id'];
          if ((delivery == 'posted' || delivery == 'duplicate') &&
              reference is String &&
              RegExp(r'^[A-Za-z0-9_-]{16,40}$').hasMatch(reference)) {
            return ExplicitDiagnosticsAcknowledgement(
              reference: reference,
              duplicate: delivery == 'duplicate',
            );
          }
        }
        throw const DiagnosticsShareException(
          'The diagnostic service returned an invalid confirmation. Try again.',
        );
      }
      if (status == 503 && attempt < 2) {
        await _retryDelay(Duration(milliseconds: 350 * (attempt + 1)));
        continue;
      }
      if (status == 429) {
        throw const DiagnosticsShareException(
          'Too many diagnostic reports were sent. Wait one minute and try again.',
        );
      }
      if (status == 413) {
        throw const DiagnosticsShareException(
          'The diagnostic report was too large to send. Refresh Diagnostics and try again.',
        );
      }
      if (status == 400 || status == 415) {
        throw const DiagnosticsShareException(
          'The diagnostic service rejected this report. Refresh Diagnostics and try again.',
        );
      }
      throw const DiagnosticsShareException(
        'The Discord diagnostic channel is temporarily unavailable. Try again shortly.',
      );
    }
    throw const DiagnosticsShareException(
      'The Discord diagnostic channel is temporarily unavailable. Try again shortly.',
    );
  }

  static String _validatedOrigin(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const DiagnosticsShareException(
        'The diagnostic service is not configured safely.',
      );
    }
    return uri.origin;
  }
}

bool _retryableDioFailure(DioException error) => switch (error.type) {
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout ||
  DioExceptionType.connectionError ||
  DioExceptionType.unknown => true,
  _ => false,
};

String buildRedactedDiagnosticsText({
  required AppVersionInfo version,
  required TvDeviceProfile profile,
  required bool isTelevision,
  required Map<String, Object?> diagnostics,
  required DateTime generatedAt,
}) {
  final payload = <String, Object?>{
    'schema': 'tetotv-explicit-diagnostics-v1',
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'app': {
      'name': 'TetoTV',
      'version': _safeVersion(version.name),
      'build': version.code.clamp(1, 999999999),
    },
    'deviceClass': isTelevision ? 'tv' : 'phone',
    'deviceCapabilities': profile.toJson(),
    'diagnostics': diagnostics,
    'privacy':
        'Explicit user share. Credentials, direct stream URLs, magnets, hashes, and common token formats are redacted.',
  };
  final safe = _sanitizeSnapshot(payload, depth: 0);
  final text = const JsonEncoder.withIndent('  ').convert(safe);
  if (text.length <= 10000) return text;
  return '${text.substring(0, 9970)}\n[REPORT TRUNCATED]';
}

Object? _sanitizeSnapshot(Object? value, {required int depth}) {
  if (depth > 8) return '[DEPTH LIMITED]';
  if (value == null || value is bool || value is num) return value;
  if (value is String) {
    return redactDiagnosticValue(value, maximum: 2000);
  }
  if (value is List) {
    return [
      for (final item in value.take(100))
        _sanitizeSnapshot(item, depth: depth + 1),
    ];
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries.take(200)) {
      final key = redactDiagnosticValue(entry.key.toString(), maximum: 80);
      result[key] = _sanitizeSnapshot(entry.value, depth: depth + 1);
    }
    return result;
  }
  return redactDiagnosticValue(value.toString(), maximum: 500);
}

String _newEventId(Random random) {
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return 'diag-${base64Url.encode(bytes).replaceAll('=', '')}';
}

String _safeVersion(String value) {
  final normalized = value.trim();
  return RegExp(r'^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$').hasMatch(normalized)
      ? normalized
      : '0.0.0';
}

String _safeAbi(String value) {
  final normalized = value.trim().toLowerCase();
  return const {
        'arm64-v8a',
        'armeabi-v7a',
        'x86_64',
        'x86',
      }.contains(normalized)
      ? normalized
      : 'unknown';
}
