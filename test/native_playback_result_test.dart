import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses native Media3 playback diagnostics', () {
    final result = NativePlaybackResult.fromMap(<Object?, Object?>{
      'status': 'no_first_frame',
      'positionMs': 12_345,
      'durationMs': 1_500_000,
      'completed': false,
      'firstFrameRendered': false,
      'droppedFrames': 18,
      'decoder': 'c2.mtk.hevc.decoder',
      'error': 'No video frame reached the SurfaceView',
      'videoMime': 'video/hevc',
      'model': 'AFTKRT',
    });

    expect(result.failed, isTrue);
    expect(result.position, const Duration(milliseconds: 12_345));
    expect(result.duration, const Duration(milliseconds: 1_500_000));
    expect(result.droppedFrames, 18);
    expect(result.decoder, 'c2.mtk.hevc.decoder');
    expect(result.diagnostics['videoMime'], 'video/hevc');
    expect(result.diagnostics['model'], 'AFTKRT');
  });

  test('native player exit is not treated as a decoder failure', () {
    final result = NativePlaybackResult.fromMap(<Object?, Object?>{
      'status': 'exit',
      'positionMs': 42_000,
      'durationMs': 100_000,
      'firstFrameRendered': true,
    });

    expect(result.failed, isFalse);
    expect(result.firstFrameRendered, isTrue);
  });
}
