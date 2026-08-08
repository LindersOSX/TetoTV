import 'package:anime_tv/features/streaming/data/torbox_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('createTorrent rejects a malformed torrent ID', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://torbox.test'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'success': true,
                  'data': {'torrent_id': 'not-a-number'},
                },
              ),
            );
          },
        ),
      );
    final client = TorBoxClient(token: 'test-token', dio: dio);

    await expectLater(
      client.createTorrent('magnet:?xt=urn:btih:test'),
      throwsA(
        isA<TorBoxException>().having(
          (error) => error.message,
          'message',
          contains('invalid torrent ID'),
        ),
      ),
    );
  });
}
