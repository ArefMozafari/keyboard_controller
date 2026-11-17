import 'package:flutter/material.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

import 'chat_widgets.dart';

/// A messenger chat: content always lifts with the keyboard, like Telegram.
class MessengerScreen extends StatefulWidget {
  const MessengerScreen({super.key});

  static const int seededMessageCount = 200;

  @override
  State<MessengerScreen> createState() => _MessengerScreenState();
}

class _MessengerScreenState extends State<MessengerScreen> {
  final ChatScrollController _controller = ChatScrollController();
  late final List<ChatMessage> _messages = List<ChatMessage>.generate(
    MessengerScreen.seededMessageCount,
    (index) => ChatMessage(
      id: 'seed-$index',
      text: 'Message ${MessengerScreen.seededMessageCount - index}',
      mine: index % 3 == 0,
    ),
  );
  int _sent = 0;

  void _send(String text) {
    setState(
      () => _messages.insert(
        0,
        ChatMessage(id: 'sent-${_sent++}', text: text, mine: true),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Messenger')),
      body: KeyboardChatView(
        controller: _controller,
        itemCount: _messages.length,
        itemKey: (index) => _messages[index].id,
        itemBuilder: (context, index) =>
            MessageBubble(message: _messages[index]),
        composer: Composer(onSend: _send),
      ),
    );
  }
}
