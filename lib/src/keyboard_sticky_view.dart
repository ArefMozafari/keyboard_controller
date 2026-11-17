import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'keyboard_scope.dart';

/// Keeps [child] sitting on top of the keyboard, following it every frame.
///
/// While the keyboard is hidden the child rests above the bottom safe area. The child is moved
/// with a transform, so following the keyboard costs no layout.
class KeyboardStickyView extends StatelessWidget {
  /// Creates a view that rides the keyboard.
  const KeyboardStickyView({super.key, required this.child});

  /// The widget that rides the keyboard, usually a message composer.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = KeyboardScope.of(context);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return ValueListenableBuilder<double>(
      valueListenable: keyboard.height,
      builder: (context, height, child) {
        return Transform.translate(
          offset: Offset(0, -math.max(0.0, height - safeBottom)),
          child: child,
        );
      },
      child: Padding(padding: EdgeInsets.only(bottom: safeBottom), child: child),
    );
  }
}
