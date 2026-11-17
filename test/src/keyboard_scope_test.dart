import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/src/keyboard_phase.dart';
import 'package:keyboard_controller/src/keyboard_platform.dart';
import 'package:keyboard_controller/src/keyboard_scope.dart';

const codec = StandardMethodCodec();
const openHeight = 336.0;

Future<void> sendFromNative(String method, Map<String, Object?> arguments) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    KeyboardPlatform.channelName,
    codec.encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}

void main() {
  group('KeyboardScope', () {
    late KeyboardController keyboard;
    late List<MethodCall> calls;

    Future<void> pumpScope(WidgetTester tester, {Widget? child, bool? installResult}) async {
      calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(KeyboardPlatform.channelName),
        (call) async {
          calls.add(call);
          return call.method == 'install' ? installResult : null;
        },
      );
      await tester.pumpWidget(
        KeyboardScope(
          child: Builder(
            builder: (context) {
              keyboard = KeyboardScope.of(context);
              return child ?? const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('should install the native side once after the first frame', (tester) async {
      await pumpScope(tester);

      expect(calls.where((call) => call.method == 'install'), hasLength(1));
    });

    testWidgets('should report interactive dismiss support from install', (tester) async {
      await pumpScope(tester, installResult: true);
      await tester.pump();

      expect(keyboard.interactiveDismissSupported.value, isTrue);
    });

    testWidgets('should report no interactive dismiss without a native side', (tester) async {
      await pumpScope(tester);
      await tester.pump();

      expect(keyboard.interactiveDismissSupported.value, isFalse);
    });

    testWidgets('should update height from view insets', (tester) async {
      await pumpScope(tester);

      tester.view.viewInsets = FakeViewPadding(bottom: openHeight * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();

      expect(keyboard.height.value, openHeight);
    });

    testWidgets('should animate from drag height to target after release', (tester) async {
      await pumpScope(tester);
      await sendFromNative('keyboardWillChange', {'height': openHeight, 'durationMs': 250});
      tester.view.viewInsets = FakeViewPadding(bottom: openHeight * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();

      await sendFromNative('interactive', {'height': 120.0});
      expect(keyboard.phase.value, KeyboardPhase.dragging);
      expect(keyboard.height.value, 120);
      await sendFromNative('keyboardWillChange', {'height': 0.0, 'durationMs': 250});
      await sendFromNative('interactiveEnd', {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      final midway = keyboard.height.value;

      await tester.pump(const Duration(milliseconds: 200));

      expect(midway, inExclusiveRange(0, 120));
      expect(keyboard.height.value, 0);
      expect(keyboard.phase.value, KeyboardPhase.closed);
    });

    testWidgets('should keep the drag height when the keyboard is grabbed during a settle', (
      tester,
    ) async {
      await pumpScope(tester);
      await sendFromNative('interactive', {'height': 120.0});
      await sendFromNative('keyboardWillChange', {'height': 0.0, 'durationMs': 250});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await sendFromNative('interactive', {'height': 250.0});
      await tester.pump(const Duration(milliseconds: 400));

      expect(keyboard.phase.value, KeyboardPhase.dragging);
      expect(keyboard.height.value, 250);
    });

    testWidgets('should settle phase from resting insets without native events', (tester) async {
      await pumpScope(tester);

      tester.view.viewInsets = FakeViewPadding(bottom: openHeight * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(keyboard.phase.value, KeyboardPhase.open);
      expect(keyboard.targetHeight.value, openHeight);
    });

    testWidgets('should keep the keyboard open when it reopens during a dismiss settle', (
      tester,
    ) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await pumpScope(tester, child: Focus(focusNode: focusNode, child: const SizedBox()));
      focusNode.requestFocus();
      await tester.pump();
      await sendFromNative('interactive', {'height': 100.0});
      await sendFromNative('keyboardWillChange', {'height': 0.0, 'durationMs': 250});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await sendFromNative('keyboardWillChange', {'height': openHeight, 'durationMs': 250});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(keyboard.height.value, openHeight);
      expect(keyboard.phase.value, KeyboardPhase.open);
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('should settle when the target arrives after the drag ends', (tester) async {
      await pumpScope(tester);
      await sendFromNative('interactive', {'height': 120.0});

      await sendFromNative('interactiveEnd', {});
      await sendFromNative('keyboardWillChange', {'height': 0.0, 'durationMs': 250});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      final midway = keyboard.height.value;
      await tester.pump(const Duration(milliseconds: 200));

      expect(midway, inExclusiveRange(0, 120));
      expect(keyboard.height.value, 0);
      expect(keyboard.phase.value, KeyboardPhase.closed);
    });

    testWidgets('should settle to the view inset when a drag ends without a target', (
      tester,
    ) async {
      await pumpScope(tester);
      tester.view.viewInsets = FakeViewPadding(bottom: openHeight * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await sendFromNative('keyboardWillChange', {'height': openHeight, 'durationMs': 250});
      await tester.pump();
      await sendFromNative('interactive', {'height': 330.0});

      await sendFromNative('interactiveEnd', {});
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 400));

      expect(keyboard.height.value, openHeight);
      expect(keyboard.phase.value, KeyboardPhase.open);
    });

    testWidgets('should not touch disposed state when removed mid-settle', (tester) async {
      await pumpScope(tester);
      await sendFromNative('interactive', {'height': 120.0});
      await sendFromNative('keyboardWillChange', {'height': 0.0, 'durationMs': 250});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });

    testWidgets('should mark the gesture held once native reports a drag', (tester) async {
      await pumpScope(tester);

      await sendFromNative('interactive', {'height': 300.0});

      expect(keyboard.gestureHeld, isTrue);
    });

    testWidgets('should unfocus after a drag dismiss settles', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await pumpScope(tester, child: Focus(focusNode: focusNode, child: const SizedBox()));
      focusNode.requestFocus();
      await tester.pump();

      await sendFromNative('interactive', {'height': 100.0});
      await sendFromNative('keyboardWillChange', {'height': 0.0, 'durationMs': 100});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('should throw a FlutterError naming KeyboardScope when missing', (tester) async {
      late Object error;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            try {
              KeyboardScope.of(context);
            } catch (caught) {
              error = caught;
            }
            return const SizedBox();
          },
        ),
      );

      expect(error, isA<FlutterError>());
      expect(error.toString(), contains('KeyboardScope'));
    });
  });
}
