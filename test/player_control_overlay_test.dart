import 'package:anime_tv/features/player/presentation/player_control_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('track picker is bottom aligned and D-pad selectable', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  selected = await showPlayerTrackPicker<String>(
                    context: context,
                    title: 'Closed captions',
                    icon: Icons.closed_caption_rounded,
                    selectedValue: 'eng',
                    options: const [
                      PlayerTrackOption(value: 'off', label: 'Off'),
                      PlayerTrackOption(value: 'eng', label: 'English'),
                      PlayerTrackOption(value: 'jpn', label: 'Japanese'),
                    ],
                  );
                },
                child: const Text('Tracks'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tracks'));
    await tester.pumpAndSettle();

    final picker = find.byKey(const ValueKey('player-track-picker'));
    expect(picker, findsOneWidget);
    expect(tester.getBottomRight(picker).dy, greaterThan(500));
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 'jpn');
    expect(picker, findsNothing);
  });
}
