import 'dart:async';
import 'package:dart_monty_ide/assistant.dart';
import 'package:dart_monty_ide/src/assistant/ide_tool_handler.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/ui/assistant_buffer.dart';
import 'package:dart_monty_ide/src/ui/chat_panel.dart';
import 'package:dart_monty_ide/src/ui/externals_inspector.dart';
import 'package:dart_monty_ide/src/ui/file_explorer.dart';
import 'package:dart_monty_ide/src/ui/monty_console.dart';
import 'package:dart_monty_ide/src/ui/monty_editor.dart';
import 'package:dart_monty_ide/src/ui/variable_inspector.dart';
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

  final MontyVfs vfs;
  final MontyIdeController? controller;
  final WidgetRegistry? registry;

  @override
  State<MontyIde> createState() => _MontyIdeState();
}

class _MontyIdeState extends State<MontyIde> {
  late final MontyIdeController _controller;
  final CodeLineEditingController _editorController = CodeLineEditingController();
  final CodeLineEditingController _assistantCodeController = CodeLineEditingController();
  final GlobalKey<MontyEditorState> _editorKey = GlobalKey<MontyEditorState>();

  String? _currentFilePath;
  bool _isSaving = false;
  bool _showAssistant = true;
  bool _showExternals = false;
  bool _showVariables = false;
  bool _viewingAssistantBuffer = false;
  
  double _explorerWidth = 200;
  double _assistantWidth = 400;
  double _externalsWidth = 300;
  double _variablesWidth = 250;

  int _fileExplorerVersion = 0;
  final StreamController<String> _consoleStreamController = StreamController<String>.broadcast();

  // Assistant Background State
  late final AssistantController _assistant;
  final List<ChatMessage> _assistantMessages = [];
  bool _isAssistantStreaming = false;
  double _assistantTemperature = 0.1;
  String _assistantDebugLog = '';

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MontyIdeController();
    _controller.addListener(_onControllerChanged);
    _controller.output.listen(_consoleStreamController.add);
    _editorController.addListener(_onEditorChanged);
    
