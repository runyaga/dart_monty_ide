import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty_ide/src/bridge/flutter_extension.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Reproduction: int object is not callable', () {
    late MontyRuntime runtime;
    late WidgetRegistry registry;

    setUp(() async {
      await DartMonty.ensureInitialized();
      registry = WidgetRegistry();
      runtime = MontyRuntime(
        extensions: [MontyFlutterExtension(registry)],
      );
    });

    tearDown(() {
      runtime.dispose();
    });

    Future<void> executeSilent(String code) async {
       await runtime.execute(code).result;
    }

    test('sequential execution with introspection interleaved', () async {
      const script1 = 'x = 1';
      const script2 = 'y = 2';
      const introspection = '[ (k, repr(v), type(v).__name__) for k, v in globals().items() if not k.startswith("__") ]';
      const script3 = 'flutter_set_color("box_1", "teal")';

      print('Running Script 1...');
      await runtime.execute(script1).result;
      
      print('Running Introspection...');
      await executeSilent(introspection);

      print('Running Script 2...');
      await runtime.execute(script2).result;

      print('Running Introspection...');
      await executeSilent(introspection);

      print('Running Script 3...');
      final r3 = await (runtime.execute(script3).result);
      if (r3.isError) {
        print('Script 3 Error: ${r3.error?.message}');
      }
      expect(r3.isError, isFalse, reason: r3.error?.message);
    });
  });
}
