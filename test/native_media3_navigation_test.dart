import 'package:anime_tv/features/player/presentation/native_media3_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('native player return navigation', () {
    test('Exit video always returns to the home route', () {
      expect(
        nativePlayerReturnNavigationForStatus('stopped'),
        NativePlayerReturnNavigation.home,
      );
      expect(
        nativePlayerReturnNavigationForStatus('exit'),
        NativePlayerReturnNavigation.home,
      );
    });

    test('a cancelled native activity returns to the previous route', () {
      expect(
        nativePlayerReturnNavigationForStatus('cancelled'),
        NativePlayerReturnNavigation.previousRoute,
      );
    });

    test('playback statuses do not produce a return or relaunch decision', () {
      for (final status in const [
        'retry',
        'next_stream',
        'use_mpv',
        'use_vlc',
        'completed',
        'error',
        'release_failed',
        'unknown',
      ]) {
        expect(
          nativePlayerReturnNavigationForStatus(status),
          NativePlayerReturnNavigation.none,
          reason: status,
        );
      }
    });

    test('Exit bookkeeping continues after an operation fails', () async {
      final attempted = <String>[];

      await runBestEffortNativePlayerExitBookkeeping([
        () async {
          attempted.add('checkpoint');
          throw StateError('database unavailable');
        },
        () async => attempted.add('tracking'),
        () async {
          attempted.add('player-success');
          throw StateError('profile unavailable');
        },
      ]);

      expect(attempted, ['checkpoint', 'tracking', 'player-success']);
    });
  });
}
