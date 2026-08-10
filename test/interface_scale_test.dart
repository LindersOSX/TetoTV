import 'package:anime_tv/core/layout/interface_scaling.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic layout follows device category', () {
    expect(
      useTelevisionCanvas(
        detectedTelevision: true,
        mode: InterfaceMode.automatic,
      ),
      isTrue,
    );
    expect(
      useTelevisionCanvas(
        detectedTelevision: false,
        mode: InterfaceMode.automatic,
      ),
      isFalse,
    );
  });

  test('phone mode bypasses the virtual TV canvas on the same APK', () {
    final tvScale = interfaceCanvasScale(
      logicalWidth: 1920,
      physicalWidth: 1920,
      detectedTelevision: true,
      mode: InterfaceMode.television,
      userScale: 1,
    );
    final phoneScale = interfaceCanvasScale(
      logicalWidth: 1920,
      physicalWidth: 1920,
      detectedTelevision: true,
      mode: InterfaceMode.phone,
      userScale: 1,
    );

    expect(tvScale, 2);
    expect(phoneScale, 1);
  });

  test('user interface scale changes TV geometry', () {
    final compact = interfaceCanvasScale(
      logicalWidth: 1920,
      physicalWidth: 1920,
      detectedTelevision: true,
      mode: InterfaceMode.television,
      userScale: .8,
    );
    final large = interfaceCanvasScale(
      logicalWidth: 1920,
      physicalWidth: 1920,
      detectedTelevision: true,
      mode: InterfaceMode.television,
      userScale: 1.2,
    );

    expect(compact, 1.6);
    expect(large, 2.4);
  });
}
