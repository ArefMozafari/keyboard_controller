import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/src/keyboard_dismiss_region.dart';
import 'package:keyboard_controller/src/keyboard_hold_scroll_physics.dart';
import 'package:keyboard_controller/src/keyboard_platform.dart';
import 'package:keyboard_controller/src/keyboard_scope.dart';

const rowHeight = 50.0;
const rowCount = 40;

void main() {
  group('KeyboardHoldScrollPhysics', () {
    late KeyboardController keyboard;

    Future<void> pumpList(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(KeyboardPlatform.channelName),
        (call) async => null,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardScope(
            child: Builder(
              builder: (context) {
                keyboard = KeyboardScope.of(context);
                return KeyboardDismissRegion(
                  child: ListView.builder(
                    physics: KeyboardHoldScrollPhysics(keyboard: keyboard),
                    itemCount: rowCount,
                    itemBuilder:
                        (context, index) => SizedBox(key: ValueKey<int>(index), height: rowHeight),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    testWidgets('should scroll a custom list normally', (tester) async {
      await pumpList(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byKey(const ValueKey<int>(4))).dy, 0);
    });

    testWidgets('should hold a custom list while the keyboard is dragged', (tester) async {
      await pumpList(tester);

      final gesture = await tester.startGesture(const Offset(100, 300));
      keyboard.gestureHeld = true;
      await gesture.moveBy(const Offset(0, -100));
      await gesture.moveBy(const Offset(0, -100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byKey(const ValueKey<int>(0))).dy, 0);
    });

    testWidgets('should keep the keyboard when applied to an ancestor', (tester) async {
      await pumpList(tester);

      final physics = KeyboardHoldScrollPhysics(
        keyboard: keyboard,
      ).applyTo(const ClampingScrollPhysics());

      expect(physics.keyboard, same(keyboard));
      expect(physics.parent, isA<ClampingScrollPhysics>());
    });
  });
}
