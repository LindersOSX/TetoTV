import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/player/presentation/native_media3_player_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Media3 completion advances for hosts but waits for attached guests',
    () {
      expect(
        nativePlayerMayAdvanceAfterCompletion(guestControlsLocked: false),
        isTrue,
      );
      expect(
        nativePlayerMayAdvanceAfterCompletion(guestControlsLocked: true),
        isFalse,
      );
    },
  );

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

  test('Watch Party native transition never performs ordinary route exit', () {
    expect(
      nativePlayerReturnNavigationForStatus('watch_party_transition'),
      NativePlayerReturnNavigation.none,
    );
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

  test('native Watch Together HUD contract exposes no playback capability', () {
    final request = NativeWatchPartyHudRequest.fromMap(<Object?, Object?>{
      'checkpointKey': '15125:9',
      'playbackSessionGeneration': 4,
    });
    const response = NativeWatchPartyHudResponse(
      ok: true,
      roomCode: '23456789',
      watchUrl: 'https://tetotv-bot.wisp.uno/watch?room=23456789',
      status: 'PARTY 23456789 • HOST • 1 watching',
      message: 'Share this code.',
      participants: [
        NativeWatchPartyHudParticipant(
          displayName: 'Teto Fan',
          avatarUrl:
              'https://s4.anilist.co/file/anilistcdn/user/avatar/large/x.jpg',
          role: 'host',
          ready: true,
        ),
      ],
    );

    expect(request.isValid, isTrue);
    expect(
      NativeWatchPartyHudRequest.fromMap(const {
        'checkpointKey': '',
        'playbackSessionGeneration': 0,
      }).isValid,
      isFalse,
    );
    expect(response.toMap().keys, {
      'ok',
      'message',
      'roomCode',
      'watchUrl',
      'status',
      'participants',
    });
    expect(response.toMap().keys, isNot(contains('token')));
    expect(response.toMap().keys, isNot(contains('source')));
    expect(response.toMap().keys, isNot(contains('headers')));
    final participant =
        ((response.toMap()['participants'] as List).single as Map)
            .cast<String, Object>();
    expect(participant.keys, {'display_name', 'avatar_url', 'role', 'ready'});
    expect(participant.keys, isNot(contains('token')));
    expect(participant.keys, isNot(contains('account_id')));
  });

  test(
    'native guest lock updates are generation scoped and capability free',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('dev.tetotv/android_tv');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final applied = await AndroidTvBridge.instance
          .updateNativePlayerWatchPartyState(
            checkpointKey: '15125:9',
            playbackSessionGeneration: 4,
            guestControlsLocked: true,
            stateSequence: 7,
            status: 'PARTY 23456789 • SYNCED',
          );

      expect(applied, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'updateNativePlayerWatchPartyState');
      final arguments = (calls.single.arguments as Map).cast<String, Object>();
      expect(arguments.keys, {
        'checkpointKey',
        'playbackSessionGeneration',
        'guestControlsLocked',
        'stateSequence',
        'status',
      });
      expect(arguments['guestControlsLocked'], isTrue);
      expect(arguments.keys, isNot(contains('source')));
      expect(arguments.keys, isNot(contains('headers')));
      expect(arguments.keys, isNot(contains('token')));

      expect(
        await AndroidTvBridge.instance.updateNativePlayerWatchPartyState(
          checkpointKey: '',
          playbackSessionGeneration: 4,
          guestControlsLocked: false,
          stateSequence: 8,
        ),
        isFalse,
      );
      expect(calls, hasLength(1));
    },
  );

  test(
    'native media transition dismissal is exact-session and data free',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('dev.tetotv/android_tv');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      expect(
        await AndroidTvBridge.instance
            .dismissNativePlayerForWatchPartyTransition(
              checkpointKey: '15125:9',
              playbackSessionGeneration: 4,
            ),
        isTrue,
      );
      expect(calls.single.method, 'dismissNativePlayerForWatchPartyTransition');
      final arguments = (calls.single.arguments as Map).cast<String, Object>();
      expect(arguments, {
        'checkpointKey': '15125:9',
        'playbackSessionGeneration': 4,
      });
      expect(arguments.keys, isNot(contains('token')));
      expect(arguments.keys, isNot(contains('source')));
      expect(arguments.keys, isNot(contains('headers')));

      expect(
        await AndroidTvBridge.instance
            .dismissNativePlayerForWatchPartyTransition(
              checkpointKey: '',
              playbackSessionGeneration: 4,
            ),
        isFalse,
      );
      expect(calls, hasLength(1));
    },
  );

  test('native launch carries the initial attached-guest authority', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('dev.tetotv/android_tv');
    MethodCall? recorded;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recorded = call;
          return <String, Object>{
            'status': 'stopped',
            'positionMs': 0,
            'durationMs': 0,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await AndroidTvBridge.instance.startNativePlayer(
      source: Uri.parse('https://media.example/episode.m3u8'),
      title: 'Frieren',
      checkpointKey: '154587:2',
      releaseName: 'Episode 2',
      streamLabel: 'Web stream',
      resumePosition: Duration.zero,
      startFromBeginning: false,
      playbackSessionGeneration: 8,
      watchPartyStatus: 'PARTY 23456789 • SYNCED',
      watchPartyGuestControlsLocked: true,
      watchPartyStateSequence: 3,
    );

    expect(recorded?.method, 'startNativePlayer');
    final arguments = (recorded?.arguments as Map).cast<String, Object>();
    expect(arguments['checkpointKey'], '154587:2');
    expect(arguments['playbackSessionGeneration'], 8);
    expect(arguments['watchPartyGuestControlsLocked'], isTrue);
    expect(arguments['watchPartyStateSequence'], 3);
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
