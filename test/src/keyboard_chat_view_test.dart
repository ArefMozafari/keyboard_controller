import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/src/chat_scroll_controller.dart';
import 'package:keyboard_controller/src/keyboard_chat_view.dart';
import 'package:keyboard_controller/src/keyboard_lift_behavior.dart';
import 'package:keyboard_controller/src/keyboard_platform.dart';
import 'package:keyboard_controller/src/keyboard_scope.dart';

const itemHeight = 50.0;
const composerHeight = 60.0;
const keyboardHeight = 300.0;
const listKey = Key('chat list');
const wideMessageWidth = 2000.0;

class TestMessage {
  TestMessage(this.id, [this.height = itemHeight]);

  final String id;
  double height;
}

List<TestMessage> seedMessages(int count) {
  return List<TestMessage>.generate(count, (index) => TestMessage('m$index'));
}

class ChatHarness {
  ChatHarness(this.tester);

  final WidgetTester tester;
  final ChatScrollController controller = ChatScrollController();
  final ValueNotifier<double> composer = ValueNotifier<double>(composerHeight);
  int composerTaps = 0;
  bool showChat = true;
  late KeyboardController keyboard;
  late StateSetter _setState;
  List<TestMessage> messages = seedMessages(20);

  double get screenHeight => tester.view.physicalSize.height / tester.view.devicePixelRatio;
  double get listBottom => screenHeight - composerHeight;

  Rect rectOf(String id) => tester.getRect(find.byKey(ValueKey<String>('box-$id')));

  Future<void> update(VoidCallback change) async {
    _setState(change);
    await tester.pump();
    // The composer size reaches the list one frame later.
    await tester.pump();
  }

  Future<void> setKeyboard(double height) async {
    tester.view.viewInsets = FakeViewPadding(bottom: height * tester.view.devicePixelRatio);
    await tester.pump();
    await tester.pump();
  }

  Future<void> scrollUp(double distance) async {
    await tester.drag(find.byKey(listKey), Offset(0, distance));
    await tester.pumpAndSettle();
  }

  Future<void> pump({
    KeyboardLiftBehavior liftBehavior = KeyboardLiftBehavior.always,
    bool removeInsetAbove = false,
    bool? installResult,
    int framesAfterMount = 2,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(KeyboardPlatform.channelName),
      (call) async => call.method == 'install' ? installResult : null,
    );
    addTearDown(tester.view.resetViewInsets);
    Widget chat = StatefulBuilder(
      builder: (context, setState) {
        _setState = setState;
        if (!showChat) return const SizedBox();
        return KeyboardChatView(
          key: listKey,
          controller: controller,
          liftBehavior: liftBehavior,
          itemCount: messages.length,
          itemKey: (index) => messages[index].id,
          itemBuilder: (context, index) {
            final message = messages[index];
            final box = SizedBox(
              key: ValueKey<String>('box-${message.id}'),
              height: message.height,
            );
            if (message.id.startsWith('stateful')) {
              return StatefulMessage(key: ValueKey<String>('state-${message.id}'), child: box);
            }
            if (!message.id.startsWith('wide')) return box;
            // A message with its own horizontal scrollable, like a code block.
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: wideMessageWidth, child: box),
            );
          },
          composer: ValueListenableBuilder<double>(
            valueListenable: composer,
            builder:
                (context, height, _) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => composerTaps++,
                  child: SizedBox(height: height),
                ),
          ),
        );
      },
    );
    if (removeInsetAbove) {
      final inner = chat;
      chat = Builder(builder: (context) => _removeInsets(context, inner));
    }
    await tester.pumpWidget(
      MediaQuery.fromView(
        view: tester.view,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardScope(
            child: Builder(
              builder: (context) {
                keyboard = KeyboardScope.of(context);
                return chat;
              },
            ),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < framesAfterMount; frame++) {
      await tester.pump();
    }
  }

  static Widget _removeInsets(BuildContext context, Widget child) {
    return MediaQuery.removeViewInsets(context: context, removeBottom: true, child: child);
  }
}

