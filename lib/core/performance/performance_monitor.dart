import 'dart:async';

import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:flutter/scheduler.dart';

class PerformanceMonitor {
  PerformanceMonitor._();

  static final instance = PerformanceMonitor._();
  bool _started = false;
  final Stopwatch _startup = Stopwatch();

  void start() {
    if (_started) return;
    _started = true;
    _startup.start();
    SchedulerBinding.instance.addTimingsCallback(_recordFrames);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _startup.stop();
      _record('startup_first_frame', _startup.elapsed);
    });
  }

  void _recordFrames(List<FrameTiming> timings) {
    for (final timing in timings) {
      final total = timing.totalSpan;
      if (total > const Duration(milliseconds: 20)) {
        _record('slow_frame', total);
      }
    }
  }

  void _record(String name, Duration duration) {
    unawaited(
      TetoTvDatabase.instance
          .recordPerformance(name, duration)
          .catchError((_) {}),
    );
  }
}
