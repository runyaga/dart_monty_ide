import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty_ide/src/bridge/flutter_extension.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Diagnosis: Interleaved Introspection', () {
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

    Future<void> runIntrospection() async {
      // The IDE's background script
      const script = '[ (_ide_k, repr(_ide_v), type(_ide_v).__name__) for _ide_k, _ide_v in globals().items() if not _ide_k.startswith("__") ]';
      await runtime.execute(script).result;
    }

    test('repro: introspection shadowing', () async {
      print('\n--- STEP 1: Define welcome() ---');
      await runtime.execute('def welcome(name): return 42').result;

      print('\n--- STEP 2: Run Background Introspection ---');
      await runIntrospection();

      print('\n--- STEP 3: Call Host Function ---');
      // Using the CURRENT prefix scheme
      final r = await runtime.execute('__monty__.flutter_set_color("box", "red")').result;
      
      if (r.isError) {
        print('FAILURE REPRODUCED: ${r.error!.message}');
        
        final check = await runtime.execute('print(f"DEBUG: {__monty__}")').result;
        print(check.printOutput);
      } else {
        print('SUCCESS');
      }
    });
  });
}
