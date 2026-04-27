import 'dart:async';
import 'dart:convert';
import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:flutter/foundation.dart';

/// Controller for the Monty IDE.
///
/// Manages the [MontyRuntime] lifecycle and provides methods for executing
/// Python code and observing results.
class MontyIdeController extends ChangeNotifier {
  /// Creates a [MontyIdeController].
  MontyIdeController({
    List<MontyExtension>? extensions,
  }) : _extensions = extensions;

  final List<MontyExtension>? _extensions;
  MontyRuntime? _runtime;
  bool _isInitialized = false;
  bool _isExecuting = false;

  /// Returns the list of registered extensions.
  List<MontyExtension>? get extensions => _extensions;

  /// The line number of the last error, if any.
  int? lastErrorLine;

  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  /// Whether the controller has been initialized.
  bool get isInitialized => _isInitialized;

  /// Whether the controller is currently executing code.
  bool get isExecuting => _isExecuting;

  /// Stream of stdout and error messages from the interpreter.
  Stream<String> get output => _outputController.stream;

  /// Initializes the Monty platform and the runtime.
  ///
  /// This must be called before [execute].
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('Initializing Monty Platform...');
    // Ensure WASM or FFI bindings are loaded.
    await DartMonty.ensureInitialized();
    debugPrint('Monty Platform Initialized.');

    _runtime = MontyRuntime(
      extensions: _extensions,
    );
    debugPrint('Monty Runtime Created.');

    _isInitialized = true;
    notifyListeners();
  }

  /// Executes the given Python [code].
  ///
  /// Returns the [MontyResult] of the execution.
  /// Results and print outputs are also emitted to the [output] stream.
  Future<MontyResult?> execute(String code) async {
    if (!_isInitialized) {
      throw StateError(
        'MontyIdeController must be initialized before execution.',
      );
    }

    _isExecuting = true;
    lastErrorLine = null;
    notifyListeners();

    try {
      // Normalize newlines and ensure trailing newline for the parser.
      final normalizedCode = '${code.replaceAll('\r\n', '\n').trim()}\n';

      final handle = _runtime!.execute(normalizedCode);

      // Wait for the result
      final result = await handle.result;

      if (result.printOutput != null && result.printOutput!.isNotEmpty) {
        _outputController.add(result.printOutput!);
      }

      if (result.isError) {
        final montyExc = result.error;
        lastErrorLine = montyExc?.lineNumber;

        // Fallback: Parse line number
        if (lastErrorLine == null && montyExc != null) {
          final lineMatch = RegExp(r'at line (\d+)').firstMatch(montyExc.message);
          if (lineMatch != null) {
            lastErrorLine = int.tryParse(lineMatch.group(1)!);
          }
        }

        if (lastErrorLine == null && montyExc != null) {
          final byteMatch = RegExp(r'at byte range (\d+)').firstMatch(montyExc.message);
          if (byteMatch != null) {
            final startByte = int.tryParse(byteMatch.group(1)!);
            if (startByte != null) {
              lastErrorLine = _getLineFromByteOffset(normalizedCode, startByte);
            }
          }
        }

        var errorMessage = '';
        if (montyExc != null) {
          final type = montyExc.excType ?? 'PythonError';
          errorMessage = '[$type] ${montyExc.message}\n';
          if (montyExc.message.contains('Simple statements must be separated') && code.contains('print ')) {
            errorMessage += 'Hint: In Monty/Python 3, print is a function. Use print(...).\n';
          }
        } else {
          errorMessage = 'Error: Unknown execution failure\n';
        }
        _outputController.add(errorMessage);
      }

      return result;
    } on MontySyntaxError catch (e) {
      lastErrorLine = e.exception?.lineNumber;
      _outputController.add('[SyntaxError] ${e.message}\n');
      return null;
    } on MontyScriptError catch (e) {
      lastErrorLine = e.exception?.lineNumber;
      _outputController.add('[${e.excType ?? "ScriptError"}] ${e.message}\n');
      return null;
    } on MontyResourceError catch (e) {
      _outputController.add('[ResourceError] ${e.message}\n');
      return null;
    } catch (e, stack) {
      debugPrint('Internal System Error: $e');
      debugPrint('Stack Trace: $stack');
      _outputController.add('[SystemException] $e\n');
      return null;
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  /// Translates a UTF-8 byte offset to a 1-based line number.
  int _getLineFromByteOffset(String code, int offset) {
    final bytes = utf8.encode(code);
    var lineCount = 1;
    for (var i = 0; i < offset && i < bytes.length; i++) {
      if (bytes[i] == 10) {
        // \n
        lineCount++;
      }
    }
    return lineCount;
  }

  /// Executes code without emitting to the output stream or changing error state.
  ///
  /// Used for introspection and background state updates.
  Future<MontyResult?> executeSilent(String code) async {
    if (!_isInitialized) return null;
    debugPrint('Executing Silent Code: ${code.trim()}');
    try {
      final handle = _runtime!.execute(code);
      final res = await handle.result;
      debugPrint('Silent execution complete. Result: ${res.value}');
      return res;
    } catch (e) {
      debugPrint('Silent execution error: $e');
      return null;
    }
  }

  /// Clears the interpreter state.
  void clearState() {
    unawaited(_runtime?.dispose());
    _runtime = MontyRuntime(extensions: _extensions);
    lastErrorLine = null;
    _outputController.add('--- Interpreter Reset ---\n');
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_runtime?.dispose());
    unawaited(_outputController.close());
    super.dispose();
  }
}
