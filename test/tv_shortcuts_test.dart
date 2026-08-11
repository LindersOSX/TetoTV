import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'D-pad chooses the nearest vertical control in an irregular layout',
    (tester) async {
      final nodes = <int, FocusNode>{
        for (final id in [1, 2, 3, 5, 6, 7, 8, 9])
          id: FocusNode(debugLabel: 'spatial.$id'),
      };
      addTearDown(() {
        for (final node in nodes.values) {
          node.dispose();
        }
      });

      Widget control(int id, double left, double top) => Positioned(
        left: left,
        top: top,
        child: SizedBox(
          width: 70,
          height: 44,
          child: TvFocusable(
            focusNode: nodes[id],
            autofocus: id == 1,
            onPressed: () {},
            child: ColoredBox(
              color: Colors.black,
              child: Center(child: Text('$id')),
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TvShortcuts(
            child: Scaffold(
              body: Stack(
                children: [
                  control(1, 10, 10),
                  control(2, 100, 10),
                  control(3, 190, 10),
                  control(5, 360, 90),
                  control(6, 360, 155),
                  control(7, 10, 250),
                  control(8, 100, 250),
                  control(9, 190, 250),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'spatial.1');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'spatial.5');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'spatial.6');
    },
  );
}
