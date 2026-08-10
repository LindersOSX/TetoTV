import 'dart:convert';
import 'dart:io';

import 'package:anime_tv/features/marketplace/domain/addon_models.dart';

class ValidatedWebStream {
  const ValidatedWebStream({
    required this.uri,
    required this.headers,
    required this.contentType,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String contentType;
}

typedef WebStreamPreflight =
    Future<ValidatedWebStream> Function(Uri uri, Map<String, String> headers);

class WebStreamValidator {
  const WebStreamValidator();

  Future<ValidatedWebStream> validate(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final sanitized = sanitizeWebStreamHeaders(headers);
    var target = uri;
    for (var redirect = 0; redirect <= 4; redirect++) {
      await validatePublicNetworkTarget(target);
      final client = createPinnedPublicHttpsClient()
        ..connectionTimeout = const Duration(seconds: 7)
        ..idleTimeout = const Duration(seconds: 8);
      try {
        final request = await client.getUrl(target);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-2047');
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        sanitized.forEach(request.headers.set);
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirect == 4) {
            throw const FormatException(
              'The provider returned too many redirects.',
            );
          }
          target = target.resolve(location);
          continue;
        }
        if (response.statusCode == HttpStatus.unauthorized ||
            response.statusCode == HttpStatus.forbidden) {
          throw FormatException(
            'The provider denied access (HTTP ${response.statusCode}).',
          );
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw FormatException(
            'The provider returned HTTP ${response.statusCode}.',
          );
        }
        final bytes = await response
            .take(1)
            .fold<List<int>>(
              <int>[],
              (all, chunk) => all..addAll(chunk.take(2048)),
            );
        final contentType =
            response.headers.contentType?.mimeType.toLowerCase() ?? '';
        final sample = utf8.decode(bytes, allowMalformed: true).trimLeft();
        if (!isPlayableWebResponse(target, contentType, sample)) {
          throw FormatException(
            contentType.contains('html')
                ? 'The provider returned a web page instead of video.'
                : 'The provider response is not a supported video stream ($contentType).',
          );
        }
        return ValidatedWebStream(
          uri: target,
          headers: sanitized,
          contentType: contentType,
        );
      } finally {
        client.close(force: true);
      }
    }
    throw const FormatException('The provider stream could not be verified.');
  }
}

Map<String, String> sanitizeWebStreamHeaders(Map<String, String> headers) {
  const blocked = {
    'host',
    'connection',
    'content-length',
    'transfer-encoding',
    'proxy-authorization',
  };
  return {
    for (final entry in headers.entries)
      if (!blocked.contains(entry.key.trim().toLowerCase()) &&
          entry.key.trim().isNotEmpty &&
          !entry.value.contains(RegExp(r'[\r\n]')))
        entry.key.trim(): entry.value.trim(),
  };
}

bool isPlayableWebResponse(Uri uri, String contentType, String sample) {
  final mime = contentType.toLowerCase().split(';').first.trim();
  if (mime == 'text/html' ||
      sample.toLowerCase().startsWith('<!doctype html')) {
    return false;
  }
  if (mime.startsWith('video/') ||
      const {
        'application/vnd.apple.mpegurl',
        'application/x-mpegurl',
        'application/dash+xml',
        'application/octet-stream',
      }.contains(mime)) {
    return true;
  }
  if (sample.startsWith('#EXTM3U') || sample.toLowerCase().contains('<mpd')) {
    return true;
  }
  final path = uri.path.toLowerCase();
  return const [
    '.m3u8',
    '.mpd',
    '.mp4',
    '.mkv',
    '.webm',
    '.m4v',
    '.ts',
  ].any(path.endsWith);
}
