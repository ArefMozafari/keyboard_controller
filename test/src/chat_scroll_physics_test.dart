import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/src/chat_scroll_physics.dart';

FixedScrollMetrics metrics({required double pixels, required double minScrollExtent}) {
  return FixedScrollMetrics(
    minScrollExtent: minScrollExtent,
    maxScrollExtent: 2000,
    pixels: pixels,
    viewportDimension: 600,
    axisDirection: AxisDirection.up,
    devicePixelRatio: 3,
  );
}

double adjust(ChatScrollPhysics physics, ScrollMetrics old, ScrollMetrics updated) {
  return physics.adjustPositionForNewDimensions(
    oldPosition: old,
    newPosition: updated,
    isScrolling: false,
    velocity: 0,
  );
}

void main() {
  group('ChatScrollPhysics', () {
    late ChatScrollState state;
    late ChatScrollPhysics physics;

    setUp(() {
      state = ChatScrollState();
      physics = ChatScrollPhysics(state: state);
    });

    test('should follow the new end when the old position was at the end', () {
      final result = adjust(
        physics,
        metrics(pixels: -60, minScrollExtent: -60),
        metrics(pixels: -60, minScrollExtent: -260),
      );

      expect(result, -260);
    });

    test('should keep pixels when scrolled away from the end', () {
      final result = adjust(
        physics,
        metrics(pixels: 300, minScrollExtent: -60),
        metrics(pixels: 300, minScrollExtent: -260),
      );

      expect(result, 300);
    });

    test('should apply and consume a pending lift when scrolled away from the end', () {
      state.pendingLift = 200;

      final result = adjust(
        physics,
        metrics(pixels: 300, minScrollExtent: -60),
        metrics(pixels: 300, minScrollExtent: -260),
      );

      expect(result, 100);
      expect(state.pendingLift, 0);
    });

    test('should jump to the new end once when forced', () {
      state.forceEnd = true;

      final result = adjust(
        physics,
        metrics(pixels: 300, minScrollExtent: -60),
        metrics(pixels: 300, minScrollExtent: -260),
      );

      expect(result, -260);
      expect(state.forceEnd, isFalse);
    });

    test('should ignore user offsets while held', () {
      state.held = () => true;

      expect(physics.applyPhysicsToUserOffset(metrics(pixels: 0, minScrollExtent: 0), 40), 0);
    });

    test('should not fling while held', () {
      state.held = () => true;
      final position = metrics(pixels: 100, minScrollExtent: 0);

      expect(physics.createBallisticSimulation(position, 1500), isNull);
    });

    test('should keep the shared state when applied to an ancestor', () {
      final applied = physics.applyTo(const ClampingScrollPhysics());

      expect(applied.state, same(state));
      expect(applied.parent, isA<ClampingScrollPhysics>());
    });
  });
}
