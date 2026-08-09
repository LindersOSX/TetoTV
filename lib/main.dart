import 'package:anime_tv/app/app.dart';
import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/performance/performance_monitor.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PerformanceMonitor.instance.start();
  final isTelevision = await AndroidTvBridge.instance.isTelevision().timeout(
    const Duration(seconds: 2),
    onTimeout: () => false,
  );
  runApp(
    ProviderScope(
      overrides: [isTelevisionProvider.overrideWithValue(isTelevision)],
      child: const TetoTvApp(),
    ),
  );
}
