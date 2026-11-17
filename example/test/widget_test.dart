import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller_example/main.dart';

void main() {
  group('ExampleApp', () {
    testWidgets('should open the AI chat and pin a sent prompt', (
      tester,
    ) async {
      await tester.pumpWidget(const ExampleApp());
      await tester.tap(find.text('AI chat'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Hello'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
