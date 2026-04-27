import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty/src/web/ensure_initialized_stub.dart' as monty_init;

class DiagnosticExtension extends MontyExtension {
  @override
  String get namespace => 'diag';

  @override
  List<HostFunction> get functions => [
        HostFunction(
          schema: const HostFunctionSchema(
            name: 'diag_func',
            params: [],
          ),
          handler: (args, ctx) async => 'ok',
        ),
      ];
}

void main() async {
  await monty_init.ensureInitialized();
  
  final ext = DiagnosticExtension();
  final runtime = MontyRuntime(extensions: [ext]);
  
  print('--- Diagnosis: List Comprehension Shadowing Host Functions ---');
  
  // 1. Initial call
  await runtime.execute('diag_func()').result;

  // 2. Run a list comprehension where the loop variable matches the host function name
  print('\nRunning: [diag_func for diag_func in [1, 2, 3]]');
  await runtime.execute('[diag_func for diag_func in [1, 2, 3]]').result;

  // 3. Try calling diag_func again
  print('Calling diag_func() after comprehension...');
  final r = await runtime.execute('diag_func()').result;
  if (r.isError) {
    print('REPRODUCED: ${r.error!.message}');
  } else {
    print('SUCCESS: ${r.value}');
  }

  runtime.dispose();
}
