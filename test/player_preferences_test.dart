import 'package:anime_tv/features/player/application/audio_track_selector.dart';
import 'package:anime_tv/features/player/presentation/player_control_overlay.dart';
import 'package:anime_tv/features/player/presentation/tv_player_screen.dart';
import 'package:anime_tv/features/player/presentation/vlc_tv_player_screen.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('opens marketplace web streams with the defensive MPV path', () {
    final web = StreamReady(
      uri: Uri.parse('https://cdn.example.test/episode.m3u8'),
      displayName: 'Marketplace stream',
      providerId: 'fixture',
    );
    final debrid = StreamReady(
      uri: Uri.parse('https://cdn.example.test/episode.mkv'),
      displayName: 'Debrid stream',
      debridService: DebridService.realDebrid,
    );

    expect(preferMpvForInitialStream(web), isTrue);
    expect(preferMpvForInitialStream(debrid), isFalse);
  });

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

  test(
    'uses media_kit safe decoder selection for Android TV compatibility',
    () {
      expect(
        tetoTvVideoControllerConfiguration.enableHardwareAcceleration,
        isTrue,
      );
      expect(tetoTvVideoControllerConfiguration.vo, 'gpu');
      expect(tetoTvVideoControllerConfiguration.hwdec, 'auto-safe');
      expect(
        tetoTvVideoControllerConfiguration
            .androidAttachSurfaceAfterVideoParameters,
        isTrue,
      );
    },
  );

  test('recognizes video failures that should trigger software decoding', () {
    expect(isLikelyVideoDecodeFailure('MediaCodec failed to initialize'), true);
    expect(isLikelyVideoDecodeFailure('No video output available'), true);
    expect(isLikelyVideoDecodeFailure('HTTP 403 forbidden'), false);
  });

  test('offers safe hardware, direct hardware, and software decoders', () {
    expect(hwdecForPlaybackMode(PlaybackDecoderMode.hardwareSafe), 'auto-safe');
    expect(
      hwdecForPlaybackMode(PlaybackDecoderMode.hardwareDirect),
      'mediacodec',
    );
    expect(hwdecForPlaybackMode(PlaybackDecoderMode.software), 'no');
  });

  test('forces software decoding for H.264 Hi10P anime releases', () {
    const hi10 = ReleaseCandidate(
      infoHash: '0123456789012345678901234567890123456789',
      magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
      releaseName: '[Group] Show - 01 [1080p Hi10P x264].mkv',
      seeders: 1,
      sourceId: 'test',
      codec: 'H.264',
    );
    const ordinary = ReleaseCandidate(
      infoHash: '0123456789012345678901234567890123456789',
      magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
      releaseName: '[Group] Show - 01 [1080p x264].mkv',
      seeders: 1,
      sourceId: 'test',
      codec: 'H.264',
    );

    expect(releaseRequiresSoftwareDecoder(hi10), isTrue);
    expect(releaseRequiresSoftwareDecoder(ordinary), isFalse);
  });

  test('detects unlabeled 10-bit H.264 from decoded stream metadata', () {
    expect(
      isH264TenBitVideoProfile(
        codec: 'h264',
        profile: 'High 10',
        format: 'yuv420p10le',
        pixelFormat: 'mediacodec',
      ),
      isTrue,
    );
    expect(
      isH264TenBitVideoProfile(
        codec: 'h264',
        profile: 'High',
        format: 'yuv420p',
      ),
      isFalse,
    );
    expect(
      isH264TenBitVideoProfile(
        codec: 'hevc',
        profile: 'Main 10',
        format: 'yuv420p10le',
      ),
      isFalse,
    );
  });

  test('retries a resume seek only when playback remained near the start', () {
    const target = Duration(minutes: 12, seconds: 30);
    expect(resumeSeekNeedsRetry(target, Duration.zero), isTrue);
    expect(
      resumeSeekNeedsRetry(target, const Duration(minutes: 12, seconds: 28)),
      isFalse,
    );
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

  test('seek target remains usable before stream duration is known', () {
    expect(
      playerSeekTarget(
        position: const Duration(minutes: 3),
        offset: const Duration(seconds: 10),
        duration: Duration.zero,
      ),
      const Duration(minutes: 3, seconds: 10),
    );
    expect(
      playerSeekTarget(
        position: const Duration(seconds: 4),
        offset: const Duration(seconds: -10),
        duration: const Duration(minutes: 24),
      ),
      Duration.zero,
    );
    expect(
      playerSeekTarget(
        position: const Duration(minutes: 23, seconds: 58),
        offset: const Duration(seconds: 10),
        duration: const Duration(minutes: 24),
      ),
      const Duration(minutes: 24),
    );
  });

  test('subtitle defaults follow the selected release language', () {
    const sub = ReleaseCandidate(
      infoHash: 'sub',
      magnetUri: 'magnet:?xt=urn:btih:sub',
      releaseName: 'Show 01 English Subbed',
      seeders: 1,
      sourceId: 'test',
      hasSubtitles: true,
    );
    const dub = ReleaseCandidate(
      infoHash: 'dub',
      magnetUri: 'magnet:?xt=urn:btih:dub',
      releaseName: 'Show 01 English Dub',
      seeders: 1,
      sourceId: 'test',
      isDubbed: true,
      hasSubtitles: true,
    );

    expect(subtitlesEnabledByDefault(sub), isTrue);
    expect(subtitlesEnabledByDefault(dub), isFalse);
  });

  test('VLC compatibility mode is independent from its software fallback', () {
    expect(
      vlcHwAccForMode(VlcDecoderMode.hardwareCopy),
      isNot(vlcHwAccForMode(VlcDecoderMode.software)),
    );
    expect(
      vlcDecoderLabel(VlcDecoderMode.hardwareCopy),
      contains('recommended'),
    );
  });

  test('VLC track selection prioritizes English dub and avoids commentary', () {
    final selected = preferredVlcTrack(
      const {
        1: 'Japanese Stereo',
        2: 'English Commentary',
        3: 'English Dub 5.1',
      },
      language: 'eng',
      preferDub: true,
    );
    expect(selected, 3);
    expect(
      preferredVlcTrack(
        const {1: 'Japanese Stereo'},
        language: 'eng',
        preferDub: true,
      ),
      isNull,
    );
  });

  test('English track matching accepts common ISO aliases', () {
    for (final language in const ['en', 'eng', 'en-US', 'en_GB', 'English']) {
      expect(
        playerTrackMatchesLanguage(
          language: language,
          preferredLanguage: 'eng',
        ),
        isTrue,
        reason: language,
      );
    }
    expect(preferredVlcTrack(const {1: 'ja', 2: 'en'}, language: 'eng'), 2);
  });

  test('double Down requires two distinct presses inside the window', () {
    final detector = PlayerDoubleDownDetector();
    final start = DateTime(2026);

    expect(detector.register(LogicalKeyboardKey.arrowDown, at: start), isFalse);
    expect(
      detector.register(
        LogicalKeyboardKey.arrowDown,
        at: start.add(const Duration(milliseconds: 440)),
      ),
      isTrue,
    );
    expect(playerControlsIdleTimeout, const Duration(seconds: 10));
  });

  test('another key or a late Down resets double-Down detection', () {
    final detector = PlayerDoubleDownDetector();
    final start = DateTime(2026);

    detector.register(LogicalKeyboardKey.arrowDown, at: start);
    detector.register(
      LogicalKeyboardKey.arrowRight,
      at: start.add(const Duration(milliseconds: 100)),
    );
    expect(
      detector.register(
        LogicalKeyboardKey.arrowDown,
        at: start.add(const Duration(milliseconds: 200)),
      ),
      isFalse,
    );
    expect(
      detector.register(
        LogicalKeyboardKey.arrowDown,
        at: start.add(const Duration(milliseconds: 800)),
      ),
      isFalse,
    );
  });
}
