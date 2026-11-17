import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/src/keyboard_platform.dart';
import 'package:keyboard_controller/src/keyboard_scope.dart';
import 'package:keyboard_controller/src/keyboard_sticky_view.dart';

const keyboardHeight = 300.0;
const safeBottom = 34.0;
const childKey = Key('sticky child');

void main() {
  group('KeyboardStickyView', () {
    testWidgets('should lift the child by keyboard height minus safe inset', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(KeyboardPlatform.channelName),
        (call) async => null,
      );
      final ratio = tester.view.devicePixelRatio;
      tester.view.viewPadding = FakeViewPadding(bottom: safeBottom * ratio);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpWidget(
        MediaQuery.fromView(
          view: tester.view,
          child: const KeyboardScope(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: KeyboardStickyView(child: SizedBox(key: childKey, height: 50)),
              ),
            ),
          ),
        ),
      );
      final screenHeight = tester.view.physicalSize.height / ratio;
      expect(tester.getBottomLeft(find.byKey(childKey)).dy, screenHeight - safeBottom);

      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight * ratio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();

      expect(tester.getBottomLeft(find.byKey(childKey)).dy, screenHeight - keyboardHeight);
    });
  });
}
