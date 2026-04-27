import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/src/web/ensure_initialized_stub.dart' as monty_init;

void main() async {
  await monty_init.ensureInitialized();
  final runtime = MontyRuntime();

  print('--- Test: Python 2 style print ---');
  final code =
      'def hello(name):\n    return f"hello {name}"\nprint hello("alan")';
  final handle = runtime.execute(code);
  final result = await handle.result;

  if (result.isError) {
    print('Error Message: ${result.error!.message}');
    print('Line Number: ${result.error!.lineNumber}');
  } else {
    print('Result: ${result.value}');
  }

  runtime.dispose();
}
