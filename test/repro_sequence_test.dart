import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty_ide/src/bridge/flutter_extension.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Reproduction: 01 -> 02 -> 03 sequence', () {
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

    Future<void> checkTypes(String stage) async {
      print('\n--- Checking Types at $stage ---');
      
      final names = ['flutter_set_color', 'flutter_set_prop', 'print'];
      for (final name in names) {
        final script = 'type($name).__name__';
        final res = await runtime.execute(script).result;
        if (res.isError) {
          print('Error checking $name: ${res.error?.message}');
        } else {
          print('$name: ${res.value}');
        }
      }
    }

    test('repro: 01 -> 02 -> 03 sequence', () async {
      const script01 = '''
def welcome(name):
    return f"Greetings, {name}!"

print(welcome("Engineer"))
''';

      const script02 = '''
numbers = [1, 2, 3, 4, 5]
print(f"Squares: {[n**2 for n in numbers]}")
''';

      const script03 = '''
print("🎨 Updating Flutter widgets...")
flutter_set_color("box_1", "teal")
flutter_set_prop("label_1", "text", "Updated from Monty Python!")
print("Done.")
''';

      print('\n--- RUNNING 01_BASICS.PY ---');
      final r1 = await runtime.execute(script01).result;
      expect(r1.isError, isFalse, reason: r1.error?.message);
      await checkTypes('After 01');

      print('\n--- RUNNING 02_LOGIC.PY ---');
      final r2 = await runtime.execute(script02).result;
      expect(r2.isError, isFalse, reason: r2.error?.message);
      await checkTypes('After 02');

      print('\n--- RUNNING 03_GUI.PY ---');
      final r3 = await runtime.execute(script03).result;
      if (r3.isError) {
        print('Script 03 Error: ${r3.error?.message}');
      }
      expect(r3.isError, isFalse, reason: r3.error?.message);
    });
  });
}
