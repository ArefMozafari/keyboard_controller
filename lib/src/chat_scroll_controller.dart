import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'chat_scroll_physics.dart';

/// Controls a `KeyboardChatView`: reports whether the newest message is in view, scrolls back
/// to it, and pins a sent prompt to the top while its answer streams in.
class ChatScrollController extends ScrollController {
  /// Creates a controller.
  ChatScrollController() {
    addListener(_updateAtEnd);
  }

  /// Distance from the newest end, in logical pixels, that still counts as being at the end.
  static const double atEndTolerance = 8;

  /// How long [animateToLatest] takes.
  static const Duration latestDuration = Duration(milliseconds: 300);

  /// The curve [animateToLatest] uses.
  static const Curve latestCurve = Curves.easeOutCubic;

  final ValueNotifier<bool> _isAtEnd = ValueNotifier<bool>(true);
  Object? _pinRequest;
  bool _clearPinRequest = false;
  bool _disposed = false;

  /// Notified when [pinToTop] or [clearPin] is called; the chat view listens.
  @internal
  VoidCallback? onPinRequest;

  /// Whether the newest message is in view; bind a jump-to-latest button to it.
  ValueListenable<bool> get isAtEnd => _isAtEnd;

  bool get _atEnd {
    if (!hasClients || !position.hasContentDimensions) return true;
    return position.pixels - position.minScrollExtent <= atEndTolerance;
  }

  void _updateAtEnd() {
    // Positions schedule this after layout; the controller may be gone by then.
    if (_disposed) return;
    _isAtEnd.value = _atEnd;
  }

  bool _atEndUpdateScheduled = false;

  // Layout runs every frame while the keyboard moves or an answer streams; one check per frame
  // is enough.
  void _scheduleAtEndUpdate() {
    if (_atEndUpdateScheduled) return;
    _atEndUpdateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _atEndUpdateScheduled = false;
      _updateAtEnd();
    });
  }

  /// Runs the scheduled end update now, for tests.
  @visibleForTesting
  void debugUpdateAtEnd() => _updateAtEnd();

  /// Scrolls to the newest message.
  Future<void> animateToLatest() async {
    if (!hasClients) return;
    await position.animateTo(
      position.minScrollExtent,
      duration: latestDuration,
      curve: latestCurve,
    );
    // Streaming may have moved the end during the animation.
    if (hasClients && !_atEnd) position.jumpTo(position.minScrollExtent);
  }

  /// Pins the item with [key] to the top of the visible area, leaving blank space below it that
  /// shrinks as newer items, such as a streaming answer, grow into it.
  ///
  /// Call it right before or after inserting the item; the view resolves the key on its next
  /// build.
  void pinToTop(Object key) {
    _pinRequest = key;
    _clearPinRequest = false;
    onPinRequest?.call();
  }

  /// Removes the blank space left by [pinToTop].
  void clearPin() {
    _pinRequest = null;
    _clearPinRequest = true;
    onPinRequest?.call();
  }

  /// Returns and forgets the pending pin key.
  @internal
  Object? takePinRequest() {
    final request = _pinRequest;
    _pinRequest = null;
    return request;
  }

  /// Returns and forgets a pending clear request.
  @internal
  bool takeClearPinRequest() {
    final request = _clearPinRequest;
    _clearPinRequest = false;
    return request;
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _ChatScrollPosition(
      controller: this,
      physics: physics,
      context: context,
      oldPosition: oldPosition,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _isAtEnd.dispose();
    super.dispose();
  }
}

/// Starts at the newest end and refreshes [ChatScrollController.isAtEnd] after content changes.
class _ChatScrollPosition extends ScrollPositionWithSingleContext {
  _ChatScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final ChatScrollController controller;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final firstLayout = !hasContentDimensions;
    // The viewport keeps the history-side limit at 0 or more; stop instead where the oldest
    // message meets the top edge, which is below 0 when the history is shorter than the screen.
    final physics = this.physics;
    var historyLimit = maxScrollExtent;
    if (physics is ChatScrollPhysics && hasViewportDimension) {
      final oldestAtTop = physics.state.olderExtent - viewportDimension;
      historyLimit = math.min(maxScrollExtent, math.max(minScrollExtent, oldestAtTop));
    }
    final settled = super.applyContentDimensions(minScrollExtent, historyLimit);
    // The newest end is below the center, so the first frame must start there, not at 0.
    if (firstLayout && pixels != minScrollExtent) {
      correctPixels(minScrollExtent);
      return false;
    }
    controller._scheduleAtEndUpdate();
    return settled;
  }
}
