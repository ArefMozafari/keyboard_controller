import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'chat_scroll_controller.dart';
import 'chat_scroll_physics.dart';
import 'keyboard_dismiss_region.dart';
import 'keyboard_lift_behavior.dart';
import 'keyboard_scope.dart';
import 'keyboard_sticky_view.dart';

/// A chat screen body: a message list with the newest message at the bottom and a composer that
/// rides the keyboard.
///
/// The list stays still while the keyboard opens, closes or is dragged away, follows the newest
/// message while it grows, and never moves what the user is reading when messages arrive.
///
/// Place it in a `Scaffold` with `resizeToAvoidBottomInset: false`; this widget handles the
/// keyboard inset itself. A [KeyboardScope] must sit above it.
class KeyboardChatView extends StatefulWidget {
  /// Creates a chat view.
  const KeyboardChatView({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemKey,
    required this.composer,
    this.liftBehavior = KeyboardLiftBehavior.always,
    this.interactiveDismiss = true,
  });

  /// Reports the end state and drives jump-to-latest and pin-to-top.
  final ChatScrollController controller;

  /// The number of messages.
  final int itemCount;

  /// Builds the message at [index]; index 0 is the newest message.
  final IndexedWidgetBuilder itemBuilder;

  /// Returns a stable identity for the message at [index], such as its id.
  ///
  /// Keys let the view keep the reading position and the pinned prompt when messages are
  /// inserted.
  final Object Function(int index) itemKey;

  /// The input bar that rides on top of the keyboard.
  final Widget composer;

  /// How the list moves when the keyboard opens or closes.
  final KeyboardLiftBehavior liftBehavior;

  /// Whether a drag in the list can pull the keyboard away.
  final bool interactiveDismiss;

  @override
  State<KeyboardChatView> createState() => _KeyboardChatViewState();
}

class _KeyboardChatViewState extends State<KeyboardChatView> {
  /// Marks an anchor that puts every message in the newer sliver, used while the chat has fewer
  /// than two messages, such as a new AI chat.
  static const Object _noOlderItems = Object();

  final ChatScrollState _scrollState = ChatScrollState();
  final ValueNotifier<double> _padding = ValueNotifier<double>(0);
  final ValueNotifier<double> _composerHeight = ValueNotifier<double>(0);
  final Key _centerKey = UniqueKey();
  KeyboardController? _keyboard;
  FlutterView? _view;
  double _safeBottom = 0;
  double _keyboardPadding = 0;
  Object? _anchorKey;
  Object? _anchorFallbackKey;
  Object? _pendingPin;
  Object? _pinnedKey;
  final _PinTracker _pinTracker = _PinTracker();
  bool _liftResetScheduled = false;
  bool _pinActive = false;
  bool _insetCheckScheduled = false;
  bool _composerMeasured = false;
  Map<Object, int>? _indexByKey;

  @override
  void initState() {
    super.initState();
    widget.controller.onPinRequest = _handlePinRequest;
    _composerHeight.addListener(_updatePadding);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboard = KeyboardScope.of(context);
    if (keyboard != _keyboard) {
      _keyboard?.height.removeListener(_handleKeyboardHeight);
      _keyboard?.interactiveDismissSupported.removeListener(_handleSupportChange);
      _keyboard =
          keyboard
            ..height.addListener(_handleKeyboardHeight)
            ..interactiveDismissSupported.addListener(_handleSupportChange);
      _scrollState.held = () => keyboard.gestureHeld;
    }
  }

  void _handleSupportChange() => setState(() {});

