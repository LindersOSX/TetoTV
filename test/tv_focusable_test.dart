import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/interaction_sound_scope.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('focus ring stays high contrast over red or pale controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            autofocus: true,
            onPressed: () {},
            child: const ColoredBox(
              color: Color(0xFFE52B50),
              child: SizedBox(width: 100, height: 60),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final animated = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = animated.decoration! as BoxDecoration;
    expect(decoration.border!.top.color, Colors.white);
    expect(decoration.boxShadow, hasLength(2));
  });

  testWidgets('TV activation plays the platform click sound', (tester) async {
    final platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            autofocus: true,
            onPressed: () {},
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(
      platformCalls,
      contains(
        isA<MethodCall>()
            .having((call) => call.method, 'method', 'SystemSound.play')
            .having((call) => call.arguments, 'sound', 'SystemSoundType.click'),
      ),
    );
  });

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

  testWidgets('click sound toggle suppresses activation audio', (tester) async {
    final platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InteractionSoundScope(
          navigationEnabled: true,
          clickEnabled: false,
          child: Scaffold(
            body: TvFocusable(
              autofocus: true,
              onPressed: () {},
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    platformCalls.clear();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(
      platformCalls.where((call) => call.method == 'SystemSound.play'),
      isEmpty,
    );
  });

  testWidgets('navigation sound follows directional focus toggle', (
    tester,
  ) async {
    final platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    Widget app({required bool navigationEnabled}) => MaterialApp(
      home: InteractionSoundScope(
        navigationEnabled: navigationEnabled,
        clickEnabled: false,
        child: TvShortcuts(
          child: Scaffold(
            body: Row(
              children: [
                TvFocusable(
                  autofocus: true,
                  onPressed: () {},
                  child: const SizedBox(width: 100, height: 100),
                ),
                TvFocusable(
                  onPressed: () {},
                  child: const SizedBox(width: 100, height: 100),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(navigationEnabled: true));
    await tester.pumpAndSettle();
    platformCalls.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      platformCalls.where((call) => call.method == 'SystemSound.play'),
      isNotEmpty,
    );

    await tester.pumpWidget(app(navigationEnabled: false));
    await tester.pumpAndSettle();
    platformCalls.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      platformCalls.where((call) => call.method == 'SystemSound.play'),
      isEmpty,
    );
  });
}
