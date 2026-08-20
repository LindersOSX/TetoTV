import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Repeat-aware directional input gate for TV remotes.
///
/// Some Android TV firmwares emit held D-pad input as [KeyRepeatEvent] while
/// others emit a run of [KeyDownEvent] packets. Tracking the physical key until
/// key-up keeps both shapes predictable and lets callers consume every packet
/// without accidentally falling through to Flutter's generic traversal.
class TvDirectionalRepeatGate {
  TvDirectionalRepeatGate({
    this.repeatInterval = const Duration(milliseconds: 72),
  });

  final Duration repeatInterval;
  PhysicalKeyboardKey? _pressedKey;
  DateTime? _lastAcceptedAt;

  bool accept(KeyEvent event) {
    if (event is KeyUpEvent) {
      if (_pressedKey == event.physicalKey) {
        _pressedKey = null;
        _lastAcceptedAt = null;
      }
      return false;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final now = DateTime.now();
    final held = event is KeyRepeatEvent || _pressedKey == event.physicalKey;
    _pressedKey = event.physicalKey;
    if (held &&
        _lastAcceptedAt != null &&
        now.difference(_lastAcceptedAt!) < repeatInterval) {
      return false;
    }
    _lastAcceptedAt = now;
    return true;
  }

  void reset() {
    _pressedKey = null;
    _lastAcceptedAt = null;
  }
}

/// Owns real focus nodes and interruptible horizontal scrolling for one shelf.
///
/// A shelf remembers its selected column, so vertical movement and route pops
/// can return to the exact card the viewer last used. New scroll requests call
/// [ScrollController.animateTo] again, which cancels the prior animation; rapid
/// or held remote input therefore never queues a long chain of stale scrolls.
class TvShelfFocusController {
  TvShelfFocusController({
    required this.debugLabel,
    int itemCount = 0,
    ScrollController? scrollController,
  }) : scrollController = scrollController ?? ScrollController() {
    syncItemCount(itemCount);
  }

  final String debugLabel;
  final ScrollController scrollController;
  final TvDirectionalRepeatGate _horizontalGate = TvDirectionalRepeatGate();
  final List<FocusNode> _focusNodes = <FocusNode>[];
  int _selectedIndex = 0;
  bool _disposed = false;

  int get itemCount => _focusNodes.length;
  int get selectedIndex =>
      itemCount == 0 ? 0 : _selectedIndex.clamp(0, itemCount - 1);

  FocusNode focusNodeAt(int index) => _focusNodes[index];

  void syncItemCount(int count) {
    assert(count >= 0);
    if (_disposed) return;
    while (_focusNodes.length < count) {
      _focusNodes.add(
        FocusNode(debugLabel: '$debugLabel.item.${_focusNodes.length}'),
      );
    }
    while (_focusNodes.length > count) {
      _focusNodes.removeLast().dispose();
    }
    if (count == 0) {
      _selectedIndex = 0;
    } else {
      _selectedIndex = _selectedIndex.clamp(0, count - 1);
    }
  }

  void rememberIndex(int index) {
    if (itemCount == 0) return;
    _selectedIndex = index.clamp(0, itemCount - 1);
  }

  /// Requests the remembered card, or the closest valid preferred column.
  /// Returns false when the shelf is empty.
  bool requestFocus({int? preferredIndex}) {
    if (_disposed || itemCount == 0) return false;
    final index = (preferredIndex ?? _selectedIndex).clamp(0, itemCount - 1);
    _selectedIndex = index;
    final node = _focusNodes[index];
    if (node.context != null) {
      node.requestFocus();
      return true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && node.context != null) node.requestFocus();
    });
    return true;
  }

  /// Handles LEFT/RIGHT for a card and consumes every horizontal key packet.
  /// Edge callbacks make navigation into the side rail explicit.
  KeyEventResult handleHorizontalKey(
    KeyEvent event, {
    required int currentIndex,
    required double itemExtent,
    required double spacing,
    VoidCallback? onLeftEdge,
    VoidCallback? onRightEdge,
  }) {
    final logicalKey = event.logicalKey;
    final direction = switch (logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (direction == 0) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      _horizontalGate.accept(event);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }

    final accepted = _horizontalGate.accept(event);
    if (!accepted) return KeyEventResult.handled;
    final nextIndex = currentIndex + direction;
    if (nextIndex < 0) {
      onLeftEdge?.call();
      return KeyEventResult.handled;
    }
    if (nextIndex >= itemCount) {
      onRightEdge?.call();
      return KeyEventResult.handled;
    }

    _selectedIndex = nextIndex;
    _focusNodes[nextIndex].requestFocus();
    reveal(
      index: nextIndex,
      itemExtent: itemExtent,
      spacing: spacing,
      rapid: event is KeyRepeatEvent,
    );
    return KeyEventResult.handled;
  }

  void reveal({
    required int index,
    required double itemExtent,
    required double spacing,
    bool rapid = false,
    double edgePadding = 18,
  }) {
    if (_disposed || !scrollController.hasClients || itemCount == 0) return;
    final position = scrollController.position;
    if (!position.hasContentDimensions || position.viewportDimension <= 0) {
      return;
    }
    final safeIndex = index.clamp(0, itemCount - 1);
    final pitch = itemExtent + spacing;
    final itemStart = safeIndex * pitch;
    final itemEnd = itemStart + itemExtent;
    final leading = position.pixels + edgePadding;
    final trailing = position.pixels + position.viewportDimension - edgePadding;
    double? target;
    if (itemStart < leading) {
      target = itemStart - edgePadding;
    } else if (itemEnd > trailing) {
      target = itemEnd - position.viewportDimension + edgePadding;
    }
    if (target == null) return;
    final bounded = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((bounded - position.pixels).abs() < 1) return;
    unawaited(
      scrollController.animateTo(
        bounded,
        duration: rapid
            ? const Duration(milliseconds: 88)
            : const Duration(milliseconds: 165),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _horizontalGate.reset();
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    scrollController.dispose();
  }
}
