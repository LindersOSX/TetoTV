import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const playerControlsIdleTimeout = Duration(seconds: 5);
const playerControlsDoubleDownWindow = Duration(milliseconds: 450);

/// Keeps a held D-pad Down press from reopening player controls immediately
/// after its initial key-down dismissed them.
///
/// Android TV remotes emit [KeyRepeatEvent]s while a button remains held. The
/// dismiss action moves focus back to the player surface, so without consuming
/// the repeats the surface interprets the same physical press as a request to
/// show the controls again.
bool consumeHiddenPlayerHudDownRepeat({
  required LogicalKeyboardKey key,
  required bool isRepeat,
  required bool controlsVisible,
}) {
  return isRepeat && !controlsVisible && key == LogicalKeyboardKey.arrowDown;
}

Duration playerSeekTarget({
  required Duration position,
  required Duration offset,
  required Duration duration,
}) {
  final candidate = position + offset;
  if (candidate < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && candidate > duration) return duration;
  return candidate;
}

/// Keeps a skip-segment seek away from the exact end-of-file boundary.
///
/// Several TV decoders emit their terminal callback synchronously when asked
/// to seek to the precise duration.  The skip button would then continue its
/// own callback while completion was already tearing down the player.  Landing
/// one second before EOF lets the ordinary playback-completion path own that
/// transition without making outro skipping perceptibly slower.
Duration safeSkipSegmentTarget({
  required Duration requested,
  required Duration duration,
  Duration endGuard = const Duration(seconds: 1),
}) {
  if (requested <= Duration.zero) return Duration.zero;
  if (duration <= Duration.zero) return requested;
  final lastSafePosition = duration > endGuard
      ? duration - endGuard
      : Duration.zero;
  if (requested >= lastSafePosition) return lastSafePosition;
  return requested;
}

bool skipSegmentReachesPlaybackEnd({
  required Duration requestedEnd,
  required Duration duration,
  Duration endGuard = const Duration(seconds: 1),
}) => duration > Duration.zero && requestedEnd >= duration - endGuard;

/// Accelerates a held D-pad scrub without making the first correction coarse.
Duration playerScrubStep(int repeatCount) =>
    repeatCount >= 5 ? const Duration(minutes: 1) : const Duration(seconds: 30);

/// Detects an intentional double press of D-pad Down without treating a held
/// button (which produces key-repeat events) as two presses.
class PlayerDoubleDownDetector {
  PlayerDoubleDownDetector({this.window = playerControlsDoubleDownWindow});

  final Duration window;
  DateTime? _lastDownAt;

  bool register(LogicalKeyboardKey key, {DateTime? at}) {
    if (key != LogicalKeyboardKey.arrowDown) {
      _lastDownAt = null;
      return false;
    }
    final now = at ?? DateTime.now();
    final previous = _lastDownAt;
    _lastDownAt = now;
    if (previous == null || now.difference(previous) > window) return false;
    _lastDownAt = null;
    return true;
  }

  void reset() => _lastDownAt = null;
}

String canonicalPlayerLanguage(String? value) {
  final normalized = (value ?? '').trim().toLowerCase().replaceAll('_', '-');
  if (normalized.isEmpty) return '';
  if (RegExp(
    r'(^|[^a-z])(english|eng|en(?:-[a-z]{2})?)([^a-z]|$)',
  ).hasMatch(normalized)) {
    return 'eng';
  }
  if (RegExp(r'(^|[^a-z])(japanese|jpn|ja)([^a-z]|$)').hasMatch(normalized)) {
    return 'jpn';
  }
  if (RegExp(r'(^|[^a-z])(spanish|spa|es)([^a-z]|$)').hasMatch(normalized)) {
    return 'spa';
  }
  if (RegExp(r'(^|[^a-z])(french|fra|fre|fr)([^a-z]|$)').hasMatch(normalized)) {
    return 'fra';
  }
  return normalized;
}

bool playerTrackMatchesLanguage({
  String? language,
  String? title,
  required String preferredLanguage,
}) {
  final wanted = canonicalPlayerLanguage(preferredLanguage);
  if (wanted.isEmpty) return false;
  if (canonicalPlayerLanguage(language) == wanted) return true;
  if (canonicalPlayerLanguage(title) == wanted) return true;
  final rawTitle = (title ?? '').toLowerCase();
  return rawTitle.contains(preferredLanguage.toLowerCase());
}

int playerTrackLanguageScore({
  String? language,
  String? title,
  required String preferredLanguage,
  bool isDefault = false,
  bool subtitle = false,
}) {
  if (!playerTrackMatchesLanguage(
    language: language,
    title: title,
    preferredLanguage: preferredLanguage,
  )) {
    return 0;
  }
  final label = (title ?? '').toLowerCase();
  var score = 100;
  if (isDefault) score += 8;
  if (label.contains('commentary') || label.contains('descriptive')) {
    score -= 120;
  }
  if (subtitle &&
      (label.contains('signs') ||
          label.contains('songs') ||
          label.contains('forced'))) {
    score -= 25;
  }
  return score;
}

