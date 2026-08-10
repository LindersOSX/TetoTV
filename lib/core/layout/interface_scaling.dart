import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';

double tvCanvasWidthForPhysicalPixels(double physicalWidth) {
  if (physicalWidth >= 3200) return 1600;
  if (physicalWidth >= 2400) return 1280;
  return 960;
}

bool useTelevisionCanvas({
  required bool detectedTelevision,
  required InterfaceMode mode,
}) => switch (mode) {
  InterfaceMode.automatic => detectedTelevision,
  InterfaceMode.television => true,
  InterfaceMode.phone => false,
};

double interfaceCanvasScale({
  required double logicalWidth,
  required double physicalWidth,
  required bool detectedTelevision,
  required InterfaceMode mode,
  required double userScale,
}) {
  final televisionCanvas = useTelevisionCanvas(
    detectedTelevision: detectedTelevision,
    mode: mode,
  );
  final baseScale = televisionCanvas
      ? logicalWidth / tvCanvasWidthForPhysicalPixels(physicalWidth)
      : 1.0;
  return (baseScale * userScale).clamp(.5, 3.0).toDouble();
}
