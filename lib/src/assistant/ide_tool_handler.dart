import 'dart:async';
import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty_ide/src/assistant/assistant_tool_handler.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';

/// Implementation of [AssistantToolHandler] that uses the live IDE controllers.
/// A tool handler that interacts with the Monty IDE state.
class IdeToolHandler implements AssistantToolHandler {
  /// Creates an [IdeToolHandler].
  IdeToolHandler({
    required this.vfs,
    required this.ideController,
  });

  /// The VFS to use for file operations.
  final MontyVfs vfs;

  /// The IDE controller to interact with.
  final MontyIdeController ideController;

  @override
  Future<Map<String, dynamic>> typeCheck(String code) async {
    // Pure static analysis via Monty.typeCheck — no runtime, no execution.
    // Safe on scripts with infinite event loops (el_recv). Host function
    // stubs are passed as prefixCode so calls like el_emit/prompt_extend
    // resolve.
    final prefix = MontyIdeController.buildHostStubs(ideController.extensions);
    final errors = await Monty.typeCheck(code, prefixCode: prefix);
    if (errors.isEmpty) {
      return <String, dynamic>{'ok': true, 'errors': []};
    }
    return <String, dynamic>{
      'ok': false,
      'errors': errors
          .map(
            (e) => <String, dynamic>{
              'line': e.line,
              'col': e.column,
              'code': e.code,
              'message': e.message,
            },
          )
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

  @override
  Future<Map<String, dynamic>> readFile(String path) async {
    try {
      final content = await vfs.readFile(path);
      return {'status': 'success', 'path': path, 'content': content};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  @override
  Future<Map<String, dynamic>> listFiles() async {
    try {
      final files = await vfs.listFiles();
      return {'status': 'success', 'files': files};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
