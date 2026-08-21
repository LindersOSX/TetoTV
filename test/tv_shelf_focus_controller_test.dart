import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/tv_shelf_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('attached but clipped shelf targets are still revealed', (
    tester,
  ) async {
    final controller = TvShelfFocusController(
      debugLabel: 'clipped-shelf',
      itemCount: 12,
    );
    addTearDown(controller.dispose);
    await _pumpShelf(tester, controller);

    expect(controller.focusNodeAt(3).context, isNotNull);
    controller.requestFocus(preferredIndex: 3, itemExtent: 80, spacing: 8);
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'clipped-shelf.item.3',
    );
    expect(controller.scrollController.offset, greaterThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cross-row focus reveals a far lazy shelf target before focus', (
    tester,
  ) async {
    final controller = TvShelfFocusController(
      debugLabel: 'far-shelf',
      itemCount: 50,
    );
    addTearDown(controller.dispose);
    await _pumpShelf(tester, controller);

    controller.focusNodeAt(0).requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'far-shelf.item.0');

    expect(
      controller.requestFocus(preferredIndex: 40, itemExtent: 80, spacing: 8),
      isTrue,
    );
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'far-shelf.item.40');
    expect(controller.scrollController.offset, greaterThan(2500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest opposite request cancels a stale far-shelf focus', (
    tester,
  ) async {
    final controller = TvShelfFocusController(
      debugLabel: 'rapid-shelf',
      itemCount: 50,
    );
    addTearDown(controller.dispose);
    await _pumpShelf(tester, controller);

    controller.focusNodeAt(0).requestFocus();
    await tester.pump();
    controller.requestFocus(
      preferredIndex: 40,
      itemExtent: 80,
      spacing: 8,
      rapid: true,
    );
    await tester.pump(const Duration(milliseconds: 18));
    controller.requestFocus(
      preferredIndex: 2,
      itemExtent: 80,
      spacing: 8,
      rapid: true,
    );
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'rapid-shelf.item.2',
    );
    expect(controller.scrollController.offset, lessThan(120));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpShelf(
  WidgetTester tester,
  TvShelfFocusController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 100,
          child: ListView.separated(
            controller: controller.scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: controller.itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, index) => SizedBox(
              width: 80,
              child: TvFocusable(
                focusNode: controller.focusNodeAt(index),
                onPressed: () {},
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(child: Text('Item $index')),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
