import 'dart:async';
import 'dart:io';

import 'package:anime_tv/features/player/presentation/vlc_tv_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vendored VLC texture lifecycle is safe below Android API 26', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final source = File(
      'third_party/flutter_vlc_player/android/src/main/java/'
      'software/solid/fluttervlcplayer/VLCTextureView.java',
    ).readAsStringSync();
    final executableSource = source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//.*'), '');

    expect(
      pubspec,
      contains('path: third_party/flutter_vlc_player'),
      reason: 'The release build must consume the patched in-repo package.',
    );
    expect(source, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.O'));
    expect(source, contains('isSurfaceTextureReleased(mSurfaceTexture)'));
    expect(
      RegExp(r'\.isReleased\(\)').allMatches(executableSource),
      hasLength(1),
      reason: 'Only the SDK-gated helper may call the API 26 method.',
    );
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
