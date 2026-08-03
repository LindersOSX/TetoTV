import 'package:anime_tv/app/router.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

double tvCanvasWidthForPhysicalPixels(double physicalWidth) {
  if (physicalWidth >= 3200) return 1600;
  if (physicalWidth >= 2400) return 1280;
  return 960;
}

class TetoTvApp extends ConsumerWidget {
  const TetoTvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(settingsPreferencesProvider);
    return MaterialApp.router(
      title: 'TetoTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: appRouter,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final physicalWidth = View.of(context).physicalSize.width;
        final canvasWidth = tvCanvasWidthForPhysicalPixels(physicalWidth);
        final scale =
            (mq.size.width / canvasWidth) * preferences.interfaceScale;

        return MediaQuery(
          data: mq.copyWith(
            size: Size(mq.size.width / scale, mq.size.height / scale),
            devicePixelRatio: mq.devicePixelRatio * scale,
            padding: mq.padding / scale,
            viewPadding: mq.viewPadding / scale,
            viewInsets: mq.viewInsets / scale,
            systemGestureInsets: mq.systemGestureInsets / scale,
          ),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: mq.size.width / scale,
              height: mq.size.height / scale,
              child: TvShortcuts(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
    );
  }
}
