import 'package:anime_tv/features/streaming/data/all_debrid_models.dart';
import 'package:dio/dio.dart';

class AllDebridException implements Exception {
  const AllDebridException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class AllDebridClient {
  AllDebridClient({
    required String token,
    Dio? dio,
    this.delayedPollInterval = const Duration(seconds: 5),
    this.delayedTimeout = const Duration(minutes: 2),
  }) : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://api.alldebrid.com')) {
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
  final Duration delayedPollInterval;
  final Duration delayedTimeout;

  Future<AllDebridAccount> account() async {
    final data = await _get('/v4/user');
    return AllDebridAccount.fromJson(_map(data['user']));
  }

  Future<AllDebridMagnetUpload> uploadMagnet(String magnetUri) async {
    final data = await _post('/v4/magnet/upload', {'magnets[]': magnetUri});
    final magnets = data['magnets'];
    if (magnets is! List || magnets.isEmpty || magnets.first is! Map) {
      throw const AllDebridException('AllDebrid did not accept that magnet.');
    }
    final item = Map<String, dynamic>.from(magnets.first as Map);
    if (item['error'] is Map) {
      throw _apiError(Map<String, dynamic>.from(item['error'] as Map));
    }
    final id = _asInt(item['id']);
    if (id <= 0) {
      throw const AllDebridException(
        'AllDebrid returned an invalid magnet ID.',
      );
    }
    return AllDebridMagnetUpload(id: id, ready: item['ready'] == true);
  }

  Future<AllDebridMagnetStatus> magnetStatus(int id) async {
    final data = await _post('/v4.1/magnet/status', {'id': id});
    final magnets = data['magnets'];
    final Object? raw = magnets is List && magnets.isNotEmpty
        ? magnets.first
        : magnets;
    if (raw is! Map) {
      throw const AllDebridException('AllDebrid magnet was not found.');
    }
    return AllDebridMagnetStatus.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<List<AllDebridTorrentFile>> magnetFiles(int id) async {
    final data = await _post('/v4/magnet/files', {'id[]': id});
    final magnets = data['magnets'];
    if (magnets is! List || magnets.isEmpty || magnets.first is! Map) {
      throw const AllDebridException(
        'AllDebrid returned no files for that magnet.',
      );
    }
    final magnet = Map<String, dynamic>.from(magnets.first as Map);
    if (magnet['error'] is Map) {
      throw _apiError(Map<String, dynamic>.from(magnet['error'] as Map));
    }
    final files = <AllDebridTorrentFile>[];
    _flattenFiles(magnet['files'], '', files);
    return List.unmodifiable(files);
  }

  Future<Uri> unlock(String link) async {
    final data = await _post('/v4/link/unlock', {'link': link});
    var value = data['link']?.toString();
    final delayedId = _asInt(data['delayed']);
    if ((value == null || value.isEmpty) && delayedId > 0) {
      final deadline = DateTime.now().add(delayedTimeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(delayedPollInterval);
        final delayed = await _post('/v4/link/delayed', {'id': delayedId});
        final status = _asInt(delayed['status']);
        if (status == 3) {
          throw const AllDebridException(
            'AllDebrid could not generate the streaming link.',
          );
        }
        value = delayed['link']?.toString();
        if (status == 2 && value != null && value.isNotEmpty) break;
      }
    }
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw const AllDebridException(
        'AllDebrid did not return a secure streaming link.',
      );
    }
    return uri;
  }

  Future<Map<String, dynamic>> _get(String path) =>
      _request(() => _dio.get<Map<String, dynamic>>(path));

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
      if (body['status'] != 'success') {
        final error = body['error'];
        if (error is Map) {
          throw _apiError(Map<String, dynamic>.from(error));
        }
        throw const AllDebridException('AllDebrid request failed.');
      }
      return _map(body['data']);
    } on AllDebridException {
      rethrow;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        throw _apiError(Map<String, dynamic>.from(data['error'] as Map));
      }
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        throw const AllDebridException(
          'That AllDebrid API key is invalid or blocked.',
          code: 'AUTH_ERROR',
        );
      }
      throw AllDebridException(
        error.message ?? 'Could not reach AllDebrid.',
        code: '${error.response?.statusCode ?? ''}',
      );
    }
  }
}

void _flattenFiles(
  Object? raw,
  String parent,
  List<AllDebridTorrentFile> output,
) {
  if (raw is! List) return;
  for (final value in raw) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final name = item['n']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final path = parent.isEmpty ? name : '$parent/$name';
    if (item['e'] is List) {
      _flattenFiles(item['e'], path, output);
      continue;
    }
    final link = item['l']?.toString().trim() ?? '';
    if (link.isEmpty) continue;
    output.add(
      AllDebridTorrentFile(name: path, size: _asInt(item['s']), link: link),
    );
  }
}

AllDebridException _apiError(Map<String, dynamic> error) => AllDebridException(
  error['message']?.toString() ?? 'AllDebrid request failed.',
  code: error['code']?.toString(),
);

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const AllDebridException('AllDebrid returned an invalid response.');
}

int _asInt(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text) ?? 0,
  _ => 0,
};
