import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:flutter/material.dart';
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
    expect(keyboardSize.width, 650);
    expect(keyboardSize.height, lessThan(290));
  });
}
