import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('D-pad hold invokes the secondary TV action only', (
    tester,
  ) async {
    var primaryCalls = 0;
    var secondaryCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            autofocus: true,
            onPressed: () => primaryCalls++,
            onLongPress: () => secondaryCalls++,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(primaryCalls, 0);
    expect(secondaryCalls, 1);
  });

  testWidgets('short D-pad select keeps the primary TV action', (tester) async {
    var primaryCalls = 0;
    var secondaryCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            autofocus: true,
            onPressed: () => primaryCalls++,
            onLongPress: () => secondaryCalls++,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(primaryCalls, 1);
    expect(secondaryCalls, 0);
  });

  testWidgets('D-pad scrolls a virtualized list when focus reaches its edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TvShortcuts(
          child: Scaffold(
            body: SizedBox(
              height: 180,
              child: ListView.builder(
                itemExtent: 90,
                itemCount: 30,
                itemBuilder: (context, index) => TvFocusable(
                  autofocus: index == 0,
                  onPressed: () {},
                  child: Text('Item $index'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 8; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
