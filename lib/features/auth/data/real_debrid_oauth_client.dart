import 'package:dio/dio.dart';

class RealDebridDeviceSession {
  const RealDebridDeviceSession({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresAt,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUrl;
  final Duration interval;
  final DateTime expiresAt;
}

class RealDebridOAuthCredentials {
  const RealDebridOAuthCredentials({
    required this.clientId,
    required this.clientSecret,
  });

  final String clientId;
  final String clientSecret;
}

class RealDebridTokenSet {
  const RealDebridTokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

class RealDebridOAuthClient {
  RealDebridOAuthClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.real-debrid.com/oauth/v2',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {'Accept': 'application/json'},
            ),
          );

  static const openSourceClientId = 'X245A4XAIBGVM';
  static const deviceGrant = 'http://oauth.net/grant_type/device/1.0';

  final Dio _dio;

  Future<RealDebridDeviceSession> startDeviceAuthorization() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/device/code',
      queryParameters: const {
        'client_id': openSourceClientId,
        'new_credentials': 'yes',
      },
    );
    final data = response.data!;
    final expiresIn = data['expires_in'] as int? ?? 1800;
    return RealDebridDeviceSession(
      deviceCode: data['device_code'] as String,
      userCode: data['user_code'] as String,
      verificationUrl: Uri.parse(data['verification_url'] as String),
      interval: Duration(seconds: data['interval'] as int? ?? 5),
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Future<RealDebridOAuthCredentials?> pollCredentials(
    RealDebridDeviceSession session,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/device/credentials',
      queryParameters: {
        'client_id': openSourceClientId,
        'code': session.deviceCode,
      },
      options: Options(
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    if (response.statusCode != 200 || response.data?['client_id'] == null) {
      return null;
    }
    return RealDebridOAuthCredentials(
      clientId: response.data!['client_id'] as String,
      clientSecret: response.data!['client_secret'] as String,
    );
  }

  Future<RealDebridTokenSet> exchangeDeviceCode({
    required RealDebridDeviceSession session,
    required RealDebridOAuthCredentials credentials,
  }) {
    return _tokenRequest(
      clientId: credentials.clientId,
      clientSecret: credentials.clientSecret,
      code: session.deviceCode,
    );
  }

  Future<RealDebridTokenSet> refresh({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) {
    return _tokenRequest(
      clientId: clientId,
      clientSecret: clientSecret,
      code: refreshToken,
    );
  }

  Future<RealDebridTokenSet> _tokenRequest({
    required String clientId,
    required String clientSecret,
    required String code,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/token',
      data: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': deviceGrant,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data!;
    return RealDebridTokenSet(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      expiresAt: DateTime.now().add(
        Duration(seconds: data['expires_in'] as int? ?? 3600),
      ),
    );
  }
}
