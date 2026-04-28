import 'dart:async';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/ui/assistant_buffer.dart';
import 'package:dart_monty_ide/src/ui/chat_panel.dart';
import 'package:dart_monty_ide/src/ui/externals_inspector.dart';
import 'package:dart_monty_ide/src/ui/file_explorer.dart';
import 'package:dart_monty_ide/src/ui/monty_console.dart';
import 'package:dart_monty_ide/src/ui/monty_editor.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// A full-featured Python IDE widget with file management, Flutter Bridge,
/// and AI Assistant.
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
  final GlobalKey<MontyEditorState> _editorKey = GlobalKey<MontyEditorState>();

  String? _currentFilePath;
  bool _isSaving = false;
  bool _showExternals = false;
  bool _showAssistant = true;
  bool _viewingAssistantBuffer = false;

  double _assistantWidth = 350;
  double _externalsWidth = 250;

  int _fileExplorerVersion = 0;

  final StreamController<String> _consoleStreamController =
      StreamController<String>.broadcast();
  final StreamController<String> _assistantBufferController =
      StreamController<String>.broadcast();

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
        _editorController.selection = CodeLineSelection(
          baseIndex: lineIndex,
          baseOffset: 0,
          extentIndex: lineIndex,
          extentOffset: lines[lineIndex].length,
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
        _viewingAssistantBuffer = false; // Switch to editor when file loaded
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
    _assistantBufferController.close();
    super.dispose();
  }

  void _handleRun() {
    final code = _editorController.text;
    unawaited(_controller.execute(code));
  }

  void _handleCopyToEditor(String code) {
    setState(() {
      _editorController.text = code;
      _viewingAssistantBuffer = false;
    });
  }

  Future<void> _saveFile() async {
    if (_currentFilePath == null) return;
    debugPrint('Saving file: $_currentFilePath');
    setState(() => _isSaving = true);
    try {
      await widget.vfs.writeFile(_currentFilePath!, _editorController.text);
      debugPrint('File saved successfully.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $_currentFilePath'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } on Exception catch (e) {
      debugPrint('Error saving file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleFileWritten() {
    setState(() {
      _fileExplorerVersion++;
    });
  }

  void _handleAssistantCode(String code) {
    setState(() {
      _viewingAssistantBuffer = true;
    });
    _assistantBufferController.add(code);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FileExplorer(
          key: ValueKey('explorer_$_fileExplorerVersion'),
          vfs: widget.vfs,
          onFileSelected: (path) => unawaited(_loadFile(path)),
        ),
        Expanded(
          child: Column(
            children: [
              Container(
                color: Theme.of(context).secondaryHeaderColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _TabButton(
                      label: 'EDITOR',
                      isActive: !_viewingAssistantBuffer,
                      onTap: () =>
                          setState(() => _viewingAssistantBuffer = false),
                    ),
                    _TabButton(
                      label: 'LLM',
                      isActive: _viewingAssistantBuffer,
                      onTap: () =>
                          setState(() => _viewingAssistantBuffer = true),
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
                    ElevatedButton.icon(
                      onPressed: _controller.isExecuting ? null : _handleRun,
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text(
                        'RUN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _currentFilePath == null
                          ? null
                          : () => unawaited(_saveFile()),
                      icon: const Icon(Icons.save, size: 20),
                      tooltip: 'Save File',
                    ),
                    IconButton(
                      onPressed: () => _editorKey.currentState?.toggleFind(),
                      icon: const Icon(Icons.search, size: 20),
                      tooltip: 'Find (CMD+F)',
                    ),
                    const VerticalDivider(width: 20, indent: 10, endIndent: 10),
                    TextButton.icon(
                      onPressed: () => _controller.clearState(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label:
                          const Text('Reset', style: TextStyle(fontSize: 11)),
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
                        setState(() => _showAssistant = !_showAssistant);
                      },
                      icon: Icon(
                        _showAssistant ? Icons.chat : Icons.chat_outlined,
                        size: 20,
                        color: _showAssistant ? Colors.purple : null,
                      ),
                      tooltip: 'Toggle Assistant',
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
                child: _viewingAssistantBuffer
                    ? MontyAssistantBuffer(
                        codeStream: _assistantBufferController.stream,
                      )
                    : MontyEditor(
                        key: _editorKey,
                        controller: _editorController,
                        ideController: _controller,
                        onRun: _handleRun,
                        showRunButton: false,
                      ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: MontyConsole(
                        outputStream: _consoleStreamController.stream,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Container(
                      width: 250,
                      color: Colors.grey[50],
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PREVIEW',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                          const Spacer(),
                          Center(
                            child: MontyProxyWidget(
                              id: 'box_1',
                              registry: _registry,
                              builder: (context, props) {
                                final colorStr = props['color'] as String?;
                                final sizeNum = props['size'] as num?;
                                final size = sizeNum?.toDouble() ?? 40;

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
                          const SizedBox(height: 8),
                          MontyProxyWidget(
                            id: 'label_1',
                            registry: _registry,
                            builder: (context, props) {
                              final text = props['text'] as String?;
                              return Text(
                                text ?? 'Waiting...',
                                style: const TextStyle(fontSize: 11),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_showAssistant) ...[
          _HorizontalResizer(
            onDrag: (delta) {
              setState(() {
                _assistantWidth -= delta;
                if (_assistantWidth < 100) _assistantWidth = 100;
              });
            },
          ),
          SizedBox(
            width: _assistantWidth,
            child: ChatPanel(
              vfs: widget.vfs,
              controller: _controller,
              onCopyToEditor: _handleCopyToEditor,
              onClose: () => setState(() => _showAssistant = false),
              onFileWritten: _handleFileWritten,
              onAssistantCode: _handleAssistantCode,
            ),
          ),
        ],
        if (_showExternals) ...[
          _HorizontalResizer(
            onDrag: (delta) {
              setState(() {
                _externalsWidth -= delta;
                if (_externalsWidth < 100) _externalsWidth = 100;
              });
            },
          ),
          SizedBox(
            width: _externalsWidth,
            child: ExternalsInspector(
              controller: _controller,
              onClose: () => setState(() => _showExternals = false),
            ),
          ),
        ],
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? Colors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.blue : Colors.grey,
          ),
        ),
      ),
    );
  }
}

class _HorizontalResizer extends StatelessWidget {
  const _HorizontalResizer({required this.onDrag, super.key});
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        onDrag(details.delta.dx);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: 4,
          color: Theme.of(context).dividerColor.withAlpha(25),
        ),
      ),
    );
  }
}
