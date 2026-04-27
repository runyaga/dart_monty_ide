import 'dart:async';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/ui/externals_inspector.dart';
import 'package:dart_monty_ide/src/ui/file_explorer.dart';
import 'package:dart_monty_ide/src/ui/monty_console.dart';
import 'package:dart_monty_ide/src/ui/monty_editor.dart';
import 'package:dart_monty_ide/src/ui/system_prompt_view.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// A full-featured Python IDE widget with file management and Flutter Bridge.
class MontyIde extends StatefulWidget {
  /// Creates a [MontyIde].
  const MontyIde({
    required this.vfs,
    this.controller,
    this.registry,
    super.key,
  });

  /// The VFS to use for file operations.
  final MontyVfs vfs;

  /// Optional controller to manage the IDE state externally.
  final MontyIdeController? controller;

  /// Optional registry for the Flutter bridge.
  final WidgetRegistry? registry;

  @override
  State<MontyIde> createState() => _MontyIdeState();
}

class _MontyIdeState extends State<MontyIde> {
  late final MontyIdeController _controller;
  late final WidgetRegistry _registry;
  final CodeLineEditingController _editorController =
      CodeLineEditingController();

  String? _currentFilePath;
  bool _isSaving = false;
  bool _showExternals = false;

  final StreamController<String> _consoleStreamController =
      StreamController<String>.broadcast();

  final Map<String, String> _examples = {
    '1. The Basics':
        'def welcome(name):\n'
        '    return f"Greetings, {name}! Welcome to Monty IDE."\n\n'
        'print(welcome("Engineer"))\n',
    '2. Data Processing':
        '# List comprehensions and filtering\n'
        'numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]\n'
        'odd_squares = [n**2 for n in numbers if n % 2 != 0]\n\n'
        'print(f"Original: {numbers}")\n'
        'print(f"Odd squares: {odd_squares}")\n'
        'print(f"Sum of squares: {sum(odd_squares)}")\n',
    '3. Persistent State':
        '# Variables and classes persist between "Run" clicks\n'
        'class Counter:\n'
        '    def __init__(self):\n'
        '        self.value = 0\n'
        '    def inc(self):\n'
        '        self.value += 1\n'
        '        return self.value\n\n'
        'if "my_counter" not in globals():\n'
        '    my_counter = Counter()\n'
        '    print("Created new counter instance.")\n'
        'else:\n'
        '    print("Using existing counter instance.")\n\n'
        'print(f"Counter is now: {my_counter.inc()}")\n',
    '4. Algorithms (Fibonacci)':
        'def fib(n):\n'
        '    if n <= 1: return n\n'
        '    return fib(n-1) + fib(n-2)\n\n'
        'n = 10\n'
        'print(f"Generating Fibonacci sequence of length {n}:")\n'
        'print([fib(i) for i in range(n)])\n',
    '5. Flutter Bridge Demo':
        '# Drive the preview area widgets!\n'
        'print("🎨 Updating Flutter widgets...")\n'
        'flutter.set_color("box_1", "teal")\n'
        'flutter.set_prop("label_1", "text", "Updated from Monty Python!")\n'
        'flutter.set_prop("box_1", "size", 100)\n'
        'print("Done.")\n',
  };

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MontyIdeController();
    _registry = widget.registry ?? WidgetRegistry();
    _controller.addListener(_onControllerChanged);
    _controller.output.listen(_consoleStreamController.add);
    _editorController.addListener(_onEditorChanged);
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

  Timer? _saveTimer;
  void _onEditorChanged() {
    if (_currentFilePath != null) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 500), () async {
        if (_currentFilePath != null) {
          if (mounted) setState(() => _isSaving = true);
          await widget.vfs.writeFile(_currentFilePath!, _editorController.text);
          if (mounted) {
            setState(() => _isSaving = false);
          }
        }
      });
    }
  }

  Future<void> _initController() async {
    if (!_controller.isInitialized) {
      await _controller.initialize();
    }
  }

  Future<void> _loadFile(String path) async {
    try {
      final content = await widget.vfs.readFile(path);
      setState(() {
        _currentFilePath = path;
        _editorController.text = content;
      });
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading file: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _editorController.removeListener(_onEditorChanged);
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
    return DefaultTabController(
      length: 2,
      child: Row(
        children: [
          FileExplorer(
            vfs: widget.vfs,
            onFileSelected: _loadFile,
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  color: Theme.of(context).secondaryHeaderColor,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        tabs: [
                          Tab(text: 'EDITOR'),
                          Tab(text: 'SYSTEM PROMPT'),
                        ],
                      ),
                      const VerticalDivider(width: 20),
                      if (_currentFilePath != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            _currentFilePath!,
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Text(
                            'Scratchpad',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      if (_isSaving)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      const Spacer(),
                      DropdownButton<String>(
                        hint: const Text(
                          'Templates',
                          style: TextStyle(fontSize: 12),
                        ),
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down, size: 18),
                        style: const TextStyle(fontSize: 12, color: Colors.black),
                        items: _examples.keys.map((String name) {
                          return DropdownMenuItem<String>(
                            value: name,
                            child: Text(name),
                          );
                        }).toList(),
                        onChanged: (String? name) {
                          if (name != null) {
                            setState(() {
                              _editorController.text = _examples[name]!;
                            });
                          }
                        },
                      ),
                      const VerticalDivider(width: 20, indent: 10, endIndent: 10),
                      TextButton.icon(
                        onPressed: () => _controller.clearState(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text(
                          'Reset Interpreter',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          _consoleStreamController.add('___CLEAR_CONSOLE___');
                        },
                        icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                        tooltip: 'Clear Console',
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _showExternals = !_showExternals);
                        },
                        icon: Icon(
                          _showExternals ? Icons.info : Icons.info_outline,
                          size: 20,
                          color: _showExternals ? Colors.blue : null,
                        ),
                        tooltip: 'Show Externals',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: TabBarView(
                    children: [
                      MontyEditor(
                        controller: _editorController,
                        ideController: _controller,
                        onRun: _handleRun,
                      ),
                      const SystemPromptView(),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: MontyConsole(
                          outputStream: _consoleStreamController.stream,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      // Preview Area for Bridge Demo
                      Container(
                        width: 300,
                        color: Colors.grey[50],
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'LIVE PREVIEW',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: MontyProxyWidget(
                                id: 'box_1',
                                registry: _registry,
                                builder: (context, props) {
                                  final colorStr = props['color'] as String?;
                                  final sizeNum = props['size'] as num?;
                                  final size = sizeNum?.toDouble() ?? 60.0;

                                  Color color = Colors.grey[300]!;
                                  if (colorStr == 'teal') color = Colors.teal;
                                  if (colorStr == 'red') color = Colors.red;

                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 500),
                                    width: size,
                                    height: size,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 20),
                            MontyProxyWidget(
                              id: 'label_1',
                              registry: _registry,
                              builder: (context, props) {
                                final text = props['text'] as String?;
                                return Text(
                                  text ?? 'Waiting for Python...',
                                  style: const TextStyle(fontSize: 14),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_showExternals) ExternalsInspector(controller: _controller),
        ],
      ),
    );
  }
}
