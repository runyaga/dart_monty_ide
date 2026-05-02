import 'dart:async';
import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  group('MontyConsole', () {
    testWidgets('displays stream output', (tester) async {
      final controller = StreamController<String>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MontyConsole(outputStream: controller.stream),
          ),
        ),
      );

      controller.add('Hello World');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Hello World'), findsOneWidget);

      controller.add('Second Line');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Second Line'), findsOneWidget);
      await controller.close();
    });
  });

  group('MontyEditor', () {
    testWidgets('triggers onRun when button pressed', (tester) async {
      var runPressed = false;
      final controller = CodeLineEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MontyEditor(
              controller: controller,
              onRun: () => runPressed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(runPressed, isTrue);
      
      // Clear pending cursor blink timers
      await tester.pump(const Duration(seconds: 1));
      controller.dispose();
    });
  });
}
