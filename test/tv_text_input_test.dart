import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens an app-owned keyboard without an EditableText', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 500,
              child: TvTextInput(controller: controller, labelText: 'Search'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(TvKeyboardDialog), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('PASTE'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);
    final keyboardSize = tester.getSize(
      find.byKey(const ValueKey('tv-keyboard-panel')),
    );
    expect(keyboardSize.width, inInclusiveRange(540, 560));
    expect(keyboardSize.height, lessThan(250));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('#?&'), findsOneWidget);
  });

  testWidgets('physical Enter commits the TV keyboard value', (tester) async {
    final controller = TextEditingController(text: 'Naruto');
    addTearDown(controller.dispose);
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvTextInput(
            controller: controller,
            labelText: 'Search',
            onSubmitted: (value) => submitted = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Naruto'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(TvKeyboardDialog), findsNothing);
    expect(submitted, 'Naruto');
    expect(controller.text, 'Naruto');
  });
}
