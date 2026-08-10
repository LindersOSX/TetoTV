import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
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
    required this.onAudio,
    required this.onSubtitles,
    required this.onCaptionSize,
    required this.onPicture,
    required this.onFixVideo,
    this.onSources,
    required this.onOptions,
    required this.onDismiss,
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
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;
  final VoidCallback onCaptionSize;
  final VoidCallback onPicture;
  final VoidCallback onFixVideo;
  final VoidCallback? onSources;
  final VoidCallback onOptions;
  final VoidCallback onDismiss;
  final String footerHint;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 720 || media.size.height < 480;
    final horizontalInset = compact ? 12.0 : 28.0;
    final bottomInset = compact ? 10.0 : 24.0;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Align(
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
                                      ? Theme.of(context).textTheme.titleMedium
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
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.forward_rounded,
                          label: 'Forward ${seekForwardSeconds}s',
                          onPressed: onForward,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 18),
                        TetoPlayerControl(
                          icon: Icons.audiotrack_rounded,
                          label: 'Audio',
                          onPressed: onAudio,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.closed_caption_rounded,
                          label: 'CC',
                          onPressed: onSubtitles,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.text_fields_rounded,
                          label: 'Size',
                          onPressed: onCaptionSize,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.aspect_ratio_rounded,
                          label: 'Picture',
                          onPressed: onPicture,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.smart_display_outlined,
                          label: 'Player',
                          onPressed: onFixVideo,
                          onDismiss: onDismiss,
                        ),
                        if (onSources != null) ...[
                          const SizedBox(width: 8),
                          TetoPlayerControl(
                            icon: Icons.video_library_rounded,
                            label: 'Sources',
                            onPressed: onSources!,
                            onDismiss: onDismiss,
                          ),
                        ],
                        const SizedBox(width: 18),
                        TetoPlayerControl(
                          icon: Icons.tune_rounded,
                          label: 'Options',
                          onPressed: onOptions,
                          onDismiss: onDismiss,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 15 : 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: compact ? 3 : 4,
                      color: AppColors.accentBright,
                      backgroundColor: Colors.white.withValues(alpha: .24),
                    ),
                  ),
                  SizedBox(height: compact ? 6 : 9),
                  Row(
                    children: [
                      Text(
                        '${formatPlayerChromeDuration(position)}  /  '
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
                            footerHint,
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
    );
  }
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
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool primary;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      onKeyEvent: onDismiss == null
          ? null
          : (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                onDismiss!();
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