/// A message with widget state, like an answer whose reasoning section the user expanded.
class StatefulMessage extends StatefulWidget {
  const StatefulMessage({super.key, required this.child});

  final Widget child;

  @override
  State<StatefulMessage> createState() => StatefulMessageState();
}

class StatefulMessageState extends State<StatefulMessage> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  group('KeyboardChatView', () {
    group('list', () {
      testWidgets('should hide messages until the composer is measured', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump(framesAfterMount: 0);

        bool listVisible() {
          final visibility = find.ancestor(
            of: find.byKey(const ValueKey<String>('box-m0')),
            matching: find.byType(Visibility),
          );
          return tester.widget<Visibility>(visibility).visible;
        }

        expect(listVisible(), isFalse);

        await tester.pump();
        expect(listVisible(), isTrue);
        expect(chat.rectOf('m0').bottom, chat.listBottom);
      });

      testWidgets('should start at the newest item above the composer', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();

        expect(chat.rectOf('m0').bottom, chat.listBottom);
        expect(chat.controller.isAtEnd.value, isTrue);
      });

      testWidgets('should stay at the newest item while it grows', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();

        await chat.update(() => chat.messages.first.height = 200);

        expect(chat.rectOf('m0').bottom, chat.listBottom);
        expect(chat.rectOf('m0').height, 200);
      });

      testWidgets('should follow a message inserted while at the end', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();

        await chat.update(() => chat.messages.insert(0, TestMessage('new')));

        expect(chat.rectOf('new').bottom, chat.listBottom);
      });

      testWidgets('should keep the read item still when the newest item grows while scrolled up', (
        tester,
      ) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.update(() => chat.messages.insert(0, TestMessage('stream')));
        await chat.scrollUp(300);
        final before = chat.rectOf('m8');

        await chat.update(() => chat.messages.first.height = 400);

        expect(chat.rectOf('m8'), before);
        expect(chat.controller.isAtEnd.value, isFalse);
      });

      testWidgets('should keep the read item still when a message is inserted while scrolled up', (
        tester,
      ) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.scrollUp(300);
        final before = chat.rectOf('m8');

        await chat.update(() => chat.messages.insert(0, TestMessage('incoming', 120)));

        expect(chat.rectOf('m8'), before);
      });

      testWidgets('should not move when older items are appended at the old end', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();

        await chat.update(
          () => chat.messages.addAll(
            List<TestMessage>.generate(10, (index) => TestMessage('old$index')),
          ),
        );

        expect(chat.rectOf('m0').bottom, chat.listBottom);
        expect(chat.controller.isAtEnd.value, isTrue);
      });

      testWidgets('should reset to newest when the anchor key disappears', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.scrollUp(300);

        await chat.update(
          () => chat.messages = List<TestMessage>.generate(5, (index) => TestMessage('r$index')),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(chat.rectOf('r0').bottom, chat.listBottom);
      });

      testWidgets('should report isAtEnd and animate to latest', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.scrollUp(300);
        expect(chat.controller.isAtEnd.value, isFalse);

        chat.controller.animateToLatest();
        await tester.pumpAndSettle();

        expect(chat.controller.isAtEnd.value, isTrue);
        expect(chat.rectOf('m0').bottom, chat.listBottom);
      });

      testWidgets('should fall back to dismiss on drag without interactive dismiss', (
        tester,
      ) async {
        final chat = ChatHarness(tester);
        await chat.pump();

        final scrollView = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
        expect(scrollView.keyboardDismissBehavior, ScrollViewKeyboardDismissBehavior.onDrag);
      });

      testWidgets('should leave dismissal to the native drag when it is supported', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump(installResult: true);

        final scrollView = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
        expect(scrollView.keyboardDismissBehavior, ScrollViewKeyboardDismissBehavior.manual);
      });

      testWidgets('should keep the read item still when a message from the first build grows', (
        tester,
      ) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.scrollUp(300);
        final before = chat.rectOf('m8');

        await chat.update(() => chat.messages.first.height = 400);

        expect(chat.rectOf('m8'), before);
      });

      testWidgets('should not scroll a list shorter than the screen', (tester) async {
        final chat = ChatHarness(tester)..messages = seedMessages(3);
        await chat.pump();

        await chat.scrollUp(300);

        expect(chat.rectOf('m0').bottom, chat.listBottom);
        expect(chat.rectOf('m2').top, greaterThan(0));
      });

      testWidgets('should keep reading history when the anchor message is deleted', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.scrollUp(300);
        final before = chat.rectOf('m8');

        await chat.update(() => chat.messages.removeAt(1));

        expect(chat.controller.isAtEnd.value, isFalse);
        expect(chat.rectOf('m8').top, before.top + itemHeight);
      });

      testWidgets('should scroll again on the next gesture after a held one', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        final held = await tester.startGesture(const Offset(100, 200));
        chat.keyboard.gestureHeld = true;
        await held.moveBy(const Offset(0, 40));
        await held.up();
        await tester.pumpAndSettle();
        final before = chat.rectOf('m3');

        await chat.scrollUp(100);

        expect(chat.rectOf('m3').top, greaterThan(before.top));
      });

      testWidgets('should remove its keyboard listeners when disposed', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();

        await chat.update(() => chat.showChat = false);

        // ignore: invalid_use_of_protected_member
        expect((chat.keyboard.height as ChangeNotifier).hasListeners, isFalse);
      });

      testWidgets('should not scroll the list while gestureHeld', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        final before = chat.rectOf('m3');

        final gesture = await tester.startGesture(const Offset(100, 200));
        chat.keyboard.gestureHeld = true;
        await gesture.moveBy(const Offset(0, 40));
        await gesture.moveBy(const Offset(0, 40));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(chat.rectOf('m3'), before);
      });
    });

    group('lift behaviour', () {
      testWidgets('should lift history when the composer grows with always', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump(liftBehavior: KeyboardLiftBehavior.always);
        await chat.scrollUp(200);
        final before = chat.rectOf('m6');

        chat.composer.value = composerHeight * 2;
        await tester.pump();
        await tester.pump();

        expect(chat.rectOf('m6').top, before.top - composerHeight);
      });

      testWidgets('should keep persistent padding when a message scrolls sideways', (tester) async {
        final chat = ChatHarness(tester)..messages = [TestMessage('wide'), ...seedMessages(20)];
        await chat.pump(liftBehavior: KeyboardLiftBehavior.persistent);
        await chat.setKeyboard(keyboardHeight);
        await chat.setKeyboard(0);

        final wide = chat.rectOf('wide');
        await tester.dragFrom(Offset(100, wide.center.dy), const Offset(-200, 0));
        await tester.pumpAndSettle();

        expect(chat.rectOf('wide').bottom, chat.listBottom - keyboardHeight);
      });

      testWidgets('should release persistent padding when the user scrolls the list', (
        tester,
      ) async {
        final chat = ChatHarness(tester);
        await chat.pump(liftBehavior: KeyboardLiftBehavior.persistent);
        await chat.setKeyboard(keyboardHeight);
        await chat.setKeyboard(0);

        await chat.scrollUp(100);
        chat.controller.animateToLatest();
        await tester.pumpAndSettle();

        expect(chat.rectOf('m0').bottom, chat.listBottom);
      });

      testWidgets('should lift content with the keyboard when always and scrolled up', (
        tester,
      ) async {
        final chat = ChatHarness(tester);
        await chat.pump(liftBehavior: KeyboardLiftBehavior.always);
        await chat.scrollUp(200);
        final before = chat.rectOf('m6');

        await chat.setKeyboard(keyboardHeight);

        expect(chat.rectOf('m6').top, before.top - keyboardHeight);
      });

      testWidgets('should keep content still when whenAtEnd and scrolled up', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump(liftBehavior: KeyboardLiftBehavior.whenAtEnd);
        await chat.scrollUp(200);
        final before = chat.rectOf('m6');

        await chat.setKeyboard(keyboardHeight);

        expect(chat.rectOf('m6'), before);
      });

      testWidgets('should lift content when whenAtEnd at the end', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump(liftBehavior: KeyboardLiftBehavior.whenAtEnd);

        await chat.setKeyboard(keyboardHeight);

        expect(chat.rectOf('m0').bottom, chat.listBottom - keyboardHeight);
      });

      testWidgets('should keep padding after close when persistent', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump(liftBehavior: KeyboardLiftBehavior.persistent);

        await chat.setKeyboard(keyboardHeight);
        await chat.setKeyboard(0);

        expect(chat.rectOf('m0').bottom, chat.listBottom - keyboardHeight);
      });

      testWidgets('should never pad for the keyboard when never', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump(liftBehavior: KeyboardLiftBehavior.never);

        await chat.setKeyboard(keyboardHeight);

        expect(chat.rectOf('m0').bottom, chat.listBottom);
      });

      testWidgets('should deliver taps to the composer while it rides the keyboard', (
        tester,
      ) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.setKeyboard(keyboardHeight);

        await tester.tapAt(Offset(100, chat.screenHeight - keyboardHeight - composerHeight / 2));

        expect(chat.composerTaps, 1);
      });

      testWidgets('should pad the list for the composer and the bottom safe area', (tester) async {
        const safeBottom = 34.0;
        tester.view.viewPadding = FakeViewPadding(
          bottom: safeBottom * tester.view.devicePixelRatio,
        );
        addTearDown(tester.view.resetViewPadding);
        final chat = ChatHarness(tester);
        await chat.pump();

        expect(chat.rectOf('m0').bottom, chat.listBottom - safeBottom);
      });

      testWidgets('should move the list up when the composer grows', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();

        chat.composer.value = composerHeight * 2;
        await tester.pump();
        await tester.pump();

        expect(chat.rectOf('m0').bottom, chat.listBottom - composerHeight);
      });

      testWidgets('should assert when an ancestor consumed the inset', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump(removeInsetAbove: true);

        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboardHeight * tester.view.devicePixelRatio,
        );
        await tester.pump();

        final error = tester.takeException();
        expect(error, isA<FlutterError>());
        expect(error.toString(), contains('resizeToAvoidBottomInset: false'));
      });
    });

    group('pin to top', () {
      testWidgets('should place the pinned prompt at the top of the visible area', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();

        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));

        expect(chat.rectOf('prompt').top, 0);
      });

      testWidgets('should shrink blank space as the answer grows and keep the prompt still', (
        tester,
      ) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));
        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('answer', 20)));

        await chat.update(() => chat.messages.first.height = 200);

        expect(chat.rectOf('prompt').top, 0);
        expect(chat.rectOf('answer').top, itemHeight);
      });

      testWidgets('should end at the answer once it fills the viewport', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));
        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('answer', 20)));

        await chat.update(() => chat.messages.first.height = 1000);

        expect(chat.rectOf('answer').bottom, chat.listBottom);
        expect(chat.rectOf('answer').top, lessThan(0));
      });

      testWidgets('should pin a prompt when the answer placeholder is already inserted', (
        tester,
      ) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        await chat.update(() {
          chat.messages.insert(0, TestMessage('prompt'));
          chat.messages.insert(0, TestMessage('answer', 20));
        });

        chat.controller.pinToTop('prompt');
        await chat.update(() {});

        expect(chat.rectOf('prompt').top, 0);
      });

      testWidgets('should drop the pin when the list is cleared', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));

        await chat.update(() => chat.messages.clear());
        await chat.update(() => chat.messages.add(TestMessage('greeting')));

        expect(chat.rectOf('greeting').bottom, chat.listBottom);
      });

      testWidgets('should not scroll past the oldest message after pinning the first prompt', (
        tester,
      ) async {
        final chat = ChatHarness(tester)..messages = <TestMessage>[];
        await chat.pump();
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));
        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('answer', 1000)));

        await chat.scrollUp(3000);

        expect(chat.rectOf('prompt').top, 0);
      });

      testWidgets('should stop a fling at the oldest message with bouncing physics', (
        tester,
      ) async {
        final chat = ChatHarness(tester)..messages = <TestMessage>[];
        await chat.pump(liftBehavior: KeyboardLiftBehavior.whenAtEnd);
        await chat.setKeyboard(keyboardHeight);
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));
        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('answer', 1000)));

        await tester.fling(find.byKey(listKey), const Offset(0, 2000), 3000);
        await tester.pumpAndSettle();

        expect(chat.rectOf('prompt').top, 0);
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

      testWidgets('should fling to the oldest message across a short scroll range', (tester) async {
        const overflow = 10.0;
        final chat = ChatHarness(tester)..messages = <TestMessage>[];
        await chat.pump(liftBehavior: KeyboardLiftBehavior.whenAtEnd);
        await chat.setKeyboard(keyboardHeight);
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));
        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('answer', 20)));
        final visible = chat.listBottom - keyboardHeight;
        await chat.update(() => chat.messages.first.height = visible - itemHeight + overflow);
        expect(chat.rectOf('prompt').top, -overflow);

        await tester.fling(find.byKey(listKey), const Offset(0, 2000), 3000);
        await tester.pumpAndSettle();

        expect(chat.rectOf('prompt').top, 0);
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

      testWidgets('should not apply a keyboard lift that changed no extents later', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump(liftBehavior: KeyboardLiftBehavior.always);
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));
        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('answer', 20)));
        await chat.scrollUp(150);
        await chat.setKeyboard(keyboardHeight);
        final before = chat.rectOf('m1');

        await chat.update(() => chat.messages.first.height = 1000);

        expect(chat.rectOf('m1'), before);
      });

      testWidgets('should keep the state of earlier messages across sends', (tester) async {
        final chat = ChatHarness(tester)..messages = <TestMessage>[];
        await chat.pump();
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt-1')));
        chat.controller.pinToTop('prompt-1');
        await chat.update(() => chat.messages.insert(0, TestMessage('stateful-answer-1')));
        final answer = find.byKey(const ValueKey<String>('state-stateful-answer-1'));
        tester.state<StatefulMessageState>(answer).expanded = true;

        await chat.update(() => chat.messages.insert(0, TestMessage('prompt-2')));
        chat.controller.pinToTop('prompt-2');
        await chat.update(() => chat.messages.insert(0, TestMessage('answer-2', 20)));

        expect(chat.rectOf('prompt-2').top, 0);
        expect(
          tester
              .state<StatefulMessageState>(
                find.byKey(const ValueKey<String>('state-stateful-answer-1'), skipOffstage: false),
              )
              .expanded,
          isTrue,
        );
      });

      testWidgets('should pin a message from the history in place', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();

        chat.controller.pinToTop('m3');
        await chat.update(() {});

        expect(chat.rectOf('m3').top, 0);
        expect(chat.rectOf('m0').bottom, chat.rectOf('m3').top + 4 * itemHeight);
      });

      testWidgets('should drop the pin when the pinned message is deleted', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));

        await chat.update(() => chat.messages.removeAt(0));

        expect(chat.rectOf('m0').bottom, chat.listBottom);
      });

      testWidgets('should drop the blank space after clearPin', (tester) async {
        final chat = ChatHarness(tester);
        await chat.pump();
        chat.controller.pinToTop('prompt');
        await chat.update(() => chat.messages.insert(0, TestMessage('prompt')));

        chat.controller.clearPin();
        await chat.update(() {});

        expect(chat.rectOf('prompt').bottom, chat.listBottom);
      });
    });
  });
}
