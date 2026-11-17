import 'package:flutter/material.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

import 'ai_chat_screen.dart';
import 'messenger_screen.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'keyboard_controller',
      // The demo is recorded for the README; the debug ribbon would cover the app bar action.
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      // One scope above the navigator serves every chat route.
      builder: (context, child) => KeyboardScope(child: child!),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('keyboard_controller')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('Messenger'),
            subtitle: const Text('200 messages, lift: always'),
            onTap: () => _open(context, const MessengerScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI chat'),
            subtitle: const Text(
              'Pinned prompt, streaming answer, four lift modes',
            ),
            onTap: () => _open(context, const AiChatScreen()),
          ),
        ],
      ),
    );
  }
}
