import 'dart:async';

import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _TvSecondaryActivateIntent extends Intent {
  const _TvSecondaryActivateIntent();
}

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    required this.child,
    required this.onPressed,
    this.autofocus = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.focusScale = 1.045,
    this.focusNode,
    this.onFocusChanged,
    this.onLongPress,
    super.key,
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;
  final BorderRadius borderRadius;
  final double focusScale;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChanged;
  final VoidCallback? onLongPress;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _fallbackFocusNode;
  bool _focused = false;
  Timer? _holdTimer;
  bool _holdTriggered = false;

  FocusNode get _focusNode => widget.focusNode ?? _fallbackFocusNode;

  void _activate(VoidCallback? action) {
    if (action == null) return;
    unawaited(SystemSound.play(SystemSoundType.click));
    action();
  }

  @override
  void initState() {
    super.initState();
    _fallbackFocusNode = FocusNode(debugLabel: 'TV mouse/D-pad control');
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _fallbackFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleRemoteActivation(FocusNode node, KeyEvent event) {
    if (widget.onLongPress == null ||
        (event.logicalKey != LogicalKeyboardKey.select &&
            event.logicalKey != LogicalKeyboardKey.enter)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _holdTimer?.cancel();
      _holdTriggered = false;
      _holdTimer = Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        _holdTriggered = true;
        _activate(widget.onLongPress);
      });
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      _holdTimer?.cancel();
      _holdTimer = null;
      if (!_holdTriggered) _activate(widget.onPressed);
      _holdTriggered = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  void _handleFocus(bool focused) {
    setState(() => _focused = focused);
    widget.onFocusChanged?.call(focused);
    if (focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handleRemoteActivation,
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.contextMenu):
                _TvSecondaryActivateIntent(),
          },
          child: FocusableActionDetector(
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            onFocusChange: _handleFocus,
            onShowHoverHighlight: (hovering) {
              if (hovering) _focusNode.requestFocus();
            },
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _activate(widget.onPressed);
                  return null;
                },
              ),
              _TvSecondaryActivateIntent:
                  CallbackAction<_TvSecondaryActivateIntent>(
                    onInvoke: (_) {
                      _activate(widget.onLongPress);
                      return null;
                    },
                  ),
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _focusNode.requestFocus();
                  _activate(widget.onPressed);
                },
                onLongPress: widget.onLongPress == null
                    ? null
                    : () => _activate(widget.onLongPress),
                child: AnimatedScale(
                  scale: _focused ? widget.focusScale : 1,
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    decoration: BoxDecoration(
                      borderRadius: widget.borderRadius,
                      border: Border.all(
                        color: _focused
                            ? AppColors.accentBright
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: widget.borderRadius,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
