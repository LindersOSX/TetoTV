import 'package:anime_tv/features/player/application/audio_track_selector.dart';
import 'package:anime_tv/features/player/presentation/tv_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('prefers English dub audio over Japanese default audio', () {
    const tracks = [
      AudioTrack('1', 'Japanese', 'jpn', isDefault: true),
      AudioTrack('2', 'English Dub', 'eng'),
      AudioTrack('3', 'English Commentary', 'eng'),
    ];

    expect(preferredDubAudioTrack(tracks)?.id, '2');
  });

  test('leaves automatic audio unchanged when no dub exists', () {
    const tracks = [
      AudioTrack('1', 'Japanese', 'jpn', isDefault: true),
      AudioTrack('2', 'Japanese 5.1', 'jpn'),
    ];

    expect(preferredDubAudioTrack(tracks), isNull);
  });

  test('uses copy-back MediaCodec rendering for Android TV compatibility', () {
    expect(
      tetoTvVideoControllerConfiguration.enableHardwareAcceleration,
      isTrue,
    );
    expect(tetoTvVideoControllerConfiguration.vo, 'gpu');
    expect(tetoTvVideoControllerConfiguration.hwdec, 'mediacodec-copy');
    expect(
      tetoTvVideoControllerConfiguration
          .androidAttachSurfaceAfterVideoParameters,
      isTrue,
    );
  });

  test('recognizes video failures that should trigger software decoding', () {
    expect(isLikelyVideoDecodeFailure('MediaCodec failed to initialize'), true);
    expect(isLikelyVideoDecodeFailure('No video output available'), true);
    expect(isLikelyVideoDecodeFailure('HTTP 403 forbidden'), false);
  });

  test('offers safe hardware, direct hardware, and software decoders', () {
    expect(
      hwdecForPlaybackMode(PlaybackDecoderMode.hardwareSafe),
      'mediacodec-copy',
    );
    expect(
      hwdecForPlaybackMode(PlaybackDecoderMode.hardwareDirect),
      'mediacodec',
    );
    expect(hwdecForPlaybackMode(PlaybackDecoderMode.software), 'no');
  });

  test('D-pad arrows navigate controls instead of seeking playback', () {
    expect(playerSeekOffsetForKey(LogicalKeyboardKey.arrowLeft), isNull);
    expect(playerSeekOffsetForKey(LogicalKeyboardKey.arrowRight), isNull);
    expect(
      playerSeekOffsetForKey(LogicalKeyboardKey.mediaRewind),
      const Duration(seconds: -10),
    );
    expect(
      playerSeekOffsetForKey(LogicalKeyboardKey.mediaFastForward),
      const Duration(seconds: 10),
    );
  });
}
