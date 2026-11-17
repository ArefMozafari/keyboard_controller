import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/src/keyboard_model.dart';
import 'package:keyboard_controller/src/keyboard_phase.dart';

const openHeight = 336.0;
const animationDuration = Duration(milliseconds: 250);

void main() {
  group('KeyboardModel', () {
    late DateTime now;
    late KeyboardModel model;

    setUp(() {
      now = DateTime(2026, 11, 17);
      model = KeyboardModel(clock: () => now);
    });

    test('should start closed with zero height and progress', () {
      expect(model.phase.value, KeyboardPhase.closed);
      expect(model.height.value, 0);
      expect(model.targetHeight.value, 0);
      expect(model.progress.value, 0);
    });

    test('should enter opening and report target when target exceeds height', () {
      model.applyTarget(openHeight, animationDuration);

      expect(model.phase.value, KeyboardPhase.opening);
      expect(model.targetHeight.value, openHeight);
    });

    test('should reach open when view inset meets target', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight / 2);
      expect(model.phase.value, KeyboardPhase.opening);
      expect(model.progress.value, 0.5);

      model.applyViewInset(openHeight);

      expect(model.phase.value, KeyboardPhase.open);
      expect(model.progress.value, 1);
    });

    test('should compute progress against last open height while closing', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);

      model.applyTarget(0, animationDuration);
      model.applyViewInset(openHeight / 4);

      expect(model.phase.value, KeyboardPhase.closing);
      expect(model.targetHeight.value, 0);
      expect(model.progress.value, 0.25);
    });

    test('should enter opening when view inset grows before any target arrives', () {
      model.applyViewInset(100);

      expect(model.phase.value, KeyboardPhase.opening);
    });

    test('should ignore view insets while dragging', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.beginInteractive();

      model.applyInteractive(200);
      model.applyViewInset(openHeight);

      expect(model.phase.value, KeyboardPhase.dragging);
      expect(model.height.value, 200);
    });

    test('should return settle from current height when target arrives during drag', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.beginInteractive();
      model.applyInteractive(120);

      final settle = model.applyTarget(0, animationDuration);

      expect(settle, isNotNull);
      expect(settle!.from, 120);
      expect(settle.to, 0);
      expect(settle.duration, animationDuration);
      expect(model.phase.value, KeyboardPhase.closing);
    });

    test('should ignore view insets while settling and resume after completeSettle', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.beginInteractive();
      model.applyInteractive(120);
      model.applyTarget(0, animationDuration);

      model.applyViewInset(5);
      expect(model.height.value, 120);
      model.applySettleValue(60);
      expect(model.height.value, 60);
      model.completeSettle();

      expect(model.height.value, 0);
      expect(model.phase.value, KeyboardPhase.closed);
      model.applyViewInset(openHeight);
      expect(model.height.value, openHeight);
    });

    test('should stop settling when a new drag begins', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.beginInteractive();
      model.applyInteractive(120);
      model.applyTarget(0, animationDuration);

      model.beginInteractive();
      model.applyInteractive(200);
      model.applySettleValue(40);
      model.completeSettle();

      expect(model.phase.value, KeyboardPhase.dragging);
      expect(model.height.value, 200);
    });

    test('should retarget a settle when a different target arrives', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.beginInteractive();
      model.applyInteractive(120);
      model.applyTarget(0, animationDuration);
      model.applySettleValue(60);

      final retarget = model.applyTarget(openHeight, animationDuration);

      expect(retarget, isNotNull);
      expect(retarget!.from, 60);
      expect(retarget.to, openHeight);
      expect(model.phase.value, KeyboardPhase.opening);
      model.completeSettle();
      expect(model.height.value, openHeight);
      expect(model.phase.value, KeyboardPhase.open);
    });

    test('should settle a resting inset as open when no native target arrives', () {
      model.applyViewInset(150);
      model.applyViewInset(openHeight);
      expect(model.phase.value, KeyboardPhase.opening);

      model.settleWithoutTarget();

      expect(model.phase.value, KeyboardPhase.open);
      expect(model.targetHeight.value, openHeight);
      expect(model.progress.value, 1);
    });

    test('should settle a zero inset as closed when no native target arrives', () {
      model.applyViewInset(openHeight);
      model.settleWithoutTarget();
      model.applyViewInset(100);
      model.applyViewInset(0);

      model.settleWithoutTarget();

      expect(model.phase.value, KeyboardPhase.closed);
      expect(model.targetHeight.value, 0);
    });

    test('should leave phase to native targets once one has arrived', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(150);

      model.settleWithoutTarget();

      expect(model.phase.value, KeyboardPhase.opening);
      expect(model.targetHeight.value, openHeight);
    });

    test('should ignore a second target while settling', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.beginInteractive();
      model.applyInteractive(120);
      model.applyTarget(0, animationDuration);

      final second = model.applyTarget(0, animationDuration);

      expect(second, isNull);
    });

    test('should settle at the given target when an interactive drag ends', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.beginInteractive();
      model.applyInteractive(300);

      model.endInteractive(target: openHeight);

      expect(model.phase.value, KeyboardPhase.open);
      expect(model.height.value, openHeight);
    });

    test('should derive phase from height when an interactive drag ends without target', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.beginInteractive();
      model.applyInteractive(openHeight);

      model.endInteractive();

      expect(model.phase.value, KeyboardPhase.open);
    });

    test('should drop a stray zero view inset inside the finish guard', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.guardAfterFinish(const Duration(milliseconds: 100));

      now = now.add(const Duration(milliseconds: 10));
      model.applyViewInset(0);

      expect(model.height.value, openHeight);
    });

    test('should accept zero after the finish guard expires', () {
      model.applyTarget(openHeight, animationDuration);
      model.applyViewInset(openHeight);
      model.guardAfterFinish(const Duration(milliseconds: 100));

      now = now.add(const Duration(milliseconds: 101));
      model.applyViewInset(0);

      expect(model.height.value, 0);
    });
  });
}
