import 'package:flutter/material.dart';

/// One chat message; the text grows while an answer streams in.
class ChatMessage {
  ChatMessage({required this.id, required this.text, required this.mine});

  final String id;
  String text;
  final bool mine;
}

/// A message bubble aligned to the sender's side.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  static const double maxWidthFactor = 0.78;
  static const EdgeInsets margin = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 4,
  );
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 10,
  );
  static const double radius = 18;

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * maxWidthFactor,
        ),
        child: Container(
          margin: margin,
          padding: padding,
          decoration: BoxDecoration(
            color: message.mine
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Text(message.text.isEmpty ? '…' : message.text),
        ),
      ),
    );
  }
}

/// A multi-line input bar with a send button.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.onSend, this.hint = 'Message'});

  static const int maxLines = 5;
  static const EdgeInsets padding = EdgeInsets.fromLTRB(12, 8, 4, 8);

  final ValueChanged<String> onSend;
  final String hint;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _text = TextEditingController();

  void _send() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    widget.onSend(value);
    _text.clear();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: Composer.padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: Composer.maxLines,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: _send),
          ],
        ),
      ),
    );
  }
}
