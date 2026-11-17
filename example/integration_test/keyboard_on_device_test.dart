import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keyboard_controller/keyboard_controller.dart';
import 'package:keyboard_controller_example/chat_widgets.dart';
import 'package:keyboard_controller_example/main.dart';

/// How far, in logical pixels, measured positions may be from the expected ones.
const double layoutTolerance = 1.5;

/// How long to wait for the real keyboard to finish animating.
const Duration keyboardTimeout = Duration(seconds: 5);

const Duration frameStep = Duration(milliseconds: 100);

double viewInset(WidgetTester tester) {
  final view = tester.view;
  return view.viewInsets.bottom / view.devicePixelRatio;
}

Future<void> waitUntil(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(keyboardTimeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the keyboard.');
    }
    await tester.pump(frameStep);
  }
}

/// Waits until the keyboard inset stops changing, so measurements see the resting layout.
Future<double> waitForSteadyInset(WidgetTester tester) async {
  var previous = -1.0;
  var steadyFrames = 0;
  final deadline = DateTime.now().add(keyboardTimeout);
  while (steadyFrames < 5) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The keyboard inset never settled.');
    }
    await tester.pump(frameStep);
    final current = viewInset(tester);
    steadyFrames = (current - previous).abs() < 0.5 ? steadyFrames + 1 : 0;
    previous = current;
  }
  return previous;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Example on a device with the real keyboard', () {
    testWidgets(
      'should keep the composer on the keyboard and the newest message above it',
      (tester) async {
        await tester.pumpWidget(const ExampleApp());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Messenger'));
        await tester.pumpAndSettle();
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final safeBottom =
            tester.view.viewPadding.bottom / tester.view.devicePixelRatio;
        final restingComposer = tester.getRect(find.byType(Composer));
        expect(
          restingComposer.bottom,
          closeTo(screenHeight - safeBottom, layoutTolerance),
        );

        await tester.tap(find.byType(TextField));
        await waitUntil(tester, () => viewInset(tester) > 100);
        final keyboard = await waitForSteadyInset(tester);
        final composer = tester.getRect(find.byType(Composer));
        final newest = tester.getRect(find.text('Message 200'));
        debugPrint(
          'DEVICE keyboard=$keyboard composerBottom=${composer.bottom} '
          'keyboardTop=${screenHeight - keyboard} newestBottom=${newest.bottom} '
          'composerTop=${composer.top}',
        );

        expect(
          composer.bottom,
          closeTo(screenHeight - keyboard, layoutTolerance),
        );
        expect(newest.bottom, lessThan(composer.top));
        expect(newest.bottom, greaterThan(composer.top - 40));

        FocusManager.instance.primaryFocus?.unfocus();
        await waitUntil(tester, () => viewInset(tester) < 1);
        await waitForSteadyInset(tester);
        final closed = tester.getRect(find.byType(Composer));
        expect(
          closed.bottom,
          closeTo(screenHeight - safeBottom, layoutTolerance),
        );
      },
    );

    testWidgets('should pin the sent prompt and stop scrolling at it', (
      tester,
    ) async {
      await tester.pumpWidget(const ExampleApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI chat'));
      await tester.pumpAndSettle();
      final listTop = tester.getRect(find.byType(AppBar)).bottom;

      await tester.tap(find.byType(TextField));
      await waitUntil(tester, () => viewInset(tester) > 100);
      await waitForSteadyInset(tester);
      tester.widget<TextField>(find.byType(TextField)).controller!.text =
          'Device check';
      await tester.tap(find.byIcon(Icons.send));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(frameStep);
      }
      final prompt = find.text('Device check');
      final pinnedTop = tester.getRect(prompt).top;
      debugPrint('DEVICE listTop=$listTop promptTop=$pinnedTop');
      // The bubble's margin and padding sit between the list top and the text.
      expect(pinnedTop - listTop, inInclusiveRange(0, 30));

      // pumpAndSettle returns between streamed tokens, so wait for the answer's last words.
      await waitUntil(
        tester,
        () => find.textContaining('or the input bar.').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final keyboard = KeyboardScope.of(
        tester.element(find.byType(CustomScrollView)),
      );
      // Once the answer outgrows the screen the list follows its end, so the prompt may be out of view.
      String promptTop() => prompt.evaluate().isEmpty
          ? 'out of view'
          : '${tester.getRect(prompt).top}';
      void report(String label) => debugPrint(
        'DEVICE $label pixels=${position.pixels} min=${position.minScrollExtent} '
        'max=${position.maxScrollExtent} promptTop=${promptTop()} '
        'keyboard=${keyboard.height.value} phase=${keyboard.phase.value.name} '
        'inset=${viewInset(tester)} composer=${tester.getRect(find.byType(Composer)).height}',
      );
      report('answerDone');
      // Start on the visible messages: the list's centre lies under the composer when the
      // keyboard is open.
      await tester.flingFrom(
        Offset(200, listTop + 100),
        const Offset(0, 2000),
        3000,
      );
      await tester.pumpAndSettle();
      report('afterFling');
      expect(position.pixels, position.maxScrollExtent);
      expect(tester.getRect(prompt).top - listTop, inInclusiveRange(0, 30));
    });
  });
}
