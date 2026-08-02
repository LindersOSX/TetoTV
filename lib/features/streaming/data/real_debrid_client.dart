import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:dio/dio.dart';

class RealDebridException implements Exception {
  const RealDebridException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

class RealDebridClient {
  RealDebridClient({required String token, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.real-debrid.com/rest/1.0',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            ),
          );

  final Dio _dio;

  Future<RealDebridAccount> account() async {
    final response = await _request<Map<String, dynamic>>(
      () => _dio.get('/user'),
    );
    return RealDebridAccount.fromJson(response.data!);
  }

  Future<String> addMagnet(String magnetUri) async {
    final response = await _request<Map<String, dynamic>>(
      () => _dio.post(
        '/torrents/addMagnet',
        data: {'magnet': magnetUri},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    return response.data!['id'] as String;
  }

  Future<RealDebridTorrentInfo> torrentInfo(String id) async {
    final response = await _request<Map<String, dynamic>>(
      () => _dio.get('/torrents/info/$id'),
    );
    return RealDebridTorrentInfo.fromJson(response.data!);
  }

  Future<void> selectFiles(String id, Iterable<int> fileIds) async {
    final selected = fileIds.join(',');
    if (selected.isEmpty) {
      throw const RealDebridException('No playable torrent files were found.');
    }
    await _request<void>(
      () => _dio.post(
        '/torrents/selectFiles/$id',
        data: {'files': selected},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (status) =>
              status != null && (status == 202 || status < 400),
        ),
      ),
    );
  }

  Future<RealDebridUnrestrictedLink> unrestrict(String link) async {
    final response = await _request<Map<String, dynamic>>(
      () => _dio.post(
        '/unrestrict/link',
        data: {'link': link},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    return RealDebridUnrestrictedLink.fromJson(response.data!);
  }

  Future<Response<T>> _request<T>(
    Future<Response<T>> Function() operation,
  ) async {
    try {
      return await operation();
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        throw RealDebridException(
          data['error'] as String? ?? 'Real-Debrid request failed.',
          code: data['error_code'] as int?,
        );
      }
      if (error.response?.statusCode == 401) {
        throw const RealDebridException(
          'That Real-Debrid token is invalid or expired.',
          code: 401,
        );
      }
      throw RealDebridException(
        error.message ?? 'Could not reach Real-Debrid.',
        code: error.response?.statusCode,
      );
    }
  }
}