  @override
  void didUpdateWidget(KeyboardChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.onPinRequest = null;
      widget.controller.onPinRequest = _handlePinRequest;
    }
    if (oldWidget.liftBehavior != widget.liftBehavior) _handleKeyboardHeight();
  }

  @override
  void dispose() {
    _keyboard?.height.removeListener(_handleKeyboardHeight);
    _keyboard?.interactiveDismissSupported.removeListener(_handleSupportChange);
    if (widget.controller.onPinRequest == _handlePinRequest) widget.controller.onPinRequest = null;
    _composerHeight.dispose();
    _padding.dispose();
    super.dispose();
  }

  void _handlePinRequest() => setState(() {});

  bool _liftsInHistory(double delta) {
    return widget.liftBehavior == KeyboardLiftBehavior.always ||
        (widget.liftBehavior == KeyboardLiftBehavior.persistent && delta > 0);
  }

  // A lift only means something in the layout right after it; one that changed no extents (the
  // pin's blank space absorbed it) must not fire on some later, unrelated change.
  void _addPendingLift(double delta) {
    _scrollState.pendingLift += delta;
    if (_liftResetScheduled) return;
    _liftResetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _liftResetScheduled = false;
      _scrollState.pendingLift = 0;
    });
  }

  void _handleComposerHeight(double height) {
    final delta = height - _composerHeight.value;
    if (_composerMeasured && delta != 0 && _liftsInHistory(delta) && !_atEnd) {
      _addPendingLift(delta);
    }
    _composerHeight.value = height;
    if (!_composerMeasured) setState(() => _composerMeasured = true);
  }

  bool get _atEnd {
    final controller = widget.controller;
    if (!controller.hasClients || !controller.position.hasContentDimensions) return true;
    final position = controller.position;
    return position.pixels - position.minScrollExtent <= ChatScrollController.atEndTolerance;
  }

  double get _rawKeyboardPadding {
    return math.max(0, (_keyboard?.height.value ?? 0) - _safeBottom);
  }

  // The sticky view rests the composer above the bottom safe area, so the list pads for both.
  void _updatePadding() {
    _padding.value = _composerHeight.value + _safeBottom + _keyboardPadding;
  }

  void _checkInsetNotConsumed() {
    final view = _view;
    if (!mounted || view == null) return;
    final media = context.getInheritedWidgetOfExactType<MediaQuery>();
    if (media == null) return;
    if (view.viewInsets.bottom > 0 && media.data.viewInsets.bottom == 0) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('KeyboardChatView found the keyboard inset already removed by an ancestor.'),
        ErrorDescription(
          'An ancestor, usually a Scaffold, resized for the keyboard, so the chat view would add '
          'the keyboard height twice.',
        ),
        ErrorHint('Set resizeToAvoidBottomInset: false on the Scaffold around KeyboardChatView.'),
      ]);
    }
  }

  void _handleKeyboardHeight() {
    if (!mounted) return;
    assert(() {
      // MediaQuery catches up with the view one frame later, so compare after that frame.
      if (!_insetCheckScheduled) {
        _insetCheckScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _insetCheckScheduled = false;
          _checkInsetNotConsumed();
        });
      }
      return true;
    }());
    final raw = _rawKeyboardPadding;
    final double next = switch (widget.liftBehavior) {
      KeyboardLiftBehavior.always || KeyboardLiftBehavior.whenAtEnd => raw,
      KeyboardLiftBehavior.persistent => math.max(raw, _keyboardPadding),
      KeyboardLiftBehavior.never => 0,
    };
    final delta = next - _keyboardPadding;
    if (delta == 0) return;
    if (_liftsInHistory(delta) && !_atEnd) _addPendingLift(delta);
    _keyboardPadding = next;
    _updatePadding();
  }

  void _releasePersistentPadding() {
    if (widget.liftBehavior != KeyboardLiftBehavior.persistent) return;
    _keyboardPadding = _rawKeyboardPadding;
    _updatePadding();
  }

  bool _handleScrollStart(ScrollStartNotification notification) {
    // Only the chat list's own scroll counts, not a code block or table scrolling inside a message.
    if (notification.depth == 0 && notification.dragDetails != null) {
      _releasePersistentPadding();
    }
    return false;
  }

  int? _indexOfKey(Object key) {
    for (var index = 0; index < widget.itemCount; index++) {
      if (widget.itemKey(index) == key) return index;
    }
    return null;
  }

  int? _lookupIndex(Key key) {
    if (key is! ValueKey<Object>) return null;
    final indexByKey =
        _indexByKey ??= <Object, int>{
          for (var index = 0; index < widget.itemCount; index++) widget.itemKey(index): index,
        };
    return indexByKey[key.value];
  }

  void _resolvePin() {
    if (widget.controller.takeClearPinRequest()) {
      _pinActive = false;
      _pendingPin = null;
    }
    _pendingPin = widget.controller.takePinRequest() ?? _pendingPin;
    final pinKey = _pendingPin;
    if (pinKey == null) return;
    final pinIndex = _indexOfKey(pinKey);
    // The pinned message may be inserted after pinToTop; wait for it.
    if (pinIndex == null) return;
    _pendingPin = null;
    _pinActive = true;
    // The pinned message stays in whichever sliver it is in; moving it, or the messages around
    // it, to another sliver would rebuild their widget state on every send.
    _pinnedKey = pinKey;
    _scrollState.forceEnd = true;
    _releasePersistentPadding();
  }

  void _dropPinIfGone() {
    final pinnedKey = _pinnedKey;
    if (!_pinActive || pinnedKey == null) return;
    if (_indexOfKey(pinnedKey) == null) _pinActive = false;
  }

  /// Returns how many of the newest messages sit in the newer sliver, below the center.
  int _resolveNewerCount() {
    if (widget.itemCount == 0) {
      // An emptied chat, such as "new chat", must not keep blank space for a pinned prompt.
      _anchorKey = null;
      _pinActive = false;
      return 0;
    }
    final anchor = _anchorKey;
    if (anchor == _noOlderItems) return widget.itemCount;
    if (anchor == null) return _anchorBelowNewest();
    final anchorIndex = _indexOfKey(anchor);
    if (anchorIndex != null) {
      _anchorFallbackKey =
          anchorIndex + 1 < widget.itemCount ? widget.itemKey(anchorIndex + 1) : null;
      return anchorIndex;
    }
    // The anchor message was deleted or re-keyed: hold on to its older neighbour so the reader
    // stays in place, apart from the removed message itself.
    final fallback = _anchorFallbackKey;
    final fallbackIndex = fallback == null ? null : _indexOfKey(fallback);
    if (fallbackIndex != null) {
      _anchorKey = fallback;
      return fallbackIndex;
    }
    // Nothing familiar is left, for example after the list was replaced: start over at the end.
    _pinActive = false;
    _scrollState.forceEnd = true;
    return _anchorBelowNewest();
  }

  // The newest message starts in the newer sliver, so its growth (a streaming answer, a loading
  // preview) extends away from the center and never moves the history above it.
  int _anchorBelowNewest() {
    if (widget.itemCount < 2) {
      _anchorKey = _noOlderItems;
      return widget.itemCount;
    }
    _anchorKey = widget.itemKey(1);
    return 1;
  }

  Widget _buildItem(BuildContext context, int index, {required bool inNewer}) {
    final key = widget.itemKey(index);
    return KeyedSubtree(
      key: ValueKey<Object>(key),
      // Every item carries a marker, so pinning one changes no widget types and keeps state.
      child: _PinMarker(
        tracker: _pinTracker,
        pinned: _pinActive && key == _pinnedKey,
        inNewer: inNewer,
        child: widget.itemBuilder(context, index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    if (safeBottom != _safeBottom) {
      _safeBottom = safeBottom;
      // Padding listeners rebuild slivers, which cannot happen during this build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updatePadding();
      });
    }
    _view = View.of(context);
    _indexByKey = null;
    _resolvePin();
    final newerCount = _resolveNewerCount();
    _dropPinIfGone();
    final nativeDismiss = _keyboard?.interactiveDismissSupported.value ?? false;
    final list = CustomScrollView(
      controller: widget.controller,
      reverse: true,
      // Where the keyboard cannot follow the finger, a drag still dismisses it.
      keyboardDismissBehavior:
          widget.interactiveDismiss && !nativeDismiss
              ? ScrollViewKeyboardDismissBehavior.onDrag
              : ScrollViewKeyboardDismissBehavior.manual,
      center: _centerKey,
      physics: ChatScrollPhysics(state: _scrollState),
      slivers: <Widget>[
        ValueListenableBuilder<double>(
          valueListenable: _padding,
          builder: (context, padding, _) => SliverToBoxAdapter(child: SizedBox(height: padding)),
        ),
        ValueListenableBuilder<double>(
          valueListenable: _padding,
          builder:
              (context, padding, _) =>
                  _BlankSpace(active: _pinActive, padding: padding, tracker: _pinTracker),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, childIndex) =>
                _buildItem(context, newerCount - 1 - childIndex, inNewer: true),
            childCount: newerCount,
            findChildIndexCallback: (key) {
              final index = _lookupIndex(key);
              if (index == null || index >= newerCount) return null;
              return newerCount - 1 - index;
            },
          ),
        ),
        SliverList(
          key: _centerKey,
          delegate: SliverChildBuilderDelegate(
            (context, childIndex) => _buildItem(context, newerCount + childIndex, inNewer: false),
            childCount: widget.itemCount - newerCount,
            findChildIndexCallback: (key) {
              final index = _lookupIndex(key);
              if (index == null || index < newerCount) return null;
              return index - newerCount;
            },
          ),
        ),
        _OlderExtentProbe(state: _scrollState),
      ],
    );
    return Stack(
      children: <Widget>[
        Positioned.fill(
          // The composer height arrives a frame after the first layout; showing the list before
          // then would paint it behind the composer and jump it up a frame later.
          child: Visibility.maintain(
            visible: _composerMeasured,
            child: KeyboardDismissRegion(
              enabled: widget.interactiveDismiss,
              child: NotificationListener<ScrollStartNotification>(
                onNotification: _handleScrollStart,
                child: list,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // The transform must be outermost: a size-checking box outside it would reject taps on
          // the lifted composer, because hit testing would still use its resting position.
          child: KeyboardStickyView(
            child: _HeightReporter(onHeight: _handleComposerHeight, child: widget.composer),
          ),
        ),
      ],
    );
  }
}

/// Reports its child's height after layout, one frame later, so the list can pad for it.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderHeightReporter renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}

/// Records how tall the history above the center is, so scrolling can stop at the oldest message.
///
/// The viewport never lets the scroll offset pass 0 on the history side, which leaves up to a
/// screen of empty space above the oldest message when the history is shorter than the screen.
class _OlderExtentProbe extends LeafRenderObjectWidget {
  const _OlderExtentProbe({required this.state});

  final ChatScrollState state;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOlderExtentProbe(state);

  @override
  void updateRenderObject(BuildContext context, _RenderOlderExtentProbe renderObject) {
    renderObject.state = state;
  }
}

class _RenderOlderExtentProbe extends RenderSliver {
  _RenderOlderExtentProbe(this.state);

  ChatScrollState state;

  @override
  void performLayout() {
    // Laid out right after the history list, so this is the history's total height.
    state.olderExtent = constraints.precedingScrollExtent;
    geometry = SliverGeometry.zero;
  }
}

/// Connects the pinned message's marker with the blank space that keeps it at the top.
class _PinTracker {
  _RenderPinMarker? marker;
  _RenderBlankSpace? blankSpace;
}

/// Wraps every message; the pinned one tells the blank space where it sits.
class _PinMarker extends SingleChildRenderObjectWidget {
  const _PinMarker({
    required this.tracker,
    required this.pinned,
    required this.inNewer,
    required super.child,
  });

  final _PinTracker tracker;
  final bool pinned;
  final bool inNewer;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPinMarker(tracker: tracker, pinned: pinned, inNewer: inNewer);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderPinMarker renderObject) {
    renderObject
      ..inNewer = inNewer
      ..pinned = pinned;
  }
}

