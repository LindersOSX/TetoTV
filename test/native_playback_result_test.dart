import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/player/presentation/native_media3_player_screen.dart';
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
      'audioLanguage': 'jpn',
      'audioPreferenceSet': true,
      'subtitleLanguage': 'eng',
      'subtitlesEnabled': true,
      'subtitleSize': 42.0,
      'subtitleBackgroundColor': 0xCC000000,
      'highContrastSubtitles': true,
    });

    expect(result.failed, isTrue);
    expect(result.position, const Duration(milliseconds: 12_345));
    expect(result.duration, const Duration(milliseconds: 1_500_000));
    expect(result.droppedFrames, 18);
    expect(result.decoder, 'c2.mtk.hevc.decoder');
    expect(result.diagnostics['videoMime'], 'video/hevc');
    expect(result.diagnostics['model'], 'AFTKRT');
    expect(result.audioLanguage, 'jpn');
    expect(result.audioPreferenceSet, isTrue);
    expect(result.subtitleLanguage, 'eng');
    expect(result.subtitlesEnabled, isTrue);
    expect(result.subtitleSize, 42);
    expect(result.subtitleBackgroundColor, 0xCC000000);
    expect(result.highContrastSubtitles, isTrue);
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

  test('normalizes signed Android caption colors to unsigned ARGB', () {
    final result = NativePlaybackResult.fromMap(<Object?, Object?>{
      'status': 'stopped',
      'subtitleBackgroundColor': -1728053248,
    });

    expect(result.subtitleBackgroundColor, 0x99000000);
  });

  test(
    'unsupported-caption MPV handoff preserves intent without breaking manual off',
    () {
      final fallback = NativePlaybackResult.fromMap(<Object?, Object?>{
        'status': 'use_mpv',
        'subtitlesEnabled': true,
        'error':
            'Media3 cannot render this torrent embedded caption format; '
            'continuing in MPV for libass caption support.',
      });
      final enabled = applyNativeSubtitlePreferenceResult(
        currentPreferences: const SeriesPlaybackPreferences(
          subtitleEnabled: false,
          subtitlePreferenceSet: true,
        ),
        result: fallback,
      );

      expect(enabled.subtitleEnabled, isTrue);
      expect(enabled.subtitlePreferenceSet, isTrue);

      final manualOff = applyNativeSubtitlePreferenceResult(
        currentPreferences: enabled,
        result: NativePlaybackResult.fromMap(const <Object?, Object?>{
          'status': 'exit',
          'subtitlesEnabled': false,
        }),
      );
      expect(manualOff.subtitleEnabled, isFalse);
      expect(manualOff.subtitlePreferenceSet, isTrue);
    },
  );

  test(
    'an unchanged native subtitle observation preserves existing intent',
    () {
      final result = NativePlaybackResult.fromMap(const <Object?, Object?>{
        'status': 'use_mpv',
        'subtitleLanguage': 'eng',
      });
      expect(result.subtitlesEnabled, isNull);

      const existing = SeriesPlaybackPreferences(
        subtitleEnabled: true,
        subtitlePreferenceSet: true,
      );
      final preserved = applyNativeSubtitlePreferenceResult(
        currentPreferences: existing,
        result: result,
      );

      expect(preserved.subtitleEnabled, isTrue);
      expect(preserved.subtitlePreferenceSet, isTrue);
    },
  );

  test('parses session-scoped native playback progress', () {
    final progress = NativePlaybackProgress.fromMap(<Object?, Object?>{
      'checkpointKey': '15125:9',
      'positionMs': 930_500,
      'durationMs': 1_440_000,
      'isPlaying': true,
      'audioLanguage': 'eng',
      'audioPreferenceSet': true,
    });

    expect(progress.checkpointKey, '15125:9');
    expect(progress.position, const Duration(milliseconds: 930_500));
    expect(progress.duration, const Duration(minutes: 24));
    expect(progress.isPlaying, isTrue);
    expect(progress.audioLanguage, 'eng');
    expect(progress.audioPreferenceSet, isTrue);
  });

  test('missing native progress values remain safely inert', () {
    final progress = NativePlaybackProgress.fromMap(const {});

    expect(progress.checkpointKey, isEmpty);
    expect(progress.position, Duration.zero);
    expect(progress.duration, Duration.zero);
    expect(progress.isPlaying, isFalse);
    expect(progress.audioLanguage, isNull);
    expect(progress.audioPreferenceSet, isFalse);
  });

  test('explicit native audio saves then replaces stale preparation', () async {
    final calls = <String>[];
    SeriesPlaybackPreferences? committed;
    final changed = await applyNativeAudioPreferenceSelection(
      progress: const NativePlaybackProgress(
        checkpointKey: '15125:9',
        position: Duration(minutes: 15),
        duration: Duration(minutes: 24),
        isPlaying: true,
        audioLanguage: 'en-US',
        audioPreferenceSet: true,
      ),
      currentPreferences: const SeriesPlaybackPreferences(
        audioLanguage: 'jpn',
        audioPreferenceSet: true,
      ),
      save: (next) async {
        calls.add('save:${next.audioLanguage}');
      },
      commit: (next) {
        committed = next;
        calls.add('commit:${next.audioLanguage}');
      },
      abandonStalePreparation: () async => calls.add('abandon'),
      invalidatePreparation: () => calls.add('invalidate'),
    );

    expect(changed, isTrue);
    expect(committed?.audioLanguage, 'eng');
    expect(committed?.audioPreferenceSet, isTrue);
    expect(calls, ['save:eng', 'commit:eng', 'abandon', 'invalidate']);
  });

  test('duplicate or automatic native audio observations are inert', () async {
    final calls = <String>[];
    const current = SeriesPlaybackPreferences(
      audioLanguage: 'eng',
      audioPreferenceSet: true,
    );

    for (final explicit in [true, false]) {
      final changed = await applyNativeAudioPreferenceSelection(
        progress: NativePlaybackProgress(
          checkpointKey: '15125:9',
          position: const Duration(minutes: 15),
          duration: const Duration(minutes: 24),
          isPlaying: true,
          audioLanguage: explicit ? 'English Dub' : 'jpn',
          audioPreferenceSet: explicit,
        ),
        currentPreferences: current,
        save: (_) async => calls.add('save'),
        commit: (_) => calls.add('commit'),
        abandonStalePreparation: () async => calls.add('abandon'),
        invalidatePreparation: () => calls.add('invalidate'),
      );
      expect(changed, isFalse);
    }
    expect(calls, isEmpty);
  });
}
