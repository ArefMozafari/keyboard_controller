import 'package:flutter/foundation.dart';

import 'keyboard_phase.dart';

/// Returns the current time; injectable so tests control the finish guard.
typedef Clock = DateTime Function();

/// A request to animate the keyboard height from [from] to [to] over [duration].
@immutable
class KeyboardSettle {
  /// Creates a settle request.
  const KeyboardSettle({required this.from, required this.to, required this.duration});

  /// The height the animation starts at, in logical pixels.
  final double from;

  /// The height the animation ends at, in logical pixels.
  final double to;

  /// How long the animation runs.
  final Duration duration;
}

/// Turns engine insets, native keyboard events and drag values into one keyboard state.
///
/// The model is pure: it schedules nothing and owns no ticker, so every rule is unit-testable.
class KeyboardModel {
  /// Creates a model that reads the time from [clock].
  KeyboardModel({Clock? clock}) : _clock = clock ?? DateTime.now;

  /// Heights closer than this are treated as equal, absorbing sub-pixel engine rounding.
  static const double heightTolerance = 0.5;

  final Clock _clock;
  final ValueNotifier<double> _height = ValueNotifier<double>(0);
  final ValueNotifier<double> _targetHeight = ValueNotifier<double>(0);
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  final ValueNotifier<KeyboardPhase> _phase = ValueNotifier<KeyboardPhase>(KeyboardPhase.closed);
  double _openHeight = 0;
  bool _settling = false;
  double _settleTarget = 0;
  bool _hasNativeTarget = false;
  DateTime? _guardUntil;

  /// The visible keyboard height in logical pixels.
  ValueListenable<double> get height => _height;

  /// The height the keyboard is heading to: its open height, or 0 when hiding.
  ValueListenable<double> get targetHeight => _targetHeight;

  /// How open the keyboard is, from 0 (hidden) to 1 (fully open).
  ValueListenable<double> get progress => _progress;

  /// The keyboard's place in its show and hide cycle.
  ValueListenable<KeyboardPhase> get phase => _phase;

  bool get _isDragging => _phase.value == KeyboardPhase.dragging;

  bool _isNear(double first, double second) => (first - second).abs() <= heightTolerance;

  void _setHeight(double value) {
    _height.value = value;
    if (value > _openHeight && _targetHeight.value <= heightTolerance) {
      _openHeight = value;
    }
    _progress.value = _openHeight > 0 ? (value / _openHeight).clamp(0.0, 1.0) : 0;
  }

  void _updatePhase(double previousHeight) {
    final current = _height.value;
    final target = _targetHeight.value;
    if (_isNear(current, target)) {
      _phase.value = target > heightTolerance ? KeyboardPhase.open : KeyboardPhase.closed;
    } else if (current > previousHeight) {
      _phase.value = KeyboardPhase.opening;
    } else if (current < previousHeight) {
      _phase.value = KeyboardPhase.closing;
    }
  }

  bool _insideGuard() {
    final guardUntil = _guardUntil;
    if (guardUntil == null) return false;
    if (_clock().isBefore(guardUntil)) return true;
    _guardUntil = null;
    return false;
  }

  /// Applies the engine's bottom view inset, ignored while a drag or settle owns the height.
  void applyViewInset(double value) {
    if (_isDragging || _settling) return;
    // Android reports one stray 0 between two open values right after a controlled finish.
    if (value == 0 && _insideGuard()) return;
    final previous = _height.value;
    _setHeight(value);
    _updatePhase(previous);
  }

  /// Applies a native "keyboard will change" event.
  ///
  /// Returns a settle request when the event ends a drag, because the platform stops reporting
  /// the keyboard position once the finger lifts.
  KeyboardSettle? applyTarget(double height, Duration duration) {
    _hasNativeTarget = true;
    _targetHeight.value = height;
    if (height > heightTolerance) _openHeight = height;
    // A settle heading elsewhere, for example a dismiss the user reverses by tapping the field
    // again, restarts from where it is instead of finishing at a stale target.
    if (_settling && _isNear(height, _settleTarget)) return null;
    if (_isDragging || _settling) {
      _settling = true;
      _settleTarget = height;
      _phase.value = height > _height.value ? KeyboardPhase.opening : KeyboardPhase.closing;
      return KeyboardSettle(from: _height.value, to: height, duration: duration);
    }
    if (_isNear(_height.value, height)) {
      _phase.value = height > heightTolerance ? KeyboardPhase.open : KeyboardPhase.closed;
    } else {
      _phase.value = height > _height.value ? KeyboardPhase.opening : KeyboardPhase.closing;
    }
    _setHeight(_height.value);
    return null;
  }

  /// Marks the start of a drag that moves the keyboard.
  ///
  /// A drag that grabs the keyboard mid-settle owns the height from now on.
  void beginInteractive() {
    _settling = false;
    _phase.value = KeyboardPhase.dragging;
  }

  /// Applies the keyboard height during a drag.
  void applyInteractive(double height) {
    _setHeight(height);
  }

  /// Ends a drag, settling at [target] when the caller already moved the keyboard there.
  void endInteractive({double? target}) {
    if (!_isDragging) return;
    if (target != null) {
      _targetHeight.value = target;
      if (target > heightTolerance) _openHeight = target;
      _setHeight(target);
    }
    final current = _height.value;
    final settledAt = _targetHeight.value;
    if (_isNear(current, settledAt)) {
      _phase.value = settledAt > heightTolerance ? KeyboardPhase.open : KeyboardPhase.closed;
    } else {
      _phase.value = current < settledAt ? KeyboardPhase.opening : KeyboardPhase.closing;
    }
  }

  /// Applies one frame of a settle animation.
  void applySettleValue(double height) {
    if (!_settling) return;
    _setHeight(height);
  }

  /// Ends a settle animation at the target height.
  void completeSettle() {
    if (!_settling) return;
    _settling = false;
    final previous = _height.value;
    _setHeight(_targetHeight.value);
    _updatePhase(previous);
  }

  /// Treats the current height as the keyboard's resting target.
  ///
  /// Platforms without native events (web, desktop, Android below API 30) never send a target, so
  /// the scope calls this once the inset stops changing. Ignored once a native target arrived.
  void settleWithoutTarget() {
    if (_hasNativeTarget || _isDragging || _settling) return;
    final current = _height.value;
    _targetHeight.value = current;
    if (current > heightTolerance) _openHeight = current;
    _setHeight(current);
    _phase.value = current > heightTolerance ? KeyboardPhase.open : KeyboardPhase.closed;
  }

  /// Ignores a 0 view inset for [guard] after a controlled show finishes.
  void guardAfterFinish(Duration guard) {
    _guardUntil = _clock().add(guard);
  }

  /// Releases the listenables.
  void dispose() {
    _height.dispose();
    _targetHeight.dispose();
    _progress.dispose();
    _phase.dispose();
  }
}
