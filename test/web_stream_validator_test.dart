import 'package:anime_tv/features/marketplace/data/web_stream_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts common media MIME types and manifest signatures', () {
    expect(
      isPlayableWebResponse(
        Uri.parse('https://cdn.example/video'),
        'application/vnd.apple.mpegurl',
        '#EXTM3U',
      ),
      isTrue,
    );
    expect(
      isPlayableWebResponse(
        Uri.parse('https://cdn.example/manifest'),
        'text/plain',
        '<MPD type="static">',
      ),
      isTrue,
    );
    expect(
      isPlayableWebResponse(Uri.parse('https://cdn.example/video.mkv'), '', ''),
      isTrue,
    );
  });

  test('rejects HTML pages and strips transport-controlled headers', () {
    expect(
      isPlayableWebResponse(
        Uri.parse('https://cdn.example/watch'),
        'text/html',
        '<!doctype html>',
      ),
      isFalse,
    );
    final headers = sanitizeWebStreamHeaders({
      'Referer': 'https://provider.example/',
      'User-Agent': 'TetoTV test',
      'Host': 'attacker.example',
      'Connection': 'close',
      'X-Bad': 'one\r\ntwo',
    });
    expect(headers['Referer'], 'https://provider.example/');
    expect(headers['User-Agent'], 'TetoTV test');
    expect(headers, isNot(contains('Host')));
    expect(headers, isNot(contains('Connection')));
    expect(headers, isNot(contains('X-Bad')));
  });
}
