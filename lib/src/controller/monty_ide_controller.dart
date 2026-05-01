import 'dart:async';
import 'dart:convert';
import 'package:dart_monty/dart_monty.dart';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_hhg/dart_monty_hhg.dart';
import 'package:flutter/foundation.dart';

/// Controller for the Monty IDE.
///
/// Manages the [MontyRuntime] lifecycle and provides methods for executing
/// Python code and observing results.
class MontyIdeController extends ChangeNotifier {
  /// Creates a [MontyIdeController].
  ///
  /// Provide either a static [extensions] list, or an [extensionsFactory]
  /// that produces fresh instances. The factory is preferred when any
  /// extension's lifecycle is one-shot (e.g. `EventLoopExtension`, which
  /// becomes permanently disposed after `onDispose`): [clearState] calls
  /// the factory to swap in a fresh set, so Reset Interpreter actually
  /// works for event-loop scripts.
  MontyIdeController({
    List<MontyExtension>? extensions,
    List<MontyExtension> Function()? extensionsFactory,
  })  : _extensionsFactory = extensionsFactory,
        _extensions = extensionsFactory?.call() ?? extensions;

  List<MontyExtension>? _extensions;
  final List<MontyExtension> Function()? _extensionsFactory;
  MontyRuntime? _runtime;
  bool _isInitialized = false;
  bool _isExecuting = false;

  /// Returns the list of registered extensions. May change after
  /// [clearState] when an [extensionsFactory] was supplied.
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

  /// Appends [line] to the IDE console.
  ///
  /// Used by host functions and host-API impls (e.g. an
  /// `SvgHostApi` that wants to surface "captured 1 SVG, 412 bytes")
  /// that have something user-visible to report. Adds a trailing
  /// newline if [line] doesn't already end in one.
  void appendOutput(String line) {
    _outputController.add(line.endsWith('\n') ? line : '$line\n');
  }

  /// Initializes the Monty platform and the runtime.
  ///
  /// This must be called before [execute].
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('Initializing Monty Platform...');
    await DartMonty.ensureInitialized();
    debugPrint('Monty Platform Initialized.');

    _runtime = MontyRuntime(
      extensions: _extensions,
    );
    // Register HHG extras (currently `requires(...)`) so scripts that
    // call them through plain `runtime.execute(...)` (rather than via
    // `Hhg.run`) see them as available. Idempotent.
    Hhg.attach(_runtime!);
    debugPrint('Monty Runtime Created.');

