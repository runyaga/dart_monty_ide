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
      await tester.pumpAndSettle();

      expect(find.text('Hello World'), findsOneWidget);

      controller.add('Second Line');
      await tester.pumpAndSettle();

      expect(find.text('Second Line'), findsOneWidget);
      await controller.close();
    });
  });

  group('MontyEditor', () {
    testWidgets('triggers onRun when button pressed', (tester) async {
      bool runPressed = false;
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

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(runPressed, isTrue);
      controller.dispose();
    });
  });
}
