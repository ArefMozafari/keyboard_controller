import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'keyboard_model.dart';
import 'keyboard_phase.dart';
import 'keyboard_scope.dart';

/// Lets a finger dragging down inside [child] pull the keyboard away, and back up.
///
/// The keyboard starts following once the finger reaches its top edge. On iOS 15+ UIKit moves the
/// real keyboard; on Android API 30+ this widget drives it through the platform's inset control.
/// Elsewhere it does nothing.
class KeyboardDismissRegion extends StatefulWidget {
  /// Creates a region that enables interactive dismiss for drags inside [child].
  const KeyboardDismissRegion({super.key, required this.child, this.enabled = true});

  /// The area that accepts dismiss drags, usually a scrolling list.
  final Widget child;

  /// Whether drags in this region may move the keyboard.
  final bool enabled;

  @override
  State<KeyboardDismissRegion> createState() => _KeyboardDismissRegionState();
}

class _KeyboardDismissRegionState extends State<KeyboardDismissRegion> {
  /// Release speed in logical pixels per second that decides open or closed by direction alone.
  static const double flingVelocity = 700;

  /// How long the keyboard takes to settle after an Android release.
  static const Duration settleDuration = Duration(milliseconds: 250);

  /// How long a stray 0 inset is ignored after Android finishes control with the keyboard shown.
  static const Duration finishGuard = Duration(milliseconds: 100);

  static int _nextRegionId = 0;

  final int _regionId = _nextRegionId++;
  late KeyboardController _keyboard;
  Rect? _reportedRect;
  int? _activePointer;
  VelocityTracker? _velocityTracker;
  bool _startingControl = false;
  bool _controlling = false;
  bool _releasing = false;
  bool _controlDenied = false;
  bool _routeIsCurrent = true;
  double _shownHeight = 0;
  double _inset = 0;

  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboard = KeyboardScope.of(context);
    // A route pushed on top must not inherit this area's dismiss behaviour on iOS.
    final routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (routeIsCurrent == _routeIsCurrent) return;
    _routeIsCurrent = routeIsCurrent;
    if (!routeIsCurrent) {
      _removeRegion();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportCurrentRect());
    }
  }

  @override
  void didUpdateWidget(KeyboardDismissRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _removeRegion();
  }

  @override
  void dispose() {
    _removeRegion();
    // A region removed mid-drag, for example by a route pop, must hand the keyboard back.
    if (_controlling && !_releasing) {
      _controlling = false;
      _keyboard.platform.finishControl(show: true);
      _keyboard.model.endInteractive(target: _shownHeight);
      _keyboard.model.guardAfterFinish(finishGuard);
    }
    if (_keyboard.platform.onControlEnded == _handleControlEnded) {
      _keyboard.platform.onControlEnded = null;
    }
    super.dispose();
  }

  void _removeRegion() {
    if (_reportedRect == null) return;
    _reportedRect = null;
    _keyboard.platform.removeRegion(_regionId);
  }

  void _reportRect(Rect rect) {
    if (!_isIos || !widget.enabled || !_routeIsCurrent || rect == _reportedRect) return;
    _reportedRect = rect;
    _keyboard.platform.setRegion(_regionId, rect);
  }

  void _reportCurrentRect() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      _reportRect(box.localToGlobal(Offset.zero) & box.size);
    }
  }

  // The system can take the keyboard back mid-drag, for example when focus moves; end the drag
  // where the keyboard really is instead of guessing.
  void _handleControlEnded() {
    if (!mounted || !_controlling || _releasing) return;
    _controlling = false;
    final view = View.of(context);
    _keyboard.model.endInteractive(target: view.viewInsets.bottom / view.devicePixelRatio);
  }

  void _handlePointerDown(PointerDownEvent event) {
    // Transforms such as route slides move the region without a layout, so refresh the rect
    // before UIKit's pan decides whether to begin, which only happens after some movement.
    _reportCurrentRect();
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _controlDenied = false;
    _keyboard.gestureHeld = false;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  bool _keyboardRestsOpen() {
    final model = _keyboard.model;
    return model.height.value > KeyboardModel.heightTolerance &&
        model.phase.value != KeyboardPhase.dragging;
  }

  void _applyInset(double inset) {
    _inset = inset;
    _keyboard.platform.setControlledInset(inset);
    _keyboard.model.applyInteractive(inset);
  }

  Future<void> _startControl() async {
    _startingControl = true;
    final shown = await _keyboard.platform.startControl();
    _startingControl = false;
    if (!mounted) {
      if (shown != null) _keyboard.platform.finishControl(show: true);
      return;
    }
    if (shown == null) {
      // Do not ask again on every move of this gesture.
      _controlDenied = true;
      return;
    }
    _shownHeight = shown;
    _inset = _keyboard.height.value;
    _controlling = true;
    _keyboard.platform.onControlEnded = _handleControlEnded;
    _keyboard.model.beginInteractive();
    _keyboard.gestureHeld = true;
    // The finger lifted while control was being set up: leave the keyboard where it was.
    if (_activePointer == null) _release(show: true);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || !_isAndroid || !widget.enabled) return;
    // The release animation owns the keyboard until it finishes.
    if (_releasing) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (!_controlling) {
      // Below API 30 control is never granted, so do not ask on every move.
      if (!_keyboard.interactiveDismissSupported.value) return;
      if (_startingControl || _controlDenied || !_keyboardRestsOpen()) return;
      if (event.position.dy < screenHeight - _keyboard.height.value) return;
      _startControl();
      return;
    }
    _applyInset((screenHeight - event.position.dy).clamp(0.0, _shownHeight));
  }

  void _release({required bool show}) {
    final target = show ? _shownHeight : 0.0;
    _releasing = true;
    _keyboard.runSettle(
      KeyboardSettle(from: _inset, to: target, duration: settleDuration),
      _applyInset,
      () async {
        await _keyboard.platform.finishControl(show: show);
        _controlling = false;
        _releasing = false;
        _keyboard.model.endInteractive(target: target);
        if (show) {
          _keyboard.model.guardAfterFinish(finishGuard);
        } else {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
    );
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    if (!_controlling || _releasing) return;
    final velocity = _velocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0;
    final bool show;
    if (velocity < -flingVelocity) {
      show = true;
    } else if (velocity > flingVelocity) {
      show = false;
    } else {
      show = _inset > _shownHeight / 2;
    }
    _release(show: show);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Drags over empty areas of the region, such as blank space under few messages, count too.
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: _RectReporter(onRect: _reportRect, child: widget.child),
    );
  }
}

/// Reports its global rect after every layout, so iOS knows where dismiss drags may begin.
class _RectReporter extends SingleChildRenderObjectWidget {
  const _RectReporter({required this.onRect, required super.child});

  final ValueChanged<Rect> onRect;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRectReporter(onRect);

  @override
  void updateRenderObject(BuildContext context, _RenderRectReporter renderObject) {
    renderObject.onRect = onRect;
  }
}

class _RenderRectReporter extends RenderProxyBox {
  _RenderRectReporter(this.onRect);

  ValueChanged<Rect> onRect;

  @override
  void performLayout() {
    super.performLayout();
    // The global position is only final once the parent finishes layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!attached) return;
      onRect(localToGlobal(Offset.zero) & size);
    });
  }
}
