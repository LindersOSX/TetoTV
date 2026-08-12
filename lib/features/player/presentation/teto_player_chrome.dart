import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/player/presentation/player_control_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Visual language shared by every Flutter-backed playback engine.
///
/// Engine integration remains deliberately outside this widget. MPV and VLC
/// only provide their current state and callbacks, which prevents their
/// controls from drifting apart when the player UI changes.
class TetoPlayerChrome extends StatelessWidget {
  const TetoPlayerChrome({
    required this.engineKey,
    required this.title,
    required this.streamLabel,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.playFocusNode,
    required this.seekBackSeconds,
    required this.seekForwardSeconds,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onSeek,
    required this.onAudio,
    required this.onSubtitles,
    required this.onCaptionSize,
    required this.onPicture,
    required this.onFixVideo,
    this.onSources,
    required this.onOptions,
    required this.onDismiss,
    this.scrubController,
    this.onScrubStarted,
    this.onScrubFinished,
    this.engineLabel,
    this.footerHint = 'D-pad controls  |  J/L seek  |  Menu/Y options',
    super.key,
  });

  final String engineKey;
  final String title;
  final String streamLabel;
  final String? engineLabel;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final FocusNode playFocusNode;
  final int seekBackSeconds;
  final int seekForwardSeconds;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;
  final VoidCallback onCaptionSize;
  final VoidCallback onPicture;
  final VoidCallback onFixVideo;
  final VoidCallback? onSources;
  final VoidCallback onOptions;
  final VoidCallback onDismiss;
  final PlayerScrubController? scrubController;
  final VoidCallback? onScrubStarted;
  final VoidCallback? onScrubFinished;
  final String footerHint;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 720 || media.size.height < 480;
    final horizontalInset = compact ? 12.0 : 28.0;
    final bottomInset = compact ? 10.0 : 24.0;
    return _PlayerScrubHost(
      position: position,
      duration: duration,
      onSeek: onSeek,
      controller: scrubController,
      onScrubStarted: onScrubStarted,
      onScrubFinished: onScrubFinished,
      builder: (context, scrubber) => Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          minimum: EdgeInsets.fromLTRB(
            horizontalInset,
            0,
            horizontalInset,
            bottomInset,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: DecoratedBox(
              key: ValueKey('$engineKey-bottom-player-chrome'),
              decoration: BoxDecoration(
                color: const Color(0xD6080808),
                borderRadius: BorderRadius.circular(compact ? 12 : 16),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: .78),
                  width: 1.4,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xA8000000),
                    blurRadius: 26,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 18,
                  compact ? 10 : 14,
                  compact ? 12 : 18,
                  compact ? 9 : 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (compact
                                        ? Theme.of(
                                            context,
                                          ).textTheme.titleMedium
                                        : Theme.of(
                                            context,
                                          ).textTheme.headlineSmall)
                                    ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (!compact && engineLabel != null) ...[
                          _PlayerBadge(text: engineLabel!),
                          const SizedBox(width: 8),
                        ],
                        _PlayerBadge(text: streamLabel),
                      ],
                    ),
                    SizedBox(height: compact ? 7 : 10),
                    SingleChildScrollView(
                      key: ValueKey('$engineKey-player-controls-scroll'),
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(
                        children: [
                          TetoPlayerControl(
                            icon: Icons.replay_rounded,
                            label: 'Back ${seekBackSeconds}s',
                            onPressed: onRewind,
                            onDismiss: onDismiss,
                            onOpenScrub: scrubber.open,
                          ),
                          const SizedBox(width: 8),
                          TetoPlayerControl(
                            focusNode: playFocusNode,
                            primary: true,
                            icon: isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            label: isPlaying ? 'Pause' : 'Play',
                            onPressed: onPlayPause,
                            onDismiss: onDismiss,
                            onOpenScrub: scrubber.open,
                          ),
                          const SizedBox(width: 8),
                          TetoPlayerControl(
                            icon: Icons.forward_rounded,
                            label: 'Forward ${seekForwardSeconds}s',
                            onPressed: onForward,
                            onDismiss: onDismiss,
                            onOpenScrub: scrubber.open,
                          ),
                          const SizedBox(width: 18),
                          TetoPlayerControl(
                            icon: Icons.audiotrack_rounded,
                            label: 'Audio',
                            onPressed: onAudio,
                            onDismiss: onDismiss,
                            onOpenScrub: scrubber.open,
                          ),
                          const SizedBox(width: 8),
                          TetoPlayerControl(
                            icon: Icons.closed_caption_rounded,
                            label: 'CC',
                            onPressed: onSubtitles,
                            onDismiss: onDismiss,
                            onOpenScrub: scrubber.open,
                          ),
                          const SizedBox(width: 8),
                          TetoPlayerControl(
                            icon: Icons.text_fields_rounded,
                            label: 'Size',
                            onPressed: onCaptionSize,
                            onDismiss: onDismiss,
                            onOpenScrub: scrubber.open,
                          ),
                          const SizedBox(width: 8),
                          TetoPlayerControl(
                            icon: Icons.aspect_ratio_rounded,
                            label: 'Picture',
                            onPressed: onPicture,
                            onDismiss: onDismiss,
                            onOpenScrub: scrubber.open,
                          ),
                          const SizedBox(width: 8),
                          TetoPlayerControl(
                            icon: Icons.smart_display_outlined,
                            label: 'Player',
                            onPressed: onFixVideo,
                            onDismiss: onDismiss,
                            onOpenScrub: scrubber.open,
                          ),
                          if (onSources != null) ...[
                            const SizedBox(width: 8),
                            TetoPlayerControl(
                              icon: Icons.video_library_rounded,
                              label: 'Sources',
                              onPressed: onSources!,
                              onDismiss: onDismiss,
                              onOpenScrub: scrubber.open,
                            ),
                          ],
                          const SizedBox(width: 18),
                          TetoPlayerControl(
                            icon: Icons.tune_rounded,
                            label: 'Options',
                            onPressed: onOptions,
                            onDismiss: onDismiss,
                            onOpenScrub: scrubber.open,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 15 : 18),
                    scrubber.progressBar(compact: compact),
                    SizedBox(height: compact ? 6 : 9),
                    Row(
                      children: [
                        Text(
                          '${formatPlayerChromeDuration(scrubber.displayPosition)}  /  '
                          '${formatPlayerChromeDuration(duration)}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 11 : 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!compact) ...[
                          const Spacer(),
                          Flexible(
                            child: Text(
                              scrubber.isScrubbing
                                  ? 'Select to seek  |  Back to cancel'
                                  : 'Up to scrub  |  $footerHint',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the owning player cancel an in-progress scrub before treating Back as
/// an attempt to leave playback.
class PlayerScrubController {
  VoidCallback? _cancelActiveScrub;
  Object? _activeOwner;

  bool get isActive => _cancelActiveScrub != null;

  bool cancel() {
    final cancel = _cancelActiveScrub;
    if (cancel == null) return false;
    cancel();
    return true;
  }

  void _activate(Object owner, VoidCallback cancel) {
    _activeOwner = owner;
    _cancelActiveScrub = cancel;
  }

  void _deactivate(Object owner) {
    if (identical(_activeOwner, owner)) {
      _activeOwner = null;
      _cancelActiveScrub = null;
    }
  }
}

class _PlayerScrubHost extends StatefulWidget {
  const _PlayerScrubHost({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.builder,
    this.controller,
    this.onScrubStarted,
    this.onScrubFinished,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final Widget Function(BuildContext context, _PlayerScrubHostState scrubber)
  builder;
  final PlayerScrubController? controller;
  final VoidCallback? onScrubStarted;
  final VoidCallback? onScrubFinished;

  @override
  State<_PlayerScrubHost> createState() => _PlayerScrubHostState();
}

class _PlayerScrubHostState extends State<_PlayerScrubHost> {
  final FocusNode _progressFocus = FocusNode(
    debugLabel: 'player.progress.scrubber',
  );
  late PlayerScrubController _controller;
  Duration? _target;
  FocusNode? _returnFocus;
  bool _progressFocused = false;
  int _repeatCount = 0;
  LogicalKeyboardKey? _repeatDirection;

  bool get isScrubbing => _target != null;
  Duration get displayPosition => _target ?? widget.position;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PlayerScrubController();
  }

  @override
  void didUpdateWidget(covariant _PlayerScrubHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      cancel();
      _controller = widget.controller ?? PlayerScrubController();
    }
    final target = _target;
    if (target != null && widget.duration > Duration.zero) {
      final clamped = playerSeekTarget(
        position: target,
        offset: Duration.zero,
        duration: widget.duration,
      );
      if (clamped != target) _target = clamped;
    }
  }

  void open() {
    if (widget.duration <= Duration.zero) return;
    _beginScrub();
    _progressFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _progressFocus.requestFocus();
    });
  }

  void _beginScrub() {
    if (isScrubbing || widget.duration <= Duration.zero) return;
    _returnFocus = FocusManager.instance.primaryFocus;
    _repeatCount = 0;
    _repeatDirection = null;
    setState(
      () => _target = playerSeekTarget(
        position: widget.position,
        offset: Duration.zero,
        duration: widget.duration,
      ),
    );
    _controller._activate(this, cancel);
    widget.onScrubStarted?.call();
  }

  void cancel() {
    if (!isScrubbing) return;
    _controller._deactivate(this);
    setState(() {
      _target = null;
      _repeatCount = 0;
      _repeatDirection = null;
    });
    widget.onScrubFinished?.call();
    _restoreFocus();
  }

  void _commit() {
    final target = _target;
    if (target == null) {
      open();
      return;
    }
    _controller._deactivate(this);
    setState(() {
      _target = null;
      _repeatCount = 0;
      _repeatDirection = null;
    });
    widget.onSeek(target);
    widget.onScrubFinished?.call();
    _restoreFocus();
  }

  void _restoreFocus() {
    final focus = _returnFocus;
    _returnFocus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && focus?.canRequestFocus == true) focus!.requestFocus();
    });
  }

  void _adjust(LogicalKeyboardKey direction, {required bool repeat}) {
    if (!isScrubbing) open();
    if (!isScrubbing) return;
    if (!repeat || _repeatDirection != direction) {
      _repeatCount = 0;
      _repeatDirection = direction;
    } else {
      _repeatCount += 1;
    }
    final step = playerScrubStep(_repeatCount);
    final offset = direction == LogicalKeyboardKey.arrowLeft ? -step : step;
    setState(() {
      _target = playerSeekTarget(
        position: _target!,
        offset: offset,
        duration: widget.duration,
      );
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _adjust(key, repeat: event is KeyRepeatEvent);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _commit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _touchSeek(double dx, double width) {
    if (widget.duration <= Duration.zero || width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (widget.duration.inMilliseconds * fraction).round(),
    );
    widget.onScrubStarted?.call();
    widget.onSeek(target);
    widget.onScrubFinished?.call();
  }

  void _beginTouchScrub(double dx, double width) {
    if (widget.duration <= Duration.zero || width <= 0) return;
    _beginScrub();
    _updateTouchTarget(dx, width);
  }

  void _updateTouchTarget(double dx, double width) {
    if (!isScrubbing || width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _target = Duration(
        milliseconds: (widget.duration.inMilliseconds * fraction).round(),
      );
    });
  }

  Widget progressBar({required bool compact}) {
    final durationMs = widget.duration.inMilliseconds;
    final progress = durationMs <= 0
        ? 0.0
        : (displayPosition.inMilliseconds / durationMs).clamp(0.0, 1.0);
    return Focus(
      focusNode: _progressFocus,
      onKeyEvent: _handleKey,
      onFocusChange: (focused) {
        if (_progressFocused != focused && mounted) {
          setState(() => _progressFocused = focused);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) => Semantics(
          label: 'Playback position',
          value:
              '${formatPlayerChromeDuration(displayPosition)} of '
              '${formatPlayerChromeDuration(widget.duration)}',
          hint: 'Press Up from the controls, then Left or Right to scrub',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              _touchSeek(details.localPosition.dx, constraints.maxWidth);
            },
            onHorizontalDragStart: (details) => _beginTouchScrub(
              details.localPosition.dx,
              constraints.maxWidth,
            ),
            onHorizontalDragUpdate: (details) => _updateTouchTarget(
              details.localPosition.dx,
              constraints.maxWidth,
            ),
            onHorizontalDragEnd: (_) => _commit(),
            onHorizontalDragCancel: cancel,
            child: SizedBox(
              key: const ValueKey('player-progress-scrubber'),
              height: compact ? 26 : 30,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _progressFocused || isScrubbing
                        ? AppColors.focusRing
                        : Colors.transparent,
                    width: 2,
                  ),
                  color: isScrubbing
                      ? AppColors.accent.withValues(alpha: .16)
                      : Colors.transparent,
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned.fill(
                      top: 4,
                      bottom: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          color: AppColors.accentBright,
                          backgroundColor: Colors.white.withValues(alpha: .24),
                        ),
                      ),
                    ),
                    if (_progressFocused || isScrubbing)
                      Align(
                        alignment: Alignment(progress * 2 - 1, 0),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accentBright,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller._deactivate(this);
    _progressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, this);
}

class TetoSkipSegmentOverlay extends StatelessWidget {
  const TetoSkipSegmentOverlay({
    required this.label,
    required this.onPressed,
    this.focusNode,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      key: const ValueKey('player-skip-segment-overlay'),
      focusNode: focusNode,
      onPressed: onPressed,
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xB30B0B0D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.accentBright.withValues(alpha: .82),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x77000000), blurRadius: 16),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.skip_next_rounded,
              color: AppColors.accentBright,
              size: 21,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TetoPlayerControl extends StatelessWidget {
  const TetoPlayerControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.primary = false,
    this.onDismiss,
    this.onOpenScrub,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool primary;
  final VoidCallback? onDismiss;
  final VoidCallback? onOpenScrub;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      onKeyEvent: onDismiss == null && onOpenScrub == null
          ? null
          : (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                onDismiss?.call();
                return KeyEventResult.handled;
              }
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowUp &&
                  onOpenScrub != null) {
                onOpenScrub!();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: primary ? AppColors.accent : const Color(0x8F242429),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerBadge extends StatelessWidget {
  const _PlayerBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: .35)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.accentBright,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

String formatPlayerChromeDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
