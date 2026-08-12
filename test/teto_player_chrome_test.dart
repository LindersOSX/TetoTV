import 'package:anime_tv/features/player/presentation/teto_player_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shared player chrome keeps every feature control available', (
    tester,
  ) async {
    final playFocus = FocusNode();
    addTearDown(playFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: TetoPlayerChrome(
            engineKey: 'test',
            title: 'A test anime • Episode 3',
            streamLabel: 'Web stream',
            engineLabel: 'MPV',
            position: const Duration(minutes: 3),
            duration: const Duration(minutes: 24),
            isPlaying: true,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 30,
            onRewind: () {},
            onPlayPause: () {},
            onForward: () {},
            onSeek: (_) {},
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onSources: () {},
            onOptions: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('CC'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Picture'), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Options'), findsOneWidget);
    expect(find.text('03:00  /  24:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skip segment is a separate translucent overlay', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TetoSkipSegmentOverlay(
              label: 'Skip Intro',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('player-skip-segment-overlay')),
      findsOneWidget,
    );
    expect(find.text('Skip Intro'), findsOneWidget);
  });

  testWidgets('shared chrome remains usable at narrow phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playFocus = FocusNode();
    addTearDown(playFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TetoPlayerChrome(
            engineKey: 'phone',
            title: 'A very long anime episode title that must not overflow',
            streamLabel: 'A very long marketplace provider name',
            position: const Duration(minutes: 1),
            duration: const Duration(minutes: 24),
            isPlaying: false,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 10,
            onRewind: () {},
            onPlayPause: () {},
            onForward: () {},
            onSeek: (_) {},
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onSources: () {},
            onOptions: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('D-pad Down dismisses the visible player HUD immediately', (
    tester,
  ) async {
    final playFocus = FocusNode();
    addTearDown(playFocus.dispose);
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TetoPlayerChrome(
            engineKey: 'dismiss',
            title: 'Episode',
            streamLabel: 'Web stream',
            position: Duration.zero,
            duration: const Duration(minutes: 24),
            isPlaying: true,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 10,
            onRewind: () {},
            onPlayPause: () {},
            onForward: () {},
            onSeek: (_) {},
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onOptions: () {},
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    playFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

    expect(dismissed, isTrue);
  });

  testWidgets('D-pad scrub previews, commits, and cancels without seeking', (
    tester,
  ) async {
    final playFocus = FocusNode();
    final scrubController = PlayerScrubController();
    addTearDown(playFocus.dispose);
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TetoPlayerChrome(
            engineKey: 'scrub',
            title: 'Episode',
            streamLabel: 'Stream',
            position: const Duration(minutes: 3),
            duration: const Duration(minutes: 24),
            isPlaying: true,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 10,
            onRewind: () {},
            onPlayPause: () {},
            onForward: () {},
            onSeek: seeks.add,
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onOptions: () {},
            onDismiss: () {},
            scrubController: scrubController,
          ),
        ),
      ),
    );
    playFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(scrubController.isActive, isTrue);
    expect(find.text('Select to seek  |  Back to cancel'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('03:30  /  24:00'), findsOneWidget);
    expect(seeks, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(seeks, [const Duration(minutes: 3, seconds: 30)]);
    expect(scrubController.isActive, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(scrubController.isActive, isFalse);
  });

  testWidgets('touch drag previews progress and commits once on release', (
    tester,
  ) async {
    final playFocus = FocusNode();
    addTearDown(playFocus.dispose);
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TetoPlayerChrome(
            engineKey: 'touch-scrub',
            title: 'Episode',
            streamLabel: 'Stream',
            position: const Duration(minutes: 3),
            duration: const Duration(minutes: 24),
            isPlaying: true,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 10,
            onRewind: () {},
            onPlayPause: () {},
            onForward: () {},
            onSeek: seeks.add,
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onOptions: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    final progress = find.byKey(const ValueKey('player-progress-scrubber'));
    final rect = tester.getRect(progress);
    final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * .25, rect.center.dy),
    );
    await gesture.moveTo(Offset(rect.left + rect.width * .75, rect.center.dy));
    await tester.pump();
    expect(find.text('18:00  /  24:00'), findsOneWidget);
    expect(seeks, isEmpty);

    await gesture.up();
    await tester.pump();
    expect(seeks, [const Duration(minutes: 18)]);
  });
}
