import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'keyboard_scope.dart';

/// Stops a scrollable from moving while a gesture drags the keyboard, including the release fling.
///
/// Shared by the package's physics; [isHeld] says whether the current gesture owns the keyboard.
@internal
mixin KeyboardHold on ScrollPhysics {
  /// Whether the current gesture moves the keyboard instead of the list.
  bool get isHeld;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (isHeld) return 0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if (isHeld) {
      // Still settle an overscroll back into range, but never fling.
      return position.outOfRange ? super.createBallisticSimulation(position, 0) : null;
    }
    return super.createBallisticSimulation(position, velocity);
  }
}

/// Scroll physics for your own scrollable inside a `KeyboardDismissRegion`: the list stays still
/// while the keyboard follows the finger, as `KeyboardChatView` does for its list.
///
/// ```dart
/// KeyboardDismissRegion(
///   child: ListView(
///     physics: KeyboardHoldScrollPhysics(keyboard: KeyboardScope.of(context)),
///     children: messages,
///   ),
/// )
/// ```
class KeyboardHoldScrollPhysics extends ScrollPhysics with KeyboardHold {
  /// Creates physics that hold still while [keyboard] is being dragged.
  const KeyboardHoldScrollPhysics({required this.keyboard, super.parent});

  /// The keyboard state from the enclosing `KeyboardScope`.
  final KeyboardController keyboard;

  @override
  bool get isHeld => keyboard.gestureHeld;

  @override
  KeyboardHoldScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return KeyboardHoldScrollPhysics(keyboard: keyboard, parent: buildParent(ancestor));
  }
}
