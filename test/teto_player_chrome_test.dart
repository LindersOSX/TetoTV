import 'package:anime_tv/features/player/presentation/teto_player_chrome.dart';
import 'package:flutter/material.dart';
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
            onAudio: () {},
            onSubtitles: () {},
            onPicture: () {},
            onFixVideo: () {},
            onSources: () {},
            onOptions: () {},
          ),
        ),
      ),
    );

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('CC'), findsOneWidget);
    expect(find.text('Picture'), findsOneWidget);
    expect(find.text('Fix video'), findsOneWidget);
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
            onAudio: () {},
            onSubtitles: () {},
            onPicture: () {},
            onFixVideo: () {},
            onSources: () {},
            onOptions: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