class PlayerTrackOption<T> {
  const PlayerTrackOption({
    required this.value,
    required this.label,
    this.detail,
    this.icon,
  });

  final T value;
  final String label;
  final String? detail;
  final IconData? icon;
}

Future<T?> showPlayerTrackPicker<T>({
  required BuildContext context,
  required String title,
  required IconData icon,
  required List<PlayerTrackOption<T>> options,
  required T selectedValue,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (context) => PlayerTrackPicker<T>(
      title: title,
      icon: icon,
      options: options,
      selectedValue: selectedValue,
    ),
  );
}

Future<PreferredPlayer?> showPlayerEnginePicker({
  required BuildContext context,
  required PreferredPlayer current,
}) {
  return showPlayerTrackPicker<PreferredPlayer>(
    context: context,
    title: 'Choose player',
    icon: Icons.smart_display_rounded,
    selectedValue: current,
    options: const [
      PlayerTrackOption(
        value: PreferredPlayer.media3,
        label: 'Media3',
        detail: 'Android native player',
        icon: Icons.android_rounded,
      ),
      PlayerTrackOption(
        value: PreferredPlayer.mpv,
        label: 'MPV',
        detail: 'Best subtitle and web-stream support',
        icon: Icons.subtitles_rounded,
      ),
      PlayerTrackOption(
        value: PreferredPlayer.vlc,
        label: 'VLC',
        detail: 'Compatibility player',
        icon: Icons.video_settings_rounded,
      ),
    ],
  );
}

class PlayerTrackPicker<T> extends StatelessWidget {
  const PlayerTrackPicker({
    required this.title,
    required this.icon,
    required this.options,
    required this.selectedValue,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<PlayerTrackOption<T>> options;
  final T selectedValue;

  @override
  Widget build(BuildContext context) {
    final hasSelected = options.any((option) => option.value == selectedValue);
    return Dialog(
      key: const ValueKey('player-track-picker'),
      alignment: Alignment.bottomCenter,
      insetPadding: const EdgeInsets.fromLTRB(32, 24, 32, 28),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 220),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFA080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withValues(alpha: .75)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppColors.accentBright, size: 20),
                    const SizedBox(width: 9),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Select with D-pad',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: options.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 9),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final selected = option.value == selectedValue;
                      return TvFocusable(
                        key: ValueKey('player-track-option-$index'),
                        autofocus: selected || (!hasSelected && index == 0),
                        focusScale: 1.02,
                        borderRadius: BorderRadius.circular(9),
                        onPressed: () =>
                            Navigator.of(context).pop(option.value),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.accent.withValues(alpha: .3)
                                : const Color(0xFF171717),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : option.icon ?? Icons.circle_outlined,
                                size: 18,
                                color: selected
                                    ? AppColors.accentBright
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      option.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (option.detail case final detail?)
                                      Text(
                                        detail,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool?> showPlayerExitConfirmation(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x99000000),
    builder: (_) => const PlayerExitDialog(),
  );
}

/// A remote-safe exit prompt shared by the Flutter playback engines.
///
/// Arrow navigation is handled explicitly because some TV firmware does not
/// move focus between mixed Material button types inside an [AlertDialog].
class PlayerExitDialog extends StatefulWidget {
  const PlayerExitDialog({super.key});

  @override
  State<PlayerExitDialog> createState() => _PlayerExitDialogState();
}

class _PlayerExitDialogState extends State<PlayerExitDialog> {
  final _continueFocus = FocusNode(debugLabel: 'player.exit.continue');
  final _exitFocus = FocusNode(debugLabel: 'player.exit.confirm');

  @override
  void dispose() {
    _continueFocus.dispose();
    _exitFocus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _continueFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _exitFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const ValueKey('player-exit-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Focus(
        onKeyEvent: _handleKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFA09090B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .3)),
              boxShadow: const [
                BoxShadow(color: Color(0xA0000000), blurRadius: 28),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exit video?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your current playback position will be saved.',
                    style: TextStyle(
                      color: Color(0xFFF0EAEC),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 400;
                      final continueButton = TvFocusable(
                        key: const ValueKey('player-exit-continue'),
                        focusNode: _continueFocus,
                        autofocus: true,
                        focusScale: 1.015,
                        borderRadius: BorderRadius.circular(9),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xA629292E),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Continue watching',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                      final exitButton = TvFocusable(
                        key: const ValueKey('player-exit-confirm'),
                        focusNode: _exitFocus,
                        focusScale: 1.015,
                        borderRadius: BorderRadius.circular(9),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Exit video',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (compact) {
                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: continueButton,
                            ),
                            const SizedBox(height: 10),
                            SizedBox(width: double.infinity, child: exitButton),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: continueButton),
                          const SizedBox(width: 12),
                          Expanded(child: exitButton),
                        ],
                      );
                    },
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
