import 'dart:async';
import 'dart:io';

import 'package:anime_tv/features/player/presentation/vlc_tv_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vendored VLC has one registry-owned texture release path', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final textureSource = File(
      'third_party/flutter_vlc_player/android/src/main/java/'
      'software/solid/fluttervlcplayer/VLCTextureView.java',
    ).readAsStringSync();
    final playerSource = File(
      'third_party/flutter_vlc_player/android/src/main/java/'
      'software/solid/fluttervlcplayer/FlutterVlcPlayer.java',
    ).readAsStringSync();
    final executableTextureSource = textureSource
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//.*'), '');
    final disposeStart = playerSource.indexOf('public void dispose()');
    final disposeEnd = playerSource.indexOf('// VLC Player', disposeStart);
    final disposeSource = playerSource.substring(disposeStart, disposeEnd);

    expect(
      pubspec,
      contains('path: third_party/flutter_vlc_player'),
      reason: 'The release build must consume the patched in-repo package.',
    );
    expect(
      RegExp(r'\.release\(\)').allMatches(executableTextureSource),
      isEmpty,
      reason: 'The view must not release Flutter\'s registry-owned texture.',
    );
    expect(
      RegExp(r'textureEntry::release').allMatches(playerSource),
      hasLength(1),
    );
    expect(
      disposeSource.indexOf('textureView.setMediaPlayer(null)'),
      lessThan(disposeSource.indexOf('currentPlayer::release')),
    );
    expect(
      disposeSource.indexOf('currentPlayer::release'),
      lessThan(disposeSource.indexOf('textureEntry::release')),
      reason:
          'libVLC must release native vout before Flutter destroys texture.',
    );
    expect(disposeSource, contains('if (isDisposed || isDisposing)'));
    expect(disposeSource, contains('try {'));
    expect(disposeSource, contains('} finally {'));
    expect(
      disposeSource.indexOf('currentLibVLC::release'),
      lessThan(disposeSource.indexOf('isDisposed = true')),
    );
    for (final cleanup in [
      'stop VLC MediaPlayer',
      'detach VLC video output',
      'release VLC MediaPlayer',
      'dispose VLC TextureView',
      'release Flutter texture entry',
      'release LibVLC',
    ]) {
      expect(disposeSource, contains('runCleanupStep("$cleanup"'));
    }
    expect(playerSource, contains('catch (RuntimeException error)'));
  });

  test('live VLC handoffs avoid immediately reclaiming MediaCodec', () {
    expect(
      initialVlcDecoderMode(
        inheritedPosition: Duration.zero,
        releaseName: 'Ordinary H.264 release',
      ),
      VlcDecoderMode.software,
    );
    expect(
      initialVlcDecoderMode(
        inheritedPosition: null,
        releaseName: 'Ordinary H.264 release',
      ),
      VlcDecoderMode.hardwareCopy,
    );
    expect(
      initialVlcDecoderMode(
        inheritedPosition: null,
        releaseName: 'Anime Hi10P release',
      ),
      VlcDecoderMode.software,
    );
  });

  test(
    'a wedged VLC platform operation cannot block release forever',
    () async {
      final stuck = Completer<void>();
      final operations = <Future<void>>{stuck.future};

      final drained = await waitForVlcOperationsToDrain(
        snapshot: () => operations,
        timeout: const Duration(milliseconds: 20),
      );

      expect(drained, isFalse);
      stuck.complete();
    },
  );

  test(
    'the VLC release drain includes work queued by an earlier operation',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final operations = <Future<void>>{first.future};
      final drain = waitForVlcOperationsToDrain(
        snapshot: () => operations,
        timeout: const Duration(seconds: 1),
      );

      operations.add(second.future);
      operations.remove(first.future);
      first.complete();
      var finished = false;
      unawaited(drain.then((_) => finished = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(finished, isFalse);

      operations.remove(second.future);
      second.complete();
      expect(await drain, isTrue);
    },
  );
}
