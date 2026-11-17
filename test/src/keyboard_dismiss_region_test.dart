import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/src/keyboard_dismiss_region.dart';
import 'package:keyboard_controller/src/keyboard_phase.dart';
import 'package:keyboard_controller/src/keyboard_platform.dart';
import 'package:keyboard_controller/src/keyboard_scope.dart';

const shownHeight = 336.0;
const codec = StandardMethodCodec();

Future<void> sendFromNative(String method, Map<String, Object?> arguments) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    KeyboardPlatform.channelName,
    codec.encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}

void main() {
  group('KeyboardDismissRegion', () {
    late List<MethodCall> calls;
    late KeyboardController keyboard;
    late FocusNode focusNode;

    Iterable<MethodCall> callsNamed(String method) => calls.where((call) => call.method == method);

    Future<double> pumpRegion(
      WidgetTester tester, {
      bool keyboardOpen = true,
      bool supported = true,
      bool controlGranted = true,
      ValueListenable<Offset>? paintOffset,
    }) async {
      calls = <MethodCall>[];
      focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(KeyboardPlatform.channelName),
        (call) async {
          calls.add(call);
          return switch (call.method) {
            'install' => supported,
            'startControl' => supported && controlGranted ? shownHeight : null,
            _ => null,
          };
        },
      );
      Widget region = KeyboardDismissRegion(
        child: Focus(focusNode: focusNode, child: const SizedBox.expand()),
      );
      if (paintOffset != null) {
        final inner = region;
        region = ValueListenableBuilder<Offset>(
          valueListenable: paintOffset,
          builder: (context, offset, _) => Transform.translate(offset: offset, child: inner),
        );
      }
      await tester.pumpWidget(
        KeyboardScope(
          child: Builder(
            builder: (context) {
              keyboard = KeyboardScope.of(context);
              return region;
            },
          ),
        ),
      );
      if (keyboardOpen) {
        tester.view.viewInsets = FakeViewPadding(
          bottom: shownHeight * tester.view.devicePixelRatio,
        );
        addTearDown(tester.view.resetViewInsets);
      }
      focusNode.requestFocus();
      await tester.pump();
      return tester.view.physicalSize.height / tester.view.devicePixelRatio;
    }

    testWidgets('should register and remove its rect on iOS', (tester) async {
      await pumpRegion(tester);

      final region = callsNamed('setRegion').single.arguments as Map<Object?, Object?>;
      expect(region['top'], 0);
      expect(region['height'], tester.view.physicalSize.height / tester.view.devicePixelRatio);

      await tester.pumpWidget(const SizedBox());
      expect(callsNamed('removeRegion'), hasLength(1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('should resend its rect on pointer down after a paint-only move', (tester) async {
      final offset = ValueNotifier<Offset>(const Offset(400, 0));
      addTearDown(offset.dispose);
      await pumpRegion(tester, paintOffset: offset);
      expect((callsNamed('setRegion').last.arguments as Map<Object?, Object?>)['left'], 400);

      // A route slide moves the region by a transform, which repaints but never relays out.
      offset.value = Offset.zero;
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.up();

      expect((callsNamed('setRegion').last.arguments as Map<Object?, Object?>)['left'], 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('should not ask for control where interactive dismiss is unsupported', (
      tester,
    ) async {
      final screenHeight = await pumpRegion(tester, supported: false);

      final gesture = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      for (var step = 1; step <= 5; step++) {
        await gesture.moveTo(Offset(100, screenHeight - shownHeight + 5 + step * 20));
        await tester.pump();
      }
      await gesture.up();

      expect(callsNamed('startControl'), isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should ignore a new drag while the release settles', (tester) async {
      final screenHeight = await pumpRegion(tester);
      final first = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      await first.moveTo(Offset(100, screenHeight - shownHeight + 10));
      await tester.pump();
      await first.moveTo(Offset(100, screenHeight - 100));
      await tester.pump();
      await first.up();
      await tester.pump(const Duration(milliseconds: 50));
      final insetsBefore = callsNamed('setControlledInset').length;

      final second = await tester.startGesture(Offset(100, screenHeight - 300));
      await second.moveTo(Offset(100, screenHeight - 250));
      final secondDragInsets = callsNamed('setControlledInset')
          .skip(insetsBefore)
          .map((call) => (call.arguments as Map<Object?, Object?>)['height'])
          .where((height) => height == 250.0);
      await second.up();
      await tester.pumpAndSettle();

      expect(secondDragInsets, isEmpty);
      final finish = callsNamed('finishControl').single.arguments as Map<Object?, Object?>;
      expect(finish['show'], isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should start control when the finger crosses the keyboard top on Android', (
      tester,
    ) async {
      final screenHeight = await pumpRegion(tester);
      final keyboardTop = screenHeight - shownHeight;

      final gesture = await tester.startGesture(Offset(100, keyboardTop - 100));
      await gesture.moveTo(Offset(100, keyboardTop - 10));
      expect(callsNamed('startControl'), isEmpty);
      await gesture.moveTo(Offset(100, keyboardTop + 10));
      await tester.pump();
      await gesture.moveTo(Offset(100, keyboardTop + 50));
      await tester.pump();

      expect(callsNamed('startControl'), hasLength(1));
      expect(keyboard.phase.value, KeyboardPhase.dragging);
      expect(keyboard.height.value, shownHeight - 50);
      expect(keyboard.gestureHeld, isTrue);
      expect(
        (callsNamed('setControlledInset').last.arguments as Map<Object?, Object?>)['height'],
        shownHeight - 50,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should finish hidden and unfocus when released below half', (tester) async {
      final screenHeight = await pumpRegion(tester);

      final gesture = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      await gesture.moveTo(Offset(100, screenHeight - shownHeight + 10));
      await tester.pump();
      await gesture.moveTo(Offset(100, screenHeight - 100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final finish = callsNamed('finishControl').single.arguments as Map<Object?, Object?>;
      expect(finish['show'], isFalse);
      expect(keyboard.height.value, 0);
      expect(keyboard.phase.value, KeyboardPhase.closed);
      expect(focusNode.hasFocus, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should finish shown when released above half', (tester) async {
      final screenHeight = await pumpRegion(tester);

      final gesture = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      await gesture.moveTo(Offset(100, screenHeight - shownHeight + 10));
      await tester.pump();
      await gesture.moveTo(Offset(100, screenHeight - shownHeight + 60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final finish = callsNamed('finishControl').single.arguments as Map<Object?, Object?>;
      expect(finish['show'], isTrue);
      expect(keyboard.phase.value, KeyboardPhase.open);
      expect(focusNode.hasFocus, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    Future<bool> flingAndRelease(
      WidgetTester tester,
      double screenHeight, {
      required double slowInset,
      required double releaseInset,
    }) async {
      final gesture = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      await gesture.moveTo(
        Offset(100, screenHeight - shownHeight + 10),
        timeStamp: const Duration(milliseconds: 10),
      );
      await tester.pump();
      await gesture.moveTo(
        Offset(100, screenHeight - slowInset),
        timeStamp: const Duration(milliseconds: 400),
      );
      await tester.pump();
      // The release position alone would pick the other outcome; only the speed decides.
      await gesture.moveTo(
        Offset(100, screenHeight - (slowInset + releaseInset) / 2),
        timeStamp: const Duration(milliseconds: 410),
      );
      await gesture.moveTo(
        Offset(100, screenHeight - releaseInset),
        timeStamp: const Duration(milliseconds: 420),
      );
      await gesture.up(timeStamp: const Duration(milliseconds: 425));
      await tester.pumpAndSettle();
      final finish = callsNamed('finishControl').single.arguments as Map<Object?, Object?>;
      return finish['show']! as bool;
    }

    testWidgets('should finish shown when flung upward below half', (tester) async {
      final screenHeight = await pumpRegion(tester);

      final shown = await flingAndRelease(tester, screenHeight, slowInset: 20, releaseInset: 120);

      expect(shown, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should finish hidden when flung downward above half', (tester) async {
      final screenHeight = await pumpRegion(tester);

      final shown = await flingAndRelease(tester, screenHeight, slowInset: 320, releaseInset: 220);

      expect(shown, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should ask for control once per gesture after a denial', (tester) async {
      final screenHeight = await pumpRegion(tester, controlGranted: false);

      final gesture = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      for (var step = 1; step <= 5; step++) {
        await gesture.moveTo(Offset(100, screenHeight - shownHeight + 5 + step * 20));
        await tester.pump();
      }
      await gesture.up();

      expect(callsNamed('startControl'), hasLength(1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should end the drag at the real inset when the system takes control back', (
      tester,
    ) async {
      final screenHeight = await pumpRegion(tester);
      final gesture = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      await gesture.moveTo(Offset(100, screenHeight - shownHeight + 10));
      await tester.pump();
      await gesture.moveTo(Offset(100, screenHeight - 200));
      await tester.pump();

      tester.view.viewInsets = FakeViewPadding.zero;
      await sendFromNative('controlEnded', {});
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(keyboard.phase.value, KeyboardPhase.closed);
      expect(keyboard.height.value, 0);
      expect(callsNamed('finishControl'), isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should release control when removed mid-drag', (tester) async {
      final screenHeight = await pumpRegion(tester);
      final gesture = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      await gesture.moveTo(Offset(100, screenHeight - shownHeight + 10));
      await tester.pump();
      await gesture.moveTo(Offset(100, screenHeight - 200));
      await tester.pump();

      await tester.pumpWidget(KeyboardScope(child: const SizedBox()));
      await tester.pump();

      // Checked before the finger lifts: the pointer-up still reaches removed listeners.
      final finish = callsNamed('finishControl').single.arguments as Map<Object?, Object?>;
      expect(finish['show'], isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should drop its rect while another route covers it and restore it after', (
      tester,
    ) async {
      calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(KeyboardPlatform.channelName),
        (call) async {
          calls.add(call);
          return call.method == 'install' ? true : null;
        },
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        KeyboardScope(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Navigator(
              key: navigator,
              onGenerateRoute:
                  (settings) => PageRouteBuilder<void>(
                    pageBuilder:
                        (context, animation, secondary) =>
                            const KeyboardDismissRegion(child: SizedBox.expand()),
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(callsNamed('setRegion'), hasLength(1));

      navigator.currentState!.push(
        PageRouteBuilder<void>(pageBuilder: (context, animation, secondary) => const SizedBox()),
      );
      await tester.pumpAndSettle();
      expect(callsNamed('removeRegion'), hasLength(1));

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(callsNamed('setRegion'), hasLength(2));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('should ignore a second pointer during control', (tester) async {
      final screenHeight = await pumpRegion(tester);

      final first = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      await first.moveTo(Offset(100, screenHeight - shownHeight + 20));
      await tester.pump();
      final second = await tester.startGesture(Offset(200, screenHeight - shownHeight + 5));
      await second.moveTo(Offset(200, screenHeight - 20));
      await tester.pump();
      await second.up();
      await tester.pump();

      expect(callsNamed('startControl'), hasLength(1));
      expect(callsNamed('finishControl'), isEmpty);
      await first.up();
      await tester.pumpAndSettle();
      expect(callsNamed('finishControl'), hasLength(1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should finish shown when the finger lifts before control is ready', (
      tester,
    ) async {
      final screenHeight = await pumpRegion(tester);

      final gesture = await tester.startGesture(Offset(100, screenHeight - shownHeight + 5));
      await gesture.moveTo(Offset(100, screenHeight - shownHeight + 20));
      await gesture.up();
      await tester.pumpAndSettle();

      final finish = callsNamed('finishControl').single.arguments as Map<Object?, Object?>;
      expect(finish['show'], isTrue);
      expect(keyboard.phase.value, KeyboardPhase.open);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('should not start control while the keyboard is closed', (tester) async {
      final screenHeight = await pumpRegion(tester, keyboardOpen: false);

      final gesture = await tester.startGesture(Offset(100, screenHeight - 200));
      await gesture.moveTo(Offset(100, screenHeight - 10));
      await gesture.up();
      await tester.pump();

      expect(callsNamed('startControl'), isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
