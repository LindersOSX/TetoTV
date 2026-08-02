import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    required this.child,
    required this.onPressed,
    this.autofocus = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.focusScale = 1.045,
    this.focusNode,
    this.onFocusChanged,
    super.key,
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;
  final BorderRadius borderRadius;
  final double focusScale;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _fallbackFocusNode;
  bool _focused = false;

  FocusNode get _focusNode => widget.focusNode ?? _fallbackFocusNode;

  @override
  void initState() {
    super.initState();
    _fallbackFocusNode = FocusNode(debugLabel: 'TV mouse/D-pad control');
  }

  @override
  void dispose() {
    _fallbackFocusNode.dispose();
    super.dispose();
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
              widget.onPressed();
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
              widget.onPressed();
            },
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
    );
  }
}
