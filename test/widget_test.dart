import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Monty IDE smoke test', (tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MontyIde(),
        ),
      ),
    );

    // Verify that the editor is present.
    expect(find.byType(MontyEditor), findsOneWidget);
    // Verify that the console is present.
    expect(find.byType(MontyConsole), findsOneWidget);
  });
}