class _RenderPinMarker extends RenderProxyBox {
  _RenderPinMarker({required this.tracker, required bool pinned, required this.inNewer})
    : _pinned = pinned;

  final _PinTracker tracker;

  /// Whether the marker sits in the newer sliver rather than the history.
  bool inNewer;

  /// The height from the last layout, readable by the blank space without a size dependency.
  double lastHeight = 0;

  bool _pinned;
  set pinned(bool value) {
    if (value == _pinned) return;
    _pinned = value;
    _register();
  }

  void _register() {
    if (_pinned && attached) {
      tracker.marker = this;
    } else if (tracker.marker == this) {
      tracker.marker = null;
    }
    tracker.blankSpace?.markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_pinned) _register();
  }

  @override
  void detach() {
    super.detach();
    if (tracker.marker == this) tracker.marker = null;
  }

  @override
  void performLayout() {
    super.performLayout();
    lastHeight = size.height;
  }
}

/// Empty space below a pinned prompt, sized so the prompt sits at the top of the visible area.
class _BlankSpace extends LeafRenderObjectWidget {
  const _BlankSpace({required this.active, required this.padding, required this.tracker});

  final bool active;
  final double padding;
  final _PinTracker tracker;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderBlankSpace(active: active, padding: padding, tracker: tracker);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderBlankSpace renderObject) {
    renderObject
      ..active = active
      ..padding = padding;
  }
}

