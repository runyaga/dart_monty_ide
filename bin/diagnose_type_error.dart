import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/src/bridge/flutter_extension.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:dart_monty/src/web/ensure_initialized_stub.dart' as monty_init;

void main() async {
  await monty_init.ensureInitialized();
  
  final registry = WidgetRegistry();
  final runtime = MontyRuntime(
    extensions: [MontyFlutterExtension(registry)],
  );
  
  Future<void> logState(String label) async {
    final r = await runtime.execute('type(flutter_set_color).__name__').result;
    print('[$label] flutter_set_color type: ${r.value}');
    
    // Check if _ exists and what its value is
    final r2 = await runtime.execute('print(f"  _ value: {_}")').result;
    if (!r2.isError) print(r2.printOutput?.trim());
  }

  print('--- Phase 1: Initial ---');
  await logState('Initial');

  print('\n--- Phase 2: Run 01_basics.py ---');
  await runtime.execute('def welcome(name): return f"hi {name}"\nprint(welcome("Eng"))').result;
  await logState('After 01');

  print('\n--- Phase 3: Run 02_logic.py (The suspected culprit) ---');
  // This is the EXACT line from 02_logic.py
  await runtime.execute('numbers = [1, 2, 3]\nprint(f"Squares: {[n**2 for n in numbers]}")').result;
  await logState('After 02');

  print('\n--- Phase 4: Intentional Shadowing Test ---');
  await runtime.execute('flutter_set_color = 42').result;
  await logState('After Shadowing');

  runtime.dispose();
}
