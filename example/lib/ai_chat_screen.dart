import 'dart:async';

import 'package:flutter/material.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

import 'chat_widgets.dart';

/// An AI chat: each prompt is pinned to the top while a simulated answer streams in below it.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  /// Delay between streamed words.
  static const Duration tokenInterval = Duration(milliseconds: 30);

  /// Space above the composer for the jump-to-latest button.
  static const double jumpButtonBottom = 76;
  static const double jumpButtonEnd = 16;

  /// The simulated answer, streamed one word at a time.
  static const String cannedAnswer =
      'Here is how the keyboard behaves in this demo. The prompt you sent stays at the top of '
      'the screen while this answer grows below it, so you can read along without scrolling. '
      'Drag the list down past the top of the keyboard and it follows your finger; let go above '
      'the middle and it springs back. Scroll up into the history while the answer streams and '
      'nothing you are reading moves. A button appears to jump back to the latest message. '
      'Switch the lift mode from the menu to compare how ChatGPT, Claude, Telegram and '
      'Perplexity treat the keyboard. Every one of these behaviours comes from the same widget, '
      'with no changes to the list, the bubbles or the input bar.';

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final ChatScrollController _controller = ChatScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  KeyboardLiftBehavior _liftBehavior = KeyboardLiftBehavior.whenAtEnd;
  Timer? _stream;
  int _turn = 0;

  void _send(String text) {
    _stream?.cancel();
    final prompt = ChatMessage(id: 'prompt-$_turn', text: text, mine: true);
    final answer = ChatMessage(id: 'answer-$_turn', text: '', mine: false);
    _turn++;
    setState(() {
      _messages.insert(0, prompt);
      _messages.insert(0, answer);
    });
    _controller.pinToTop(prompt.id);
    final words = AiChatScreen.cannedAnswer.split(' ');
    var next = 0;
    _stream = Timer.periodic(AiChatScreen.tokenInterval, (timer) {
      if (next >= words.length) {
        timer.cancel();
        return;
      }
      setState(
        () => answer.text = answer.text.isEmpty
            ? words[next]
            : '${answer.text} ${words[next]}',
      );
      next++;
    });
  }

  @override
  void dispose() {
    _stream?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text('AI chat · ${_liftBehavior.name}'),
        actions: [
          PopupMenuButton<KeyboardLiftBehavior>(
            icon: const Icon(Icons.tune),
            initialValue: _liftBehavior,
            onSelected: (value) => setState(() => _liftBehavior = value),
            itemBuilder: (context) => [
              for (final behavior in KeyboardLiftBehavior.values)
                PopupMenuItem(value: behavior, child: Text(behavior.name)),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          KeyboardChatView(
            controller: _controller,
            liftBehavior: _liftBehavior,
            itemCount: _messages.length,
            itemKey: (index) => _messages[index].id,
            itemBuilder: (context, index) =>
                MessageBubble(message: _messages[index]),
            composer: Composer(onSend: _send, hint: 'Ask anything'),
          ),
          PositionedDirectional(
            end: AiChatScreen.jumpButtonEnd,
            bottom: 0,
            child: KeyboardStickyView(
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: AiChatScreen.jumpButtonBottom,
                ),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _controller.isAtEnd,
                  builder: (context, atEnd, _) => atEnd
                      ? const SizedBox.shrink()
                      : FloatingActionButton.small(
                          onPressed: _controller.animateToLatest,
                          child: const Icon(Icons.arrow_downward),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
