import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty_ide/src/bridge/flutter_extension.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Diagnosis: int object is not callable', () {
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

    test('repro: call same function twice', () async {
      const script = 'flutter_set_color("box_1", "teal")';

      print('First call...');
      final r1 = await (runtime.execute(script).result);
      expect(r1.isError, isFalse, reason: r1.error?.message);

      print('Second call...');
      final r2 = await (runtime.execute(script).result);
      if (r2.isError) {
        print('Error on second call: ${r2.error?.message}');
      }
      expect(r2.isError, isFalse, reason: r2.error?.message);
    });
  });
}
