import 'dart:async';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/ui/monty_console.dart';
import 'package:dart_monty_ide/src/ui/monty_editor.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// A full-featured Python IDE widget.
///
/// Combines a [MontyEditor] and a [MontyConsole] into a single, resizable
/// layout.
class MontyIde extends StatefulWidget {
  /// Creates a [MontyIde].
  const MontyIde({
    this.controller,
    super.key,
  });

  /// Optional controller to manage the IDE state externally.
  ///
  /// If null, a local controller is created.
  final MontyIdeController? controller;

  @override
  State<MontyIde> createState() => _MontyIdeState();
}

class _MontyIdeState extends State<MontyIde> {
  late final MontyIdeController _controller;
  final CodeLineEditingController _editorController =
      CodeLineEditingController.fromText('def hi(name):\n'
          '    return f"hi {name}"\n\n'
          'print(hi("Monty"))');

  final StreamController<String> _consoleStreamController =
      StreamController<String>.broadcast();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MontyIdeController();
    _controller.addListener(_onControllerChanged);
    _controller.output.listen(_consoleStreamController.add);
    unawaited(_initController());
  }

  void _onControllerChanged() {
    if (_controller.lastErrorLine != null) {
      final lineIndex = _controller.lastErrorLine! - 1;
      final lines = _editorController.text.split('\n');
      if (lineIndex >= 0 && lineIndex < lines.length) {
        final lineText = lines[lineIndex];
        _editorController.selection = CodeLineSelection(
          baseIndex: lineIndex,
          baseOffset: 0,
          extentIndex: lineIndex,
          extentOffset: lineText.length,
        );
      }
    }
  }

  Future<void> _initController() async {
    if (!_controller.isInitialized) {
      await _controller.initialize();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _editorController.dispose();
    _consoleStreamController.close();
    super.dispose();
  }

  void _handleRun() {
    final code = _editorController.text;
    unawaited(_controller.execute(code));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Theme.of(context).secondaryHeaderColor,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => _controller.clearState(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset Interpreter'),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  _consoleStreamController.add('___CLEAR_CONSOLE___');
                },
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Clear Console',
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: MontyEditor(
            controller: _editorController,
            ideController: _controller,
            onRun: _handleRun,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: MontyConsole(
            outputStream: _consoleStreamController.stream,
          ),
        ),
      ],
    );
  }
}
