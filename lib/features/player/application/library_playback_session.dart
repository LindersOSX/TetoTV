import 'dart:async';

import 'package:anime_tv/features/player/domain/library_playback_request.dart';

/// Serializes progress delivery across engine handoffs.
///
/// Ordinary playback samples are emitted no more than once every two seconds.
/// Play/pause transitions, forced checkpoints, and the final sample bypass the
/// time gate. A slow Jellyfin/Plex callback therefore cannot build an unbounded
/// queue while a player reports position several times per second.
class LibraryPlaybackSession {
  LibraryPlaybackSession(this.request);

  static const progressInterval = Duration(seconds: 2);

  final LibraryPlaybackRequest request;
  Future<void>? _startFuture;
  Future<void>? _progressDrain;
  LibraryPlaybackProgress? _pendingProgress;
  LibraryPlaybackProgress? _lastProgress;
  DateTime? _lastQueuedAt;
  bool? _lastQueuedPlaying;
  bool _completed = false;
  bool _finished = false;
  String? _failure;

  LibraryPlaybackProgress? get lastProgress => _lastProgress;
  bool get isFinished => _finished;

  /// Announces playback only after the typed player route has mounted.
  ///
  /// Progress delivery also awaits this future, so a slow media server can
  /// never observe progress before its Playing/started notification.
  Future<void> start() => _startFuture ??= _deliverStart();

  void report({
    required Duration position,
    required Duration duration,
    required bool playing,
    DateTime? sampledAt,
    bool force = false,
  }) {
    if (_finished) return;
    final now = (sampledAt ?? DateTime.now()).toUtc();
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    final maximum = safeDuration > Duration.zero
        ? safeDuration
        : const Duration(hours: 24);
    final safePosition = position.isNegative
        ? Duration.zero
        : position > maximum
        ? maximum
        : position;
    final progress = LibraryPlaybackProgress(
      position: safePosition,
      duration: safeDuration,
      playing: playing,
      sampledAt: now,
    );
    _lastProgress = progress;
    final stateChanged = _lastQueuedPlaying != playing;
    final intervalElapsed =
        _lastQueuedAt == null ||
        now.difference(_lastQueuedAt!) >= progressInterval;
    if (!force && !stateChanged && !intervalElapsed) return;
    _lastQueuedAt = now;
    _lastQueuedPlaying = playing;
    _enqueueProgress(progress);
  }

  void markCompleted({Duration? position, Duration? duration}) {
    if (_finished) return;
    _completed = true;
    final last = _lastProgress;
    report(
      position: position ?? duration ?? last?.position ?? Duration.zero,
      duration: duration ?? last?.duration ?? Duration.zero,
      playing: false,
      force: true,
    );
  }

  void markFailed(Object error) {
    if (_finished) return;
    _failure = error.toString();
  }

  Future<void> finish() async {
    if (_finished) return;
    final started = _startFuture;
    _finished = true;
    if (started != null) await started;
    final progress = _lastProgress;
    if (progress != null) _enqueueProgress(progress);
    while (_progressDrain != null) {
      await _progressDrain!;
    }
    final callback = request.onFinished;
    if (callback == null) return;
    final reason = _failure != null
        ? LibraryPlaybackEndReason.failed
        : _completed
        ? LibraryPlaybackEndReason.completed
        : LibraryPlaybackEndReason.exited;
    try {
      await callback(
        LibraryPlaybackResult(
          position: progress?.position ?? request.initialPosition,
          duration: progress?.duration ?? Duration.zero,
          reason: reason,
          started: _startFuture != null,
          error: _failure,
        ),
      );
    } catch (_) {
      // Server progress reporting must never strand or crash the player route.
    }
  }

  void _enqueueProgress(LibraryPlaybackProgress progress) {
    final callback = request.onProgress;
    if (callback == null) return;
    _pendingProgress = progress;
    if (_progressDrain != null) return;
    late final Future<void> drain;
    drain = _drainProgress(callback).whenComplete(() {
      if (identical(_progressDrain, drain)) _progressDrain = null;
      if (_pendingProgress != null) _enqueueProgress(_pendingProgress!);
    });
    _progressDrain = drain;
  }

  Future<void> _drainProgress(LibraryPlaybackProgressCallback callback) async {
    while (_pendingProgress != null) {
      final progress = _pendingProgress!;
      _pendingProgress = null;
      await start();
      try {
        await callback(progress);
      } catch (_) {
        // Best effort: offline media servers must not interrupt playback.
      }
    }
  }

  Future<void> _deliverStart() async {
    final callback = request.onStarted;
    if (callback == null) return;
    try {
      await callback(request.initialPosition);
    } catch (_) {
      // Media-server writeback is best effort and must not block playback.
    }
  }
}
