import 'dart:async';
import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_hhg/dart_monty_hhg.dart';
import 'package:dart_monty_ide/src/assistant/assistant_tool_handler.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/foundation.dart';

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
    final prefix = extensionsToPrefixCode(
      ideController.extensions ?? const [],
      returnTypeOverrides: MontyIdeController.hhgReturnTypeOverrides,
    );
    // Monty.typeCheck prepends prefixCode; subtract prefix line count so
    // reported lines match the user's script (not the combined file).
    // Errors in the prefix itself are stub-generation bugs — suppress them.
    final prefixLines = '\n'.allMatches(prefix).length;
    final allErrors = await Monty.typeCheck(code, prefixCode: prefix);
    final errors =
        allErrors.where((e) => (e.line ?? 0) > prefixLines).toList();
    if (errors.isEmpty) {
      return {'ok': true, 'errors': <Object?>[]};
    }

    return {
      'ok': false,
      'errors': errors
          .map(
            (e) => <String, dynamic>{
              'line': (e.line ?? prefixLines) - prefixLines,
              'col': e.column,
              'code': e.code,
              'message': e.message,
            },
          )
          .toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> runPython(
    String code, {
    Map<String, Object?>? inputs,
  }) async {
    if (!ideController.isInitialized) await ideController.initialize();
    // Clear and delimit in console so user knows which output is from
    // which tool call
    ideController.clearConsole();
    final res = await ideController.execute(code, inputs: inputs);

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
    } on Object catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  @override
  Future<Map<String, dynamic>> listFiles() async {
    try {
      final files = await vfs.listFiles();

      return {'status': 'success', 'files': files};
    } on Object catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  EventLoopExtension? get _eventLoop {
    final exts = ideController.extensions ?? const <MontyExtension>[];
    for (final e in exts) {
      if (e is EventLoopExtension) return e;
    }

    return null;
  }

  @override
  Future<Map<String, dynamic>> uiState() async {
    final el = _eventLoop;
    if (el == null) {
      return {
        'status': 'error',
        'message': 'EventLoopExtension not registered',
      };
    }

    return {
      'status': 'success',
      'tree': el.lastEmitted,
      'awaiting': el.isWaiting,
    };
  }

  @override
  Future<Map<String, dynamic>> uiDispatch({
    required String target,
    required String eventType,
    Object? value,
  }) async {
    final el = _eventLoop;
    if (el == null) {
      debugPrint('[ui_dispatch] no EventLoopExtension registered');

      return {
        'status': 'error',
        'message': 'EventLoopExtension not registered',
      };
    }
    final event = <String, Object?>{'type': eventType, 'target': target};
    if (value != null) event['value'] = value;
    debugPrint('[ui_dispatch] dispatching $event (awaiting=${el.isWaiting})');
    try {
      el.dispatch(event);

      return {'status': 'success', 'event': event};
      // Why: dispatch documents `throw StateError` as its expected error.
      // ignore: avoid_catching_errors
    } on StateError catch (e) {
      debugPrint('[ui_dispatch] StateError: ${e.message}');

      return {'status': 'error', 'message': e.message, 'event': event};
    }
  }
}
