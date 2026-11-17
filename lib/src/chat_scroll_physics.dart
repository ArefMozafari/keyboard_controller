import 'package:flutter/widgets.dart';

import 'chat_scroll_controller.dart';
import 'keyboard_hold_scroll_physics.dart';

/// Mutable state shared between a chat view and its [ChatScrollPhysics].
class ChatScrollState {
  /// How far the next layout should move the content up, in logical pixels.
  double pendingLift = 0;

  /// Whether the next layout should jump to the newest end once.
  bool forceEnd = false;

  /// The height of the history above the center, measured each layout; unbounded until then.
  double olderExtent = double.infinity;

  /// Whether the current gesture moves the keyboard, so the list must not scroll.
  bool Function() held = _neverHeld;

  static bool _neverHeld() => false;
}

/// Scroll physics that keep a reversed, center-anchored chat list where the user expects it.
///
/// At the newest end it follows growth (new messages, streaming tokens, the keyboard). Away from
/// the end it leaves the content still, unless the lift behaviour asks to move it with the
/// keyboard. During a keyboard drag it holds the list.
class ChatScrollPhysics extends ScrollPhysics with KeyboardHold {
  /// Creates physics bound to [state].
  const ChatScrollPhysics({required this.state, super.parent});

  /// The state shared with the chat view.
  final ChatScrollState state;

  @override
  ChatScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ChatScrollPhysics(state: state, parent: buildParent(ancestor));
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final lift = state.pendingLift;
    state.pendingLift = 0;
    if (state.forceEnd) {
      state.forceEnd = false;
      return newPosition.minScrollExtent;
    }
    final distanceFromEnd = oldPosition.pixels - oldPosition.minScrollExtent;
    if (distanceFromEnd <= ChatScrollController.atEndTolerance) {
      return newPosition.minScrollExtent;
    }
    if (lift != 0) return newPosition.pixels - lift;
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }

  @override
  bool get isHeld => state.held();
}
