import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'keyboard_model.dart';
import 'keyboard_phase.dart';
import 'keyboard_platform.dart';

/// The keyboard state shared by every keyboard-aware widget under a [KeyboardScope].
class KeyboardController {
  KeyboardController._(this._model, this._platform, this._runSettle);

  final KeyboardModel _model;
  final KeyboardPlatform _platform;
  final void Function(KeyboardSettle settle, ValueChanged<double> onValue, VoidCallback onDone)
  _runSettle;

  /// The visible keyboard height in logical pixels, updated every frame.
  ValueListenable<double> get height => _model.height;

  /// The height the keyboard is heading to: its open height, or 0 when hiding.
  ValueListenable<double> get targetHeight => _model.targetHeight;

  /// How open the keyboard is, from 0 (hidden) to 1 (fully open).
  ValueListenable<double> get progress => _model.progress;

  /// The keyboard's place in its show and hide cycle.
  ValueListenable<KeyboardPhase> get phase => _model.phase;

  final ValueNotifier<bool> _interactiveDismissSupported = ValueNotifier<bool>(false);

  /// Whether a drag can pull the keyboard away on this device (iOS 15+, Android API 30+).
  ///
  /// False until the native side answers, and on platforms without it.
  ValueListenable<bool> get interactiveDismissSupported => _interactiveDismissSupported;

  /// Whether the current pointer gesture is moving the keyboard, so lists must not scroll.
  ///
  /// Package widgets set it; it stays true until the next pointer down so the release fling of
  /// that gesture is suppressed too.
  @internal
  bool gestureHeld = false;

  /// The state model, for package widgets.
  @internal
  KeyboardModel get model => _model;

  /// The native channel, for package widgets.
  @internal
  KeyboardPlatform get platform => _platform;

  /// Runs [settle] on the scope's ticker, reporting each value to [onValue].
  @internal
  void runSettle(KeyboardSettle settle, ValueChanged<double> onValue, VoidCallback onDone) {
    _runSettle(settle, onValue, onDone);
  }
}

/// Provides keyboard state to keyboard-aware widgets.
///
/// Place one scope above the app's navigator, for example in `MaterialApp.builder`, so every
/// route shares one native connection.
class KeyboardScope extends StatefulWidget {
  /// Creates a scope around [child].
  const KeyboardScope({super.key, required this.child, this.platform});

  /// The widget below this scope.
  final Widget child;

  /// The native channel; tests pass their own.
  final KeyboardPlatform? platform;

  /// Returns the controller of the nearest enclosing scope.
  static KeyboardController of(BuildContext context) {
    final marker = context.getInheritedWidgetOfExactType<_KeyboardScopeMarker>();
    if (marker == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('KeyboardScope.of() was called with a context that has no KeyboardScope.'),
        ErrorHint(
          'Wrap the app in a KeyboardScope, for example: '
          'MaterialApp(builder: (context, child) => KeyboardScope(child: child!)).',
        ),
      ]);
    }
    return marker.controller;
  }

  @override
  State<KeyboardScope> createState() => _KeyboardScopeState();
}

