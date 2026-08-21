import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:dio/dio.dart';

class WatchPartyClientException implements Exception {
  const WatchPartyClientException(this.code, {this.retryAfter});

  final String code;
  final Duration? retryAfter;

  @override
  String toString() => code;
}

class WatchPartyCreated {
  const WatchPartyCreated({required this.session});

  final WatchPartySession session;
}

class WatchPartyJoined {
  const WatchPartyJoined({required this.session, required this.snapshot});

  final WatchPartySession session;
  final WatchPartySnapshot snapshot;
}

class WatchPartyClient {
  WatchPartyClient({required String baseUrl, Dio? dio})
    : _baseUri = _validOrigin(baseUrl),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _validOrigin(baseUrl).toString(),
              connectTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
              followRedirects: false,
              maxRedirects: 0,
              headers: const {
                Headers.acceptHeader: Headers.jsonContentType,
                'User-Agent': 'TetoTV/2 Android',
              },
              validateStatus: (status) => status != null && status < 600,
            ),
          );

  final Uri _baseUri;
  final Dio _dio;

  Future<bool> health() async {
    final response = await _request(
      'GET',
      '/v1/watch-parties/health',
      authenticated: false,
    );
    return response['status'] == 'ok' && response['protocol'] == 1;
  }

  Future<WatchPartyCreated> create() async {
    final value = await _request(
      'POST',
      '/v1/watch-parties',
      authenticated: false,
      data: const <String, Object>{},
    );
    final roomCode = _roomCode(value['room_code']);
    final token = _token(value['host_token']);
    final expiresAt = _date(value['expires_at']);
    final watchPath = value['watch_url'] as String? ?? '/watch?room=$roomCode';
    final watchUri = _baseUri.resolve(watchPath);
    if (watchUri.origin != _baseUri.origin || watchUri.scheme != 'https') {
      throw const WatchPartyClientException('invalid_response');
    }
    return WatchPartyCreated(
      session: WatchPartySession(
        roomCode: roomCode,
        token: token,
        role: WatchPartyRole.host,
        expiresAt: expiresAt,
        watchUrl: watchUri,
      ),
    );
  }

  Future<WatchPartyJoined> join(String rawCode) async {
    final roomCode = normalizeWatchPartyCode(rawCode);
    if (roomCode == null) {
      throw const WatchPartyClientException('invalid_room_code');
    }
    final value = await _request(
      'POST',
      '/v1/watch-parties/join',
      authenticated: false,
      data: <String, Object>{'room_code': roomCode},
    );
    final token = _token(value['participant_token']);
    final expiresAt = _date(value['expires_at']);
    final snapshotValue = _map(value['state']);
    final snapshot = WatchPartySnapshot.fromJson(snapshotValue);
    return WatchPartyJoined(
      session: WatchPartySession(
        roomCode: roomCode,
        token: token,
        role: WatchPartyRole.guest,
        expiresAt: expiresAt,
        watchUrl: _baseUri.resolve('/watch?room=$roomCode'),
      ),
      snapshot: snapshot,
    );
  }

  Future<WatchPartySnapshot> snapshot(WatchPartySession session) async =>
      WatchPartySnapshot.fromJson(
        await _request(
          'GET',
          '/v1/watch-parties/${session.roomCode}',
          token: session.token,
        ),
      );

  Future<WatchPartySnapshot> updateState({
    required WatchPartySession session,
    required int baseRevision,
    required WatchPartyMedia? media,
    required bool playing,
    required Duration position,
  }) async => WatchPartySnapshot.fromJson(
    await _request(
      'PUT',
      '/v1/watch-parties/${session.roomCode}/state',
      token: session.token,
      data: <String, Object?>{
        'base_revision': baseRevision,
        'playing': playing,
        'position_ms': position.inMilliseconds.clamp(0, 86_400_000),
        'media': media?.toJson(),
      },
    ),
  );

  Future<WatchPartySnapshot> setReady({
    required WatchPartySession session,
    required bool ready,
  }) async => WatchPartySnapshot.fromJson(
    await _request(
      'POST',
      '/v1/watch-parties/${session.roomCode}/ready',
      token: session.token,
      data: <String, Object>{'ready': ready},
    ),
  );

  Future<void> leave(WatchPartySession session) async {
    await _request(
      'POST',
      '/v1/watch-parties/${session.roomCode}/leave',
      token: session.token,
      data: const <String, Object>{},
      allowNoContent: true,
    );
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    String? token,
    Object? data,
    bool authenticated = true,
    bool allowNoContent = false,
  }) async {
    if (authenticated && token == null) {
      throw const WatchPartyClientException('party_token_required');
    }
    Response<Object?> response;
    try {
      response = await _dio.request<Object?>(
        path,
        data: data,
        options: Options(
          method: method,
          headers: token == null
              ? null
              : <String, String>{'Authorization': 'Bearer $token'},
        ),
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw const WatchPartyClientException('timeout');
      }
      throw const WatchPartyClientException('network_unavailable');
    }
    final status = response.statusCode ?? 0;
    if (allowNoContent && status == 204) return const {};
    final value = _mapOrNull(response.data);
    if (status < 200 || status >= 300) {
      final retrySeconds = int.tryParse(
        response.headers.value('retry-after') ?? '',
      );
      throw WatchPartyClientException(
        value?['error'] as String? ?? 'server_error',
        retryAfter: retrySeconds == null
            ? null
            : Duration(seconds: retrySeconds),
      );
    }
    if (value == null) {
      throw const WatchPartyClientException('invalid_response');
    }
    return value;
  }
}

Uri _validOrigin(String rawValue) {
  final value = Uri.tryParse(rawValue.trim());
  if (value == null ||
      value.scheme != 'https' ||
      value.host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.path != '' && value.path != '/' ||
      value.hasQuery ||
      value.hasFragment) {
    throw const FormatException('Watch Together requires a root HTTPS origin.');
  }
  return value.replace(path: '/');
}

String? normalizeWatchPartyCode(String rawValue) {
  final normalized = rawValue.trim().toUpperCase().replaceAll(
    RegExp('[^A-Z0-9]'),
    '',
  );
  return RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(normalized)
      ? normalized
      : null;
}

Map<String, Object?> _map(Object? value) {
  final mapped = _mapOrNull(value);
  if (mapped == null) {
    throw const WatchPartyClientException('invalid_response');
  }
  return mapped;
}

Map<String, Object?>? _mapOrNull(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : null;

String _roomCode(Object? value) {
  final normalized = normalizeWatchPartyCode(value as String? ?? '');
  if (normalized == null) {
    throw const WatchPartyClientException('invalid_response');
  }
  return normalized;
}

String _token(Object? value) {
  final token = value as String? ?? '';
  if (!RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(token)) {
    throw const WatchPartyClientException('invalid_response');
  }
  return token;
}

DateTime _date(Object? value) {
  final date = DateTime.tryParse(value as String? ?? '')?.toUtc();
  if (date == null) {
    throw const WatchPartyClientException('invalid_response');
  }
  return date;
}
