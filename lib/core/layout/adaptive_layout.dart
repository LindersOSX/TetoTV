import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The native Android device category. Tests default to television so the
/// established 10-foot focus and sizing behavior remains deterministic.
final isTelevisionProvider = Provider<bool>((_) => true);

extension AdaptiveLayoutContext on BuildContext {
  bool get isCompactWidth => MediaQuery.sizeOf(this).width < 600;

  bool get isMediumWidth {
    final width = MediaQuery.sizeOf(this).width;
    return width >= 600 && width < 1000;
  }

  EdgeInsets get responsiveScreenPadding {
    final width = MediaQuery.sizeOf(this).width;
    if (width < 600) return const EdgeInsets.fromLTRB(16, 12, 16, 18);
    if (width < 1000) return const EdgeInsets.fromLTRB(24, 18, 24, 24);
    return const EdgeInsets.fromLTRB(34, 24, 34, 28);
  }
}
