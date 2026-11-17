import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/src/chat_scroll_controller.dart';

void main() {
  group('ChatScrollController', () {
    test('should report at end before attaching to a list', () {
      final controller = ChatScrollController();
      addTearDown(controller.dispose);

      expect(controller.isAtEnd.value, isTrue);
    });

    test('should hand a pin request to the view once', () {
      final controller = ChatScrollController();
      addTearDown(controller.dispose);
      var notified = 0;
      controller.onPinRequest = () => notified++;

      controller.pinToTop('prompt');

      expect(notified, 1);
      expect(controller.takePinRequest(), 'prompt');
      expect(controller.takePinRequest(), isNull);
    });

    test('should replace a pending pin with a clear request', () {
      final controller = ChatScrollController();
      addTearDown(controller.dispose);

      controller.pinToTop('prompt');
      controller.clearPin();

      expect(controller.takePinRequest(), isNull);
      expect(controller.takeClearPinRequest(), isTrue);
      expect(controller.takeClearPinRequest(), isFalse);
    });

    testWidgets('should ignore an end update scheduled before dispose', (tester) async {
      final controller = ChatScrollController();
      controller.dispose();

      controller.debugUpdateAtEnd();

      expect(tester.takeException(), isNull);
    });
  });
}
