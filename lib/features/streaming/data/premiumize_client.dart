import 'package:anime_tv/features/streaming/data/premiumize_models.dart';
import 'package:dio/dio.dart';

class PremiumizeException implements Exception {
  const PremiumizeException(this.message, {this.code});

  final String message;
  final String? code;

  bool get isAuthenticationFailure =>
      code == 'authentication_failed' || code == 'permission_denied';

  @override
  String toString() => message;
}

/// Official Premiumize API client.
///
/// Credentials are always sent in the Authorization header. They are never
/// placed in query parameters, form fields, exception messages, or URLs.
class PremiumizeClient {
  PremiumizeClient({required String token, Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://www.premiumize.me')) {
    _dio.options
      ..connectTimeout ??= const Duration(seconds: 15)
      ..receiveTimeout ??= const Duration(seconds: 30);
    _dio.options.headers.addAll({
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'User-Agent': 'TetoTV Android',
    });
  }

  final Dio _dio;

  Future<PremiumizeAccount> account() async {
    final body = await _get('/api/account/info');
    return PremiumizeAccount.fromJson(body);
  }

  Future<List<PremiumizeFile>> directDownload(String source) async {
    final body = await _post('/api/transfer/directdl', {'src': source});
    final values = body['content'];
    if (values is! List) {
      throw const PremiumizeException(
        'Premiumize did not return any cached files.',
        code: 'not_found',
      );
    }
    final files = <PremiumizeFile>[];
    for (final value in values) {
      if (value is! Map) continue;
      try {
        files.add(PremiumizeFile.fromJson(Map<String, dynamic>.from(value)));
      } on FormatException {
        // One malformed or non-downloadable entry must not hide valid files.
      }
    }
    if (files.isEmpty) {
      throw const PremiumizeException(
        'Premiumize did not return any playable cached files.',
        code: 'not_found',
      );
    }
    return List.unmodifiable(files);
  }

  Future<PremiumizeTransferCreation> createTransfer(String source) async {
    final body = await _post('/api/transfer/create', {'src': source});
    final id = body['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const PremiumizeException(
        'Premiumize did not return a transfer ID.',
      );
    }
    return PremiumizeTransferCreation(
      id: id,
      name: body['name']?.toString() ?? 'Premiumize transfer',
    );
  }

  Future<List<PremiumizeTransfer>> transfers() async {
    final body = await _get('/api/transfer/list');
    final values = body['transfers'];
    if (values is! List) {
      throw const PremiumizeException(
        'Premiumize returned an invalid transfer list.',
      );
    }
    return List.unmodifiable([
      for (final value in values)
        if (value is Map)
          PremiumizeTransfer.fromJson(Map<String, dynamic>.from(value)),
    ]);
  }

  Future<PremiumizeFile> itemDetails(String id) async {
    final body = await _get('/api/item/details', query: {'id': id});
    return PremiumizeFile.fromJson(body);
  }

  Future<List<PremiumizeFolderEntry>> folderContents(String id) async {
    final body = await _get('/api/folder/list', query: {'id': id});
    final values = body['content'];
    if (values is! List) {
      throw const PremiumizeException(
        'Premiumize returned an invalid folder listing.',
      );
    }
    final entries = <PremiumizeFolderEntry>[];
    for (final value in values) {
      if (value is! Map) continue;
      try {
        entries.add(
          PremiumizeFolderEntry.fromJson(Map<String, dynamic>.from(value)),
        );
      } on FormatException {
        // Skip malformed entries while keeping valid cloud files available.
      }
    }
    return List.unmodifiable(entries);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) => _request(
    () => _dio.get<Map<String, dynamic>>(path, queryParameters: query),
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> fields,
  ) => _request(
    () => _dio.post<Map<String, dynamic>>(
      path,
      data: fields,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    ),
  );

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() operation,
  ) async {
    try {
      final response = await operation();
      final body = response.data ?? const <String, dynamic>{};
      if (body['status'] != 'success') throw _apiError(body);
      return body;
    } on PremiumizeException {
      rethrow;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map) {
        throw _apiError(Map<String, dynamic>.from(data));
      }
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        throw const PremiumizeException(
          'That Premiumize API key is invalid or access was denied.',
          code: 'authentication_failed',
        );
      }
      throw PremiumizeException(
        error.message ?? 'Could not reach Premiumize.',
        code: 'network_error',
      );
    } on FormatException catch (error) {
      throw PremiumizeException(error.message, code: 'invalid_response');
    }
  }
}

PremiumizeException _apiError(Map<String, dynamic> body) {
  final code = body['code']?.toString();
  final defaultMessage = code == 'authentication_failed'
      ? 'That Premiumize API key is invalid or expired.'
      : 'Premiumize request failed.';
  return PremiumizeException(
    body['message']?.toString() ?? defaultMessage,
    code: code,
  );
}
