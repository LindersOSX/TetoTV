import 'package:anime_tv/features/streaming/data/torbox_models.dart';
import 'package:dio/dio.dart';

class TorBoxException implements Exception {
  const TorBoxException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class TorBoxClient {
  TorBoxClient({required String token, Dio? dio})
    : _token = token,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.torbox.app/v1/api',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            ),
          );

  final String _token;
  final Dio _dio;

  Future<TorBoxAccount> account() async {
    final body = await _get('/user/me', query: const {'settings': false});
    return TorBoxAccount.fromJson(_dataMap(body));
  }

  Future<int> createTorrent(String magnetUri) async {
    final body = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '/torrents/createtorrent',
        data: FormData.fromMap({
          'magnet': magnetUri,
          'seed': 1,
          'allow_zip': false,
        }),
      ),
    );
    final torrentId = _asInt(_dataMap(body)['torrent_id']);
    if (torrentId <= 0) {
      throw const TorBoxException(
        'TorBox returned an invalid torrent ID. Try another stream.',
      );
    }
    return torrentId;
  }

  Future<TorBoxTorrent> torrentInfo(
    int torrentId, {
    bool bypassCache = true,
  }) async {
    final body = await _get(
      '/torrents/mylist',
      query: {'id': torrentId, 'bypass_cache': bypassCache},
    );
    final data = body['data'];
    final item = switch (data) {
      final Map<String, dynamic> value => value,
      final List<dynamic> values when values.isNotEmpty =>
        values.first as Map<String, dynamic>,
      _ => throw const TorBoxException('TorBox torrent was not found.'),
    };
    return TorBoxTorrent.fromJson(item);
  }

  Future<Uri> requestDownloadLink({
    required int torrentId,
    required int fileId,
  }) async {
    final body = await _get(
      '/torrents/requestdl',
      query: {
        'token': _token,
        'torrent_id': torrentId,
        'file_id': fileId,
        'zip_link': false,
        'redirect': false,
        'append_name': true,
      },
    );
    final value = body['data'];
    if (value is! String || !value.startsWith('https://')) {
      throw const TorBoxException(
        'TorBox did not return a secure streaming link.',
      );
    }
    return Uri.parse(value);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) {
    return _request(
      () => _dio.get<Map<String, dynamic>>(path, queryParameters: query),
    );
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() operation,
  ) async {
    try {
      final response = await operation();
      final body = response.data ?? const <String, dynamic>{};
      if (body['success'] != true) {
        throw TorBoxException(
          body['detail'] as String? ?? 'TorBox request failed.',
          code: body['error'] as String?,
        );
      }
      return body;
    } on TorBoxException {
      rethrow;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        throw TorBoxException(
          data['detail'] as String? ?? 'TorBox request failed.',
          code: data['error'] as String?,
        );
      }
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        throw const TorBoxException(
          'That TorBox API token is invalid or API access is unavailable.',
          code: 'AUTH_ERROR',
        );
      }
      throw TorBoxException(
        error.message ?? 'Could not reach TorBox.',
        code: '${error.response?.statusCode ?? ''}',
      );
    }
  }
}

Map<String, dynamic> _dataMap(Map<String, dynamic> body) {
  final data = body['data'];
  if (data is Map<String, dynamic>) return data;
  throw const TorBoxException('TorBox returned an unexpected response.');
}

int _asInt(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text) ?? 0,
  _ => 0,
};
