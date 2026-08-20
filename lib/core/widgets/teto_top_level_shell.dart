import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/features/home/presentation/main_navigation_bar.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

typedef TetoTopLevelBuilder =
    Widget Function(BuildContext context, TetoTopLevelLayout layout);

/// Layout information shared with a top-level destination's content.
@immutable
class TetoTopLevelLayout {
  const TetoTopLevelLayout({
    required this.usesTvRail,
    required this.contentPadding,
    required this.focusRail,
  });

  final bool usesTvRail;
  final EdgeInsets contentPadding;
  final VoidCallback focusRail;
}

/// The shared cinematic frame for Home-adjacent destinations.
///
/// Expanded TV layouts reuse Home's icon rail and profile switcher. Compact
/// layouts keep their existing page navigation and receive only the common
/// dark, theme-aware backdrop. The destination owns its content and focus
/// graph, so this wrapper does not change its data or behavior.
class TetoTopLevelShell extends StatefulWidget {
  const TetoTopLevelShell({
    required this.preferences,
    required this.activeDestination,
    required this.firstContentFocusNode,
    required this.builder,
    this.autofocusRail = false,
    this.onActiveDestinationPressed,
    this.resizeToAvoidBottomInset = true,
    super.key,
  });

  final SettingsPreferences preferences;
  final TopNavigationDestination activeDestination;
  final FocusNode firstContentFocusNode;
  final TetoTopLevelBuilder builder;
  final bool autofocusRail;
  final VoidCallback? onActiveDestinationPressed;
  final bool resizeToAvoidBottomInset;

  @override
  State<TetoTopLevelShell> createState() => _TetoTopLevelShellState();
}

class _TetoTopLevelShellState extends State<TetoTopLevelShell> {
  final _railFocusNode = FocusNode(debugLabel: 'top-level.active-navigation');
  final _profileFocusNode = FocusNode(debugLabel: 'top-level.profile');

  @override
  void dispose() {
    _railFocusNode.dispose();
    _profileFocusNode.dispose();
    super.dispose();
  }

  void _focusRail() {
    if (_railFocusNode.context != null) {
      _railFocusNode.requestFocus();
    } else if (_profileFocusNode.context != null) {
      // Settings may live under the profile menu while every optional rail
      // destination is disabled. The profile remains a deterministic escape
      // target instead of leaving LEFT trapped in Settings content.
      _profileFocusNode.requestFocus();
    }
  }

  void _focusContent() {
    if (widget.firstContentFocusNode.context != null) {
      widget.firstContentFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final usesTvRail = !context.isCompactWidth && size.width >= 840;
    final railWidth = homeNavigationRailWidth(
      size.width,
      widget.preferences.navigationChromeSize,
    );
    final responsive = context.responsiveScreenPadding;
    final safeAreaMinimum = usesTvRail
        ? EdgeInsets.zero
        : responsive.copyWith(top: 0, bottom: 0);
    final contentPadding = usesTvRail
        ? EdgeInsets.fromLTRB(
            size.width >= 1400 ? 34 : 28,
            68,
            size.width >= 1400 ? 34 : 28,
            24,
          )
        : EdgeInsets.zero;
    final layout = TetoTopLevelLayout(
      usesTvRail: usesTvRail,
      contentPadding: contentPadding,
      focusRail: _focusRail,
    );

    final canPop = Navigator.of(context).canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) GoRouter.maybeOf(context)?.go('/');
      },
      child: Scaffold(
        key: ValueKey('teto-top-level-${widget.activeDestination.name}'),
        resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
        backgroundColor: context.appPalette.background,
        body: SafeArea(
          minimum: safeAreaMinimum,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(child: _TetoDestinationBackdrop()),
              if (usesTvRail) ...[
                Positioned.fill(
                  left: railWidth,
                  child: Padding(
                    padding: contentPadding,
                    child: widget.builder(context, layout),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: HomeSideNavigation(
                    preferences: widget.preferences,
                    activeDestination: widget.activeDestination,
                    activeFocusNode: _railFocusNode,
                    autofocusActive: widget.autofocusRail,
                    onActivePressed: widget.onActiveDestinationPressed ?? () {},
                    onExitRight: _focusContent,
                    width: railWidth,
                  ),
                ),
                Positioned(
                  right: size.width >= 1400 ? 30 : 22,
                  top: 12,
                  child: RepaintBoundary(
                    key: const ValueKey('top-level-fixed-profile'),
                    child: HomeProfileSwitcher(
                      preferences: widget.preferences,
                      focusNode: _profileFocusNode,
                      onKeyEvent: (_, event) {
                        final returnsToContent =
                            event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                            event.logicalKey == LogicalKeyboardKey.arrowDown;
                        if (!returnsToContent) return KeyEventResult.ignored;
                        if (event is KeyDownEvent || event is KeyRepeatEvent) {
                          _focusContent();
                        }
                        return KeyEventResult.handled;
                      },
                    ),
                  ),
                ),
              ] else
                Padding(
                  padding: contentPadding,
                  child: widget.builder(context, layout),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TetoDestinationBackdrop extends StatelessWidget {
  const _TetoDestinationBackdrop();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return IgnorePointer(
      child: DecoratedBox(
        key: const ValueKey('teto-top-level-backdrop'),
        decoration: BoxDecoration(
          color: palette.background,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black,
              palette.background,
              Color.alphaBlend(
                palette.accent.withValues(alpha: .055),
                palette.background,
              ),
            ],
            stops: const [0, .58, 1],
          ),
        ),
      ),
    );
  }
}
