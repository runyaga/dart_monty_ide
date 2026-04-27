import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MontyIdeController', () {
    late MontyIdeController controller;

    setUp(() {
      controller = MontyIdeController();
    });

    test('isInitialized is false initially', () {
      expect(controller.isInitialized, isFalse);
    });

    test('isExecuting is false initially', () {
      expect(controller.isExecuting, isFalse);
    });

    test('execute throws StateError when not initialized', () async {
      expect(
        () => controller.execute('print("hi")'),
        throwsStateError,
      );
    });
  });
}