    _initAssistant();
    unawaited(_initController());
  }

  void _initAssistant() {
    final handler = IdeToolHandler(vfs: widget.vfs, ideController: _controller);
    _assistant = AssistantController(
      toolHandler: handler,
      llmService: OllamaLlmService(),
      config: LlmConfig(
        provider: LlmProvider.ollama,
        baseUrl: 'http://localhost:11434',
        model: 'gpt-oss:20b',
        temperature: _assistantTemperature,
      ),
      systemPrompt: defaultAssistantPrompt,
    );

    _assistant.events.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event is AssistantTextEvent) {
          if (_assistantMessages.isEmpty || _assistantMessages.last.role != 'assistant' || _assistantMessages.last.isUiOnly) {
            _assistantMessages.add(ChatMessage(role: 'assistant', content: event.text));
          } else {
            _assistantMessages.last.append(event.text);
          }
        } else if (event is ToolCallEvent) {
          _assistantMessages.add(ChatMessage(role: 'assistant', content: '🛠️ Calling tool: ${event.name}...', isUiOnly: true));
          if (event.name == 'run_python' || event.name == 'write_file') {
            final code = (event.arguments['code'] ?? event.arguments['content']) as String?;
            if (code != null) _assistantCodeController.text = code;
          }
        } else if (event is ToolResultEvent) {
          _assistantMessages.add(ChatMessage(role: 'tool', content: event.result.toString(), isUiOnly: false));
          if (event.name == 'write_file') _fileExplorerVersion++;
        } else if (event is AssistantLogEvent) {
          _assistantDebugLog = '${DateTime.now().toIso8601String()}: ${event.message}\n$_assistantDebugLog';
        }
      });
    });
  }

  void _onControllerChanged() {
    final line = _controller.lastErrorLine;
    if (line != null) {
      final lineIndex = line - 1;
      final content = _viewingAssistantBuffer ? _assistantCodeController.text : _editorController.text;
      final lines = content.split('\n');
      if (lineIndex >= 0 && lineIndex < lines.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final targetController = _viewingAssistantBuffer ? _assistantCodeController : _editorController;
          targetController.selection = CodeLineSelection(
            baseIndex: lineIndex, baseOffset: 0, extentIndex: lineIndex, extentOffset: lines[lineIndex].length,
          );
        });
      }
    }
  }

  Timer? _saveTimer;
  void _onEditorChanged() {
    if (_currentFilePath != null) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 1000), () async {
        if (_currentFilePath != null) {
          if (mounted) setState(() => _isSaving = true);
          try {
            await widget.vfs.writeFile(_currentFilePath!, _editorController.text);
          } catch (e) {
            debugPrint('Auto-save error: $e');
          } finally {
            if (mounted) setState(() => _isSaving = false);
          }
        }
      });
    }
  }

  Future<void> _initController() async {
    if (!_controller.isInitialized) await _controller.initialize();
  }

  Future<void> _loadFile(String path) async {
    try {
      final content = await widget.vfs.readFile(path);
      setState(() {
        _currentFilePath = path;
        _editorController.text = content;
        _viewingAssistantBuffer = false;
      });
    } catch (e) {
      debugPrint('Error loading: $e');
    }
  }

  void _handleRun() {
    final code = _viewingAssistantBuffer ? _assistantCodeController.text : _editorController.text;
    unawaited(_controller.execute(code));
  }

  Future<void> _handleAssistantSendMessage(String prompt) async {
    if (_isAssistantStreaming) return;

    final currentCode = _viewingAssistantBuffer ? _assistantCodeController.text : _editorController.text;
    final bufferName = _viewingAssistantBuffer ? 'AI Pilot' : 'Editor';
    final context = 'Current Buffer ($bufferName):\n```python\n$currentCode\n```';

    setState(() {
      _assistantMessages.add(ChatMessage(role: 'user', content: prompt));
      _isAssistantStreaming = true;
    });

    try {
      await _assistant.processPrompt(prompt, context: context);
    } catch (e) {
      setState(() => _assistantMessages.add(ChatMessage(role: 'assistant', content: 'Error: $e')));
    } finally {
      if (mounted) setState(() => _isAssistantStreaming = false);
    }
  }

  void _handleAssistantStop() {
    _assistant.stop();
    setState(() => _isAssistantStreaming = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _explorerWidth,
          child: FileExplorer(
            key: ValueKey('explorer_$_fileExplorerVersion'),
            vfs: widget.vfs,
            onFileSelected: _loadFile,
          ),
        ),
        _HorizontalResizer(
          onDrag: (delta) {
            setState(() {
              _explorerWidth += delta;
              if (_explorerWidth < 100) _explorerWidth = 100;
              if (_explorerWidth > 400) _explorerWidth = 400;
            });
          },
        ),
        Expanded(
          child: Column(
            children: [
              _buildToolbar(),
              Expanded(
                flex: 2,
                child: _viewingAssistantBuffer
                    ? MontyAssistantBuffer(
                        controller: _assistantCodeController,
                        isProcessing: _isAssistantStreaming,
                        onPrompt: _handleAssistantSendMessage,
                        onRun: (code) => unawaited(_controller.execute(code)),
                        onTypeCheck: (code) => unawaited(_controller.typeCheck(code)),
                        onSaveAs: (code) => unawaited(_handleSaveAs(code)),
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
                child: MontyConsole(outputStream: _consoleStreamController.stream),
              ),
            ],
          ),
        ),
        if (_showAssistant) ...[
          _HorizontalResizer(
            onDrag: (delta) {
              setState(() {
                _assistantWidth -= delta;
                if (_assistantWidth < 200) _assistantWidth = 200;
                if (_assistantWidth > 600) _assistantWidth = 600;
              });
            },
          ),
          SizedBox(
            width: _assistantWidth,
            child: ChatPanel(
              vfs: widget.vfs,
              controller: _controller,
              assistant: _assistant,
              messages: _assistantMessages,
              isStreaming: _isAssistantStreaming,
              onSendMessage: _handleAssistantSendMessage,
              onStop: _handleAssistantStop,
              temperature: _assistantTemperature,
              onTemperatureChanged: (v) => setState(() => _assistantTemperature = v),
              debugLog: _assistantDebugLog,
              onCopyToEditor: (code) {
                _editorController.text = code;
                setState(() => _viewingAssistantBuffer = false);
              },
              onClose: () => setState(() => _showAssistant = false),
              onClearChat: () {
                _assistant.clearHistory();
                setState(() => _assistantMessages.clear());
              },
            ),
          ),
        ],
        if (_showVariables) ...[
          _HorizontalResizer(
            onDrag: (delta) {
              setState(() {
                _variablesWidth -= delta;
                if (_variablesWidth < 150) _variablesWidth = 150;
              });
            },
          ),
          SizedBox(
            width: _variablesWidth,
            child: VariableInspector(
              controller: _controller,
              onClose: () => setState(() => _showVariables = false),
            ),
          ),
        ],
        if (_showExternals) ...[
          _HorizontalResizer(
            onDrag: (delta) {
              setState(() {
                _externalsWidth -= delta;
                if (_externalsWidth < 150) _externalsWidth = 150;
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

  Widget _buildToolbar() {
    return Container(
      height: 40,
      color: Theme.of(context).secondaryHeaderColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(onPressed: () => setState(() => _viewingAssistantBuffer = false), icon: Icon(Icons.edit_note, color: !_viewingAssistantBuffer ? Colors.blue : Colors.grey), tooltip: 'Editor'),
            IconButton(onPressed: () => setState(() => _viewingAssistantBuffer = true), icon: Icon(Icons.bolt, color: _viewingAssistantBuffer ? Colors.purple : Colors.grey), tooltip: 'AI Pilot'),
            const SizedBox(width: 8),
            if (_isSaving) const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))),
            IconButton(visualDensity: VisualDensity.compact, onPressed: _handleRun, icon: const Icon(Icons.play_arrow, color: Colors.green, size: 20), tooltip: 'Run'),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () {
              final code = _viewingAssistantBuffer ? _assistantCodeController.text : _editorController.text;
              unawaited(_controller.typeCheck(code));
            }, icon: const Icon(Icons.fact_check_outlined, color: Colors.blue, size: 20), tooltip: 'Type Check'),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () {
              final code = _viewingAssistantBuffer ? _assistantCodeController.text : _editorController.text;
              unawaited(_handleSaveAs(code));
            }, icon: const Icon(Icons.save_alt, color: Colors.blueGrey, size: 20), tooltip: 'Save As'),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _showAssistant = !_showAssistant), icon: const Icon(Icons.chat, size: 20), tooltip: 'Assistant'),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _showVariables = !_showVariables), icon: Icon(_showVariables ? Icons.account_tree : Icons.account_tree_outlined, color: _showVariables ? Colors.orange : null, size: 20), tooltip: 'Variables'),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _showExternals = !_showExternals), icon: Icon(_showExternals ? Icons.info : Icons.info_outline, color: _showExternals ? Colors.blue : null, size: 20), tooltip: 'Externals'),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSaveAs(String code) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save As Python File'),
        content: TextField(controller: nameController, decoration: const InputDecoration(hintText: 'filename.py'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final String fileName = name.endsWith('.py') ? name : '$name.py';
      setState(() => _isSaving = true);
      try {
        await widget.vfs.writeFile(fileName, code);
        setState(() {
          _fileExplorerVersion++;
          _currentFilePath = fileName;
          _editorController.text = code;
          _viewingAssistantBuffer = false;
        });
      } catch (e) {
        debugPrint('Error saving: $e');
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _editorController.dispose();
    _assistantCodeController.dispose();
    _consoleStreamController.close();
    _assistant.dispose();
    super.dispose();
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.isActive, required this.onTap});
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? Colors.blue : Colors.transparent, width: 2))),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isActive ? Colors.blue : Colors.grey)),
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
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: MouseRegion(cursor: SystemMouseCursors.resizeLeftRight, child: Container(width: 4, color: Theme.of(context).dividerColor.withAlpha(25))),
    );
  }
}
