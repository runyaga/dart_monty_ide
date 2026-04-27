import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/src/web/ensure_initialized_stub.dart' as monty_init;

void main() async {
  // Ensure we can run in a CLI test env
  await monty_init.ensureInitialized();
  
  final runtime = MontyRuntime();
  
  print('--- Test 1: Standard Newlines ---');
  final code1 = 'x = 1\ny = 2\nprint(x + y)';
  final h1 = runtime.execute(code1);
  final r1 = await h1.result;
  print('Result 1 Error: ${r1.error?.message}');

  print('\n--- Test 2: Windows Newlines ---');
  final code2 = 'x = 1\r\ny = 2\r\nprint(x + y)';
  final h2 = runtime.execute(code2);
  final r2 = await h2.result;
  print('Result 2 Error: ${r2.error?.message}');

  print('\n--- Test 3: No Trailing Newline in block ---');
  final code3 = 'def f():\n    pass\nprint("hi")';
  final h3 = runtime.execute(code3);
  final r3 = await h3.result;
  print('Result 3 Error: ${r3.error?.message}');

  runtime.dispose();
}