    _isInitialized = true;
    notifyListeners();
  }

  /// Executes the given Python [code].
  ///
  /// Returns the [MontyResult] of the execution.
  /// Results and print outputs are also emitted to the [output] stream unless [silent] is true.
  ///
  /// When [strict] is `true`, runs `Monty.typeCheck` against the
  /// auto-generated host-function stubs **before** execution; if it
  /// reports any errors, the interpreter is not started, the errors
  /// are emitted to [output] (when not [silent]), and the call returns
  /// `null`. Default `false` preserves today's permissive behaviour.
  Future<MontyResult?> execute(
    String code, {
    bool clear = true,
    bool silent = false,
    bool strict = false,
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'MontyIdeController must be initialized before execution.',
      );
    }

    if (!silent && clear) clearConsole();
    _isExecuting = true;
    if (!silent) {
      lastErrorLine = null;
      notifyListeners();
    }

    if (strict) {
      try {
        final prefix = extensionsToPrefixCode(
          _extensions ?? const [],
          returnTypeOverrides: hhgReturnTypeOverrides,
        );
        final errors = await Monty.typeCheck(code, prefixCode: prefix);
        if (errors.isNotEmpty) {
          if (!silent) {
            _outputController.add(
              '🛑 Strict mode: refusing to run, '
              '${errors.length} type error(s):\n',
            );
            for (final e in errors) {
              _outputController.add(
                '❌ [${e.code}] Line ${e.line}, Col ${e.column}: '
                '${e.message}\n',
              );
            }
            lastErrorLine = errors.first.line;
            notifyListeners();
          }
          _isExecuting = false;
          if (!silent) notifyListeners();
          return null;
        }
      } on Exception catch (e) {
        if (!silent) {
          _outputController.add('⚠️ Strict typecheck engine error: $e\n');
        }
        _isExecuting = false;
        if (!silent) notifyListeners();
        return null;
      }
    }

    try {
      // Normalize newlines and ensure trailing newline for the parser.
      final normalizedCode = '${code.replaceAll('\r\n', '\n').trim()}\n';

      final handle = _runtime!.execute(normalizedCode);

      // Wait for the result
      final result = await handle.result;

      if (!silent && result.printOutput != null && result.printOutput!.isNotEmpty) {
        _outputController.add(result.printOutput!);
      }

      if (result.isError) {
        final montyExc = result.error;
        if (!silent) lastErrorLine = montyExc?.lineNumber;

        // Fallback: Parse line number from message text like "at line 3"
        if (!silent && lastErrorLine == null && montyExc != null) {
          final lineMatch =
              RegExp(r'at line (\d+)').firstMatch(montyExc.message);
          if (lineMatch != null) {
            lastErrorLine = int.tryParse(lineMatch.group(1)!);
          }
        }

        // Fallback: Translate byte range
        if (!silent && lastErrorLine == null && montyExc != null) {
          final byteMatch =
              RegExp(r'at byte range (\d+)').firstMatch(montyExc.message);
          if (byteMatch != null) {
            final startByte = int.tryParse(byteMatch.group(1)!);
            if (startByte != null) {
              lastErrorLine = _getLineFromByteOffset(normalizedCode, startByte);
            }
          }
        }

        if (!silent) {
          var errorMessage = '';
          if (montyExc != null) {
            final type = montyExc.excType ?? 'PythonError';
            errorMessage = '[$type] ${montyExc.message}';
            if (lastErrorLine != null) {
              errorMessage += ' [IDE: Line $lastErrorLine]';
            }
            errorMessage += '\n';

            if (montyExc.message
                    .contains('Simple statements must be separated') &&
                code.contains('print ')) {
              errorMessage +=
                  'Hint: In Monty/Python 3, print is a function. Use print(...).\n';
            }
          } else {
            errorMessage = 'Error: Unknown execution failure\n';
          }
          _outputController.add(errorMessage);
        }
      }

      return result;
    } on MontySyntaxError catch (e) {
      if (!silent) {
        lastErrorLine = e.exception?.lineNumber;
        // Also try to translate byte range from message for SyntaxError
        if (lastErrorLine == null) {
          final byteMatch = RegExp(r'at byte range (\d+)').firstMatch(e.message);
          if (byteMatch != null) {
            final startByte = int.tryParse(byteMatch.group(1)!);
            if (startByte != null) {
              lastErrorLine = _getLineFromByteOffset(
                  '${code.trim()}\n', startByte); // Use same normalization
            }
          }
        }

        var msg = '[SyntaxError] ${e.message}';
        if (lastErrorLine != null) {
          msg += ' [IDE: Line $lastErrorLine]';
        }
        _outputController.add('$msg\n');
      }
      return null;
    } on MontyScriptError catch (e) {
      if (!silent) {
        lastErrorLine = e.exception?.lineNumber;
        _outputController.add('[${e.excType ?? "ScriptError"}] ${e.message}\n');
      }
      return null;
    } on MontyResourceError catch (e) {
      if (!silent) {
        _outputController.add('[ResourceError] ${e.message}\n');
      }
      return null;
    } on Exception catch (e, stack) {
      debugPrint('Internal System Error: $e');
      debugPrint('Stack Trace: $stack');
      if (!silent) {
        _outputController.add('[SystemException] $e\n');
      }
      return null;
    } finally {
      _isExecuting = false;
      if (!silent) notifyListeners();
    }
  }

  /// Convenience for background introspection.
  Future<MontyResult?> executeSilent(String code) =>
      execute(code, silent: true, clear: false);

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

  /// Performs static analysis on the given [code].
  ///
  /// Pure static check via [Monty.typeCheck] — no runtime, no execution.
  /// Safe to call on scripts with infinite loops (e.g. Monty UI `el_recv`
  /// loops). Host function stubs from registered extensions are passed as
  /// `prefixCode` so calls like `el_emit(...)` resolve. Errors are emitted
  /// to the [output] stream.
  Future<void> typeCheck(String code) async {
    clearConsole();
    _outputController.add('--- Analysis Started ---\n');
    try {
      _outputController.add('🔍 Checking types...\n');
      final prefix = extensionsToPrefixCode(
        _extensions ?? const [],
        returnTypeOverrides: hhgReturnTypeOverrides,
      );
      final errors = await Monty.typeCheck(code, prefixCode: prefix);
      if (errors.isEmpty) {
        _outputController.add('✅ Analysis complete: No errors found.\n');
      } else {
        for (final e in errors) {
          _outputController.add(
            '❌ [${e.code}] Line ${e.line}, Col ${e.column}: ${e.message}\n',
          );
        }
        _outputController.add('--- Found ${errors.length} typing errors ---\n');
      }
    } on Exception catch (e) {
      _outputController.add('⚠️ Analysis engine error: $e\n');
    } finally {
      notifyListeners();
    }
  }

  /// Return-type overrides for non-HHG-authored extensions whose source
  /// we can't change but whose return type we know.
  ///
  /// Currently: `el_recv` from `dart_monty`'s built-in
  /// `EventLoopExtension`. Drop entries here when their source grows
  /// HHG-style return-type metadata.
  ///
  /// Shared by [typeCheck] above and `IdeToolHandler.typeCheck` so both
  /// surfaces see the same enforcement.
  static const Map<String, String> hhgReturnTypeOverrides = {
    'el_recv': 'dict',
  };

  /// Clears only the console output.
  void clearConsole() {
    _outputController.add('___CLEAR_CONSOLE___');
  }

  /// Clears the interpreter state.
  ///
  /// Disposes the runtime, swaps in fresh extension instances (if a factory
  /// was supplied — required for one-shot extensions like
  /// `EventLoopExtension`), and creates a new runtime. Listeners are
  /// notified so UI components can rebind to the new extensions.
  void clearState() {
    unawaited(_runtime?.dispose());
    final factory = _extensionsFactory;
    if (factory != null) {
      _extensions = factory();
    }
    _runtime = MontyRuntime(extensions: _extensions);
    // Re-attach HHG extras after interpreter reset.
    Hhg.attach(_runtime!);
    lastErrorLine = null;
    clearConsole();
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
