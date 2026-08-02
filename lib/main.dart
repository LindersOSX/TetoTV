import 'package:anime_tv/app/app.dart';
import 'package:anime_tv/core/performance/performance_monitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PerformanceMonitor.instance.start();
  runApp(const ProviderScope(child: TetoTvApp()));
}
