import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Maps the Android TV remote's center button to Flutter's standard activate
/// action. Arrow keys continue to use Flutter's directional focus traversal.
class TvShortcuts extends StatelessWidget {
  const TvShortcuts({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
            onInvoke: _moveFocusOrScroll,
          ),
        },
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: child,
        ),
      ),
    );
  }
}

Object? _moveFocusOrScroll(DirectionalFocusIntent intent) {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null) return null;

  // Flutter's default policy favors secondary-axis overlap. In an irregular
  // TV layout this can skip a nearer control and land an entire row below it.
  // Prefer the closest mounted control in the requested half-plane, using the
  // requested axis as the primary distance and the other axis only to break
  // ties. This makes D-pad movement predictable across mixed rows and stacks.
  final spatialTarget = _nearestDirectionalTarget(focus, intent.direction);
  if (spatialTarget != null) {
    spatialTarget.requestFocus();
    final targetContext = spatialTarget.context;
    if (targetContext != null) {
      unawaited(
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 150),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    }
    return null;
  }

  final context = focus.context;
  if (context == null) return null;
  final vertical =
      intent.direction == TraversalDirection.up ||
      intent.direction == TraversalDirection.down;
  final scrollable = Scrollable.maybeOf(
    context,
    axis: vertical ? Axis.vertical : Axis.horizontal,
  );
  if (scrollable == null || !scrollable.position.hasContentDimensions) {
    return null;
  }

  final direction = switch (intent.direction) {
    TraversalDirection.up || TraversalDirection.left => -1.0,
    TraversalDirection.down || TraversalDirection.right => 1.0,
  };
  final position = scrollable.position;
  final target = (position.pixels + direction * position.viewportDimension * .7)
      .clamp(position.minScrollExtent, position.maxScrollExtent);
  if ((target - position.pixels).abs() < 1) return null;

  unawaited(
    position
        .animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (focus.context != null) focus.focusInDirection(intent.direction);
          });
        }),
  );
  return null;
}

FocusNode? _nearestDirectionalTarget(
  FocusNode current,
  TraversalDirection direction,
) {
  final scope = current.nearestScope;
  if (scope == null || current.context == null) return null;

  Rect currentRect;
  try {
    currentRect = current.rect;
  } catch (_) {
    return null;
  }

  FocusNode? best;
  var bestPrimaryDistance = double.infinity;
  var bestSecondaryDistance = double.infinity;
  for (final candidate in scope.traversalDescendants) {
    if (identical(candidate, current) ||
        candidate.context == null ||
        !candidate.canRequestFocus ||
        candidate.skipTraversal) {
      continue;
    }
    Rect candidateRect;
    try {
      candidateRect = candidate.rect;
    } catch (_) {
      continue;
    }
    if (candidateRect.isEmpty) continue;

    final delta = candidateRect.center - currentRect.center;
    final (primary, secondary) = switch (direction) {
      TraversalDirection.up => (-delta.dy, delta.dx.abs()),
      TraversalDirection.down => (delta.dy, delta.dx.abs()),
      TraversalDirection.left => (-delta.dx, delta.dy.abs()),
      TraversalDirection.right => (delta.dx, delta.dy.abs()),
    };
    if (primary <= 1) continue;
    if (primary < bestPrimaryDistance - 1 ||
        ((primary - bestPrimaryDistance).abs() <= 1 &&
            secondary < bestSecondaryDistance)) {
      best = candidate;
      bestPrimaryDistance = primary;
      bestSecondaryDistance = secondary;
    }
  }
  return best;
}
