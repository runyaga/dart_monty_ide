import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.showRunButton = true,
    super.key,
  });

  /// The code controller for the editor.
  final CodeLineEditingController controller;

  /// The IDE controller to watch for errors.
  final MontyIdeController? ideController;

  /// Callback when the run button is pressed.
  final VoidCallback onRun;

  /// Whether to show the floating run button.
  final bool showRunButton;

  @override
  State<MontyEditor> createState() => MontyEditorState();
}

/// State for [MontyEditor] to allow external control of search.
class MontyEditorState extends State<MontyEditor> {
  late final CodeFindController _findController;
  bool _showFind = false;

  @override
  void initState() {
    super.initState();
    _findController = CodeFindController(widget.controller);
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
    _findController.dispose();
    super.dispose();
  }

  // Bumped inside setState to mark the element dirty when the gutter
  // indicators live in the IDE controller and not on this state.
  int _rebuildSentinel = 0;

  void _onIdeStateChanged() {
    if (mounted) setState(() => _rebuildSentinel++);
  }

  /// Toggles the visibility of the search bar.
  void toggleFind() {
    setState(() {
      _showFind = !_showFind;
      if (_showFind) {
        _findController
          ..findMode()
          ..focusOnFindInput();
      } else {
        _findController.close();
      }
    });
  }

  void _closeFind() {
    if (_showFind) {
      setState(() {
        _showFind = false;
        _findController.close();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyF, meta: true): _FindIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _CancelIntent(),
      },
      child: Actions(
        actions: {
          _FindIntent: CallbackAction<_FindIntent>(
            onInvoke: (_) => toggleFind(),
          ),
          _CancelIntent: CallbackAction<_CancelIntent>(
            onInvoke: (_) => _closeFind(),
          ),
        },
        child: Column(
          children: [
            Expanded(
              child: CodeEditor(
                controller: widget.controller,
                findController: _findController,
                chunkAnalyzer: const DefaultCodeChunkAnalyzer(),
                wordWrap: false,
                autocompleteSymbols: false,
                style: CodeEditorStyle(
                  fontSize: 14,
                  codeTheme: CodeHighlightTheme(
                    languages: {
                      'python': CodeHighlightThemeMode(mode: langPython),
                    },
                    theme: atomOneDarkTheme,
                  ),
                ),
                findBuilder: (context, controller, readOnly) {
                  if (!_showFind) return const _EmptyPreferredSize();

                  return _MontyFindWidget(
                    controller: controller,
                    onClose: () {
                      setState(() {
                        _showFind = false;
                        controller.close();
                      });
                    },
                  );
                },
                indicatorBuilder:
                    (context, editingController, chunkController, notifier) {
                      return Row(
                        children: [
                          DefaultCodeLineNumber(
                            controller: editingController,
                            notifier: notifier,
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
            if (widget.showRunButton)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
        ),
      ),
    );
  }
}

class _FindIntent extends Intent {
  const _FindIntent();
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}

class _EmptyPreferredSize extends StatelessWidget
    implements PreferredSizeWidget {
  const _EmptyPreferredSize();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  Size get preferredSize => Size.zero;
}

class _MontyFindWidget extends StatelessWidget implements PreferredSizeWidget {
  const _MontyFindWidget({
    required this.controller,
    required this.onClose,
  });

  final CodeFindController controller;
  final VoidCallback onClose;

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    return CodeEditorTapRegion(
      child: Container(
        height: preferredSize.height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: ValueListenableBuilder<CodeFindValue?>(
          valueListenable: controller,
          builder: (context, value, child) {
            final result = value?.result;
            final matches = result?.matches ?? [];
            final current = (result?.index ?? -1) + 1;
            final total = matches.length;

            return Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.findInputController,
                    focusNode: controller.findInputFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Find',
                      isDense: true,
                      contentPadding: EdgeInsets.all(8),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => controller.nextMatch(),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$current / $total',
                  style: const TextStyle(fontSize: 12),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: total > 0 ? controller.previousMatch : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: total > 0 ? controller.nextMatch : null,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