class _RenderBlankSpace extends RenderSliver {
  _RenderBlankSpace({required bool active, required double padding, required this.tracker})
    : _active = active,
      _padding = padding;

  final _PinTracker tracker;

  bool _active;
  set active(bool value) {
    if (value == _active) return;
    _active = value;
    markNeedsLayout();
  }

  double _padding;
  set padding(double value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    tracker.blankSpace = this;
  }

  @override
  void detach() {
    if (tracker.blankSpace == this) tracker.blankSpace = null;
    super.detach();
  }

  /// The height from the pinned message's top down to the newest message's bottom, or null when
  /// the pinned message is not laid out (scrolled far away, so no blank space is visible anyway).
  double? _pinnedToNewest() {
    final marker = tracker.marker;
    if (marker == null) return null;
    // SliverList wraps each item in keep-alive and repaint boxes; find the sliver's own child,
    // which shares the marker's position and height.
    RenderObject sliverChild = marker;
    while (sliverChild.parent is! RenderSliverMultiBoxAdaptor) {
      final parent = sliverChild.parent;
      if (parent == null) return null;
      sliverChild = parent;
    }
    final sliver = sliverChild.parent! as RenderSliverMultiBoxAdaptor;
    final offsetInSliver = sliver.childScrollOffset(sliverChild);
    if (offsetInSliver == null) return null;
    // This sliver is laid out after the newer messages, so precedingScrollExtent is their total
    // height. A pinned message among them is measured from the center side; one in the history
    // adds the history between the center and itself.
    final newerExtent = constraints.precedingScrollExtent;
    if (marker.inNewer) return newerExtent - offsetInSliver;
    return newerExtent + offsetInSliver + marker.lastHeight;
  }

  @override
  void performLayout() {
    final pinnedToNewest = _active ? _pinnedToNewest() : null;
    final extent =
        pinnedToNewest == null
            ? 0.0
            : math.max(0.0, constraints.viewportMainAxisExtent - _padding - pinnedToNewest);
    final paintExtent = calculatePaintOffset(constraints, from: 0, to: extent);
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: paintExtent,
      maxPaintExtent: extent,
      hitTestExtent: paintExtent,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {}
}
