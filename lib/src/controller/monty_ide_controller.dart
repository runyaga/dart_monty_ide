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

    // Ensure WASM or FFI bindings are loaded.
    await DartMonty.ensureInitialized();

    _runtime = MontyRuntime(
      extensions: _extensions,
    );

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
        // 1. Try to extract line number from the exception if available.
        lastErrorLine = result.error?.lineNumber;

        // 2. Fallback: Parse line number from message text like "at line 3"
        if (lastErrorLine == null) {
          final lineMatch =
              RegExp(r'at line (\d+)').firstMatch(result.error!.message);
          if (lineMatch != null) {
            lastErrorLine = int.tryParse(lineMatch.group(1)!);
          }
        }

        // 3. Fallback: Translate byte range (e.g. "at byte range 50..55")
        // humans don't speak bytes!
        if (lastErrorLine == null) {
          final byteMatch =
              RegExp(r'at byte range (\d+)').firstMatch(result.error!.message);
          if (byteMatch != null) {
            final startByte = int.tryParse(byteMatch.group(1)!);
            if (startByte != null) {
              lastErrorLine = _getLineFromByteOffset(normalizedCode, startByte);
            }
          }
        }

        var errorMessage = 'Error: ${result.error!.message}\n';

        // Add helpful hint for print statements
        if (result.error!.message
                .contains('Simple statements must be separated') &&
            code.contains('print ')) {
          errorMessage +=
              'Hint: In Monty/Python 3, print is a function. Use print(...).\n';
        }

        _outputController.add(errorMessage);
      }

      return result;
    } on Exception catch (e) {
      _outputController.add('Exception: $e\n');
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
