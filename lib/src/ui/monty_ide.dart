import 'dart:async';
import 'package:dart_monty_ide/assistant.dart';
import 'package:dart_monty_ide/src/assistant/ide_tool_handler.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/ui/assistant_buffer.dart';
import 'package:dart_monty_ide/src/ui/chat_panel.dart';
import 'package:dart_monty_ide/src/ui/file_explorer.dart';
import 'package:dart_monty_ide/src/ui/monty_console.dart';
import 'package:dart_monty_ide/src/ui/monty_editor.dart';
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
  final CodeLineEditingController _editorController = CodeLineEditingController();
  final CodeLineEditingController _assistantCodeController = CodeLineEditingController();
  final GlobalKey<MontyEditorState> _editorKey = GlobalKey<MontyEditorState>();

  String? _currentFilePath;
  bool _isSaving = false;
  bool _showAssistant = true;
  bool _viewingAssistantBuffer = false;
  bool _isAssistantProcessing = false;

  final double _assistantWidth = 400;

  int _fileExplorerVersion = 0;
  final StreamController<String> _consoleStreamController = StreamController<String>.broadcast();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MontyIdeController();
    _controller.addListener(_onControllerChanged);
    _controller.output.listen(_consoleStreamController.add);
    unawaited(_initController());
  }

  void _onControllerChanged() {
    final line = _controller.lastErrorLine;
    if (line != null) {
      final lineIndex = line - 1;
      final content = _viewingAssistantBuffer
          ? _assistantCodeController.text
          : _editorController.text;
      final lines = content.split('\n');
      if (lineIndex >= 0 && lineIndex < lines.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final targetController = _viewingAssistantBuffer
              ? _assistantCodeController
              : _editorController;
          targetController.selection = CodeLineSelection(
            baseIndex: lineIndex,
            baseOffset: 0,
            extentIndex: lineIndex,
            extentOffset: lines[lineIndex].length,
          );
        });
      }
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

  Future<void> _handleAssistantPrompt(String prompt) async {
    if (_isAssistantProcessing) return;
    setState(() => _isAssistantProcessing = true);

    final handler = IdeToolHandler(vfs: widget.vfs, ideController: _controller);
    final assistant = AssistantController(
      toolHandler: handler,
      llmService: OllamaLlmService(),
      config: LlmConfig(
        provider: LlmProvider.ollama,
        baseUrl: 'http://localhost:11434',
        model: 'gpt-oss:20b',
      ),
      systemPrompt: defaultAssistantPrompt,
    );

    final subscription = assistant.events.listen((event) {
      if (event is ToolCallEvent) {
        if (event.name == 'run_python' || event.name == 'write_file') {
          final code = (event.arguments['code'] ?? event.arguments['content']) as String?;
          if (code != null) {
            _assistantCodeController.text = code;
          }
        }
      }
    });

    try {
      await assistant.processPrompt(prompt);
    } on Exception catch (e) {
      _assistantCodeController.text = 'Error: $e';
    } finally {
      await subscription.cancel();
      assistant.dispose();
      if (mounted) setState(() => _isAssistantProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FileExplorer(
          key: ValueKey('explorer_$_fileExplorerVersion'),
          vfs: widget.vfs,
          onFileSelected: _loadFile,
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
                        isProcessing: _isAssistantProcessing,
                        onPrompt: _handleAssistantPrompt,
                        onRun: (code) => unawaited(_controller.execute(code)),
                        onTypeCheck: (code) => unawaited(_controller.typeCheck(code)),
                        onSaveAs: (code) => _handleSaveAs(code),
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
        if (_showAssistant) 
          SizedBox(
            width: _assistantWidth,
            child: ChatPanel(
              vfs: widget.vfs,
              controller: _controller,
              onCopyToEditor: (code) {
                _editorController.text = code;
                setState(() => _viewingAssistantBuffer = false);
              },
              onAssistantCode: (code) {
                _assistantCodeController.text = code;
                setState(() => _viewingAssistantBuffer = true);
              },
              onClose: () => setState(() => _showAssistant = false),
            ),
          ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 40,
      color: Theme.of(context).secondaryHeaderColor,
      child: Row(
        children: [
          _TabButton(
            label: 'EDITOR',
            isActive: !_viewingAssistantBuffer,
            onTap: () => setState(() => _viewingAssistantBuffer = false),
          ),
          _TabButton(
            label: 'AI PILOT',
            isActive: _viewingAssistantBuffer,
            onTap: () => setState(() => _viewingAssistantBuffer = true),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              final code = _viewingAssistantBuffer ? _assistantCodeController.text : _editorController.text;
              unawaited(_handleSaveAs(code));
            },
            icon: const Icon(Icons.save_alt, color: Colors.blueGrey),
            tooltip: 'Save As',
          ),
          IconButton(
            onPressed: () {
              final code = _viewingAssistantBuffer ? _assistantCodeController.text : _editorController.text;
              unawaited(_controller.typeCheck(code));
            },
            icon: const Icon(Icons.fact_check_outlined, color: Colors.blue),
            tooltip: 'Type Check',
          ),
          IconButton(
            onPressed: _handleRun,
            icon: const Icon(Icons.play_arrow, color: Colors.green),
            tooltip: 'Run',
          ),
          IconButton(
            onPressed: () => setState(() => _showAssistant = !_showAssistant),
            icon: const Icon(Icons.chat),
            tooltip: 'Assistant',
          ),
        ],
      ),
    );
  }

  Future<void> _handleSaveAs(String code) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save As Python File'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: 'filename.py'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Save'),
          ),
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
      } on Exception catch (e) {
        debugPrint('Error saving: $e');
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _editorController.dispose();
    _assistantCodeController.dispose();
    _consoleStreamController.close();
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
