import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

/// A widget that provides a Python code editor with syntax highlighting and
/// IDE-like features.
class MontyEditor extends StatefulWidget {
  /// Creates a [MontyEditor].
  const MontyEditor({
    required this.controller,
    required this.onRun,
    this.ideController,
    super.key,
  });

  /// The code controller for the editor.
  final CodeLineEditingController controller;

  /// The IDE controller to watch for errors.
  final MontyIdeController? ideController;

  /// Callback when the run button is pressed.
  final VoidCallback onRun;

  @override
  State<MontyEditor> createState() => _MontyEditorState();
}

class _MontyEditorState extends State<MontyEditor> {
  @override
  void initState() {
    super.initState();
    widget.ideController?.addListener(_onIdeStateChanged);
  }

  @override
  void didUpdateWidget(MontyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ideController != widget.ideController) {
      oldWidget.ideController?.removeListener(_onIdeStateChanged);
      widget.ideController?.addListener(_onIdeStateChanged);
    }
  }

  @override
  void dispose() {
    widget.ideController?.removeListener(_onIdeStateChanged);
    super.dispose();
  }

  void _onIdeStateChanged() {
    if (mounted) {
      setState(() {
        // Trigger rebuild to update gutter indicators
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CodeEditor(
            controller: widget.controller,
            wordWrap: false,
            autocompleteSymbols: true,
            style: CodeEditorStyle(
              fontSize: 14,
              codeTheme: CodeHighlightTheme(
                languages: {
                  'python': CodeHighlightThemeMode(mode: langPython),
                },
                theme: atomOneDarkTheme,
              ),
            ),
            indicatorBuilder:
                (context, editingController, chunkController, notifier) {
              return Row(
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                  _ErrorIndicator(
                    notifier: notifier,
                    errorLine: widget.ideController?.lastErrorLine,
                  ),
                  DefaultCodeChunkIndicator(
                    width: 20,
                    controller: chunkController,
                    notifier: notifier,
                  ),
                ],
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).cardColor,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: widget.onRun,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorIndicator extends StatelessWidget {
  const _ErrorIndicator({
    required this.notifier,
    this.errorLine,
  });

  final CodeIndicatorValueNotifier notifier;
  final int? errorLine;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeIndicatorValue?>(
      valueListenable: notifier,
      builder: (context, value, child) {
        if (value == null || errorLine == null) {
          return const SizedBox(width: 20);
        }
        // Monty error line numbers are 1-based.
        // paragraphs[0] is not necessarily line 0, but it has an index.
        // We need to see if any visible paragraph has the error index.
        final targetIndex = errorLine! - 1;

        return Container(
          width: 20,
          alignment: Alignment.topCenter,
          child: Stack(
            children: value.paragraphs.map((p) {
              if (p.index == targetIndex) {
                return Positioned(
                  top: p.offset.dy,
                  left: 0,
                  right: 0,
                  height: p.preferredLineHeight,
                  child: const Icon(Icons.close, color: Colors.red, size: 16),
                );
              }
              return const SizedBox.shrink();
            }).toList(),
          ),
        );
      },
    );
  }
}