class _KeyboardScopeState extends State<KeyboardScope>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// The settle curve; UIKit's own curve is not observable after a drag ends.
  static const Curve settleCurve = Curves.easeOutCubic;

  final KeyboardModel _model = KeyboardModel();
  late final KeyboardPlatform _platform = widget.platform ?? KeyboardPlatform();
  late final AnimationController _settleAnimation = AnimationController(vsync: this);
  late final KeyboardController _controller = KeyboardController._(_model, _platform, _runSettle);

  /// How long the inset must stay still before a platform without native events counts it as
  /// resting.
  static const Duration restDelay = Duration(milliseconds: 120);

  /// How long to wait after an iOS drag ends for UIKit's target before settling on our own.
  static const Duration releaseTargetWait = Duration(milliseconds: 100);

  /// The settle length used when UIKit sends no target after a drag.
  static const Duration fallbackSettleDuration = Duration(milliseconds: 250);

  VoidCallback? _settleListener;
  int _settleGeneration = 0;
  Timer? _restTimer;
  Timer? _releaseTimer;

  // A superseded or cancelled settle must not run its completion: it would snap the height to a
  // target the user already moved away from.
  void _cancelSettle() {
    _settleGeneration++;
    _settleAnimation.stop();
  }

  void _runSettle(KeyboardSettle settle, ValueChanged<double> onValue, VoidCallback onDone) {
    if (_settleListener != null) _settleAnimation.removeListener(_settleListener!);
    final generation = ++_settleGeneration;
    void listener() {
      final eased = settleCurve.transform(_settleAnimation.value);
      onValue(settle.from + (settle.to - settle.from) * eased);
    }

    _settleListener = listener;
    _settleAnimation
      ..duration = settle.duration
      ..addListener(listener);
    _settleAnimation.forward(from: 0).whenCompleteOrCancel(() {
      _settleAnimation.removeListener(listener);
      if (_settleListener == listener) _settleListener = null;
      if (generation == _settleGeneration) onDone();
    });
  }

  double get _viewInset {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  void _readViewInset() {
    if (!mounted) return;
    _model.applyViewInset(_viewInset);
    // Without native events the phase only settles once the inset stops changing.
    _restTimer?.cancel();
    _restTimer = Timer(restDelay, _model.settleWithoutTarget);
  }

  void _startSettle(KeyboardSettle settle) {
    _runSettle(settle, _model.applySettleValue, () {
      _model.completeSettle();
      // A drag that ends hidden leaves the field focused on both platforms; release it so the
      // next tap opens the keyboard again. A settle retargeted to open keeps the focus.
      if (_model.targetHeight.value <= KeyboardModel.heightTolerance) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _handleWillChange(double height, Duration duration) {
    _releaseTimer?.cancel();
    final settle = _model.applyTarget(height, duration);
    if (settle != null) _startSettle(settle);
  }

  void _handleInteractive(double height) {
    _releaseTimer?.cancel();
    if (_model.phase.value != KeyboardPhase.dragging) {
      if (_settleAnimation.isAnimating) _cancelSettle();
      _model.beginInteractive();
    }
    _controller.gestureHeld = true;
    _model.applyInteractive(height);
  }

  // The finger lifting and UIKit's will-change notification are separate events. Wait briefly for
  // the target; if none comes, settle to wherever the engine says the keyboard is.
  void _handleInteractiveEnd() {
    if (_model.phase.value != KeyboardPhase.dragging) return;
    _releaseTimer?.cancel();
    _releaseTimer = Timer(releaseTargetWait, () {
      if (!mounted || _model.phase.value != KeyboardPhase.dragging) return;
      final settle = _model.applyTarget(_viewInset, fallbackSettleDuration);
      if (settle != null) _startSettle(settle);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platform
      ..onWillChange = _handleWillChange
      ..onInteractive = _handleInteractive
      ..onInteractiveEnd = _handleInteractiveEnd;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _platform.install().then((supported) {
        if (mounted) _controller._interactiveDismissSupported.value = supported;
      });
      _readViewInset();
    });
  }

  @override
  void didChangeMetrics() => _readViewInset();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restTimer?.cancel();
    _releaseTimer?.cancel();
    // Stopping the ticker below fires the settle's completion; it must not reach disposed state.
    _cancelSettle();
    _platform.dispose();
    _settleAnimation.dispose();
    _model.dispose();
    _controller._interactiveDismissSupported.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _KeyboardScopeMarker(controller: _controller, child: widget.child);
  }
}

class _KeyboardScopeMarker extends InheritedWidget {
  const _KeyboardScopeMarker({required this.controller, required super.child});

  final KeyboardController controller;

  @override
  bool updateShouldNotify(_KeyboardScopeMarker oldWidget) => false;
}
