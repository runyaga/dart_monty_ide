import 'dart:async';
import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty_core/dart_monty_core.dart';
import 'package:dart_monty_ide/src/assistant/assistant_tool_handler.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';

/// Implementation of [AssistantToolHandler] that uses the live IDE controllers.
class IdeToolHandler implements AssistantToolHandler {
  /// Creates an [IdeToolHandler].
  IdeToolHandler({
    required this.vfs,
    required this.ideController,
  });

  final MontyVfs vfs;
  final MontyIdeController ideController;

  @override
  Future<Map<String, dynamic>> typeCheck(String code) async {
    // 1. Syntax check
    try {
      final runtime = MontyRuntime(extensions: ideController.extensions);
      final handle = await runtime.execute('${code.trim()}\n');
      await handle.result;
      await runtime.dispose();
    } on MontySyntaxError catch (e) {
      return {
        'ok': false,
        'errors': [
          {
            'line': e.exception?.lineNumber,
            'code': 'syntax-error',
            'message': e.message,
          }
        ],
      };
    }

    // 2. Type check
    final errors = await Monty.typeCheck(code);
    if (errors.isEmpty) {
      return {'ok': true, 'errors': []};
    }
    return {
      'ok': false,
      'errors': errors
          .map((e) => {
                'line': e.line,
                'col': e.column,
                'code': e.code,
                'message': e.message,
              })
          .toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> runPython(String code) async {
    // Clear and delimit in console so user knows which output is from which tool call
    ideController.clearConsole();
    final res = await ideController.execute(code);
    return {
      'output': res?.printOutput,
      'error': res?.error?.message,
      'value': res?.value.toString(),
    };
  }

  @override
  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    await vfs.writeFile(path, content);
    return {'status': 'success', 'path': path};
  }
}
