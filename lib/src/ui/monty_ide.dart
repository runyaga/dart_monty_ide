import 'dart:async';

import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/assistant.dart';
import 'package:dart_monty_ide/src/assistant/ide_tool_handler.dart';
import 'package:dart_monty_ide/src/assistant/system_prompt_builder.dart';
import 'package:dart_monty_ide/src/bridge/prompt_extension.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/ui/assistant_buffer.dart';
import 'package:dart_monty_ide/src/ui/chat_panel.dart';
import 'package:dart_monty_ide/src/ui/externals_inspector.dart';
import 'package:dart_monty_ide/src/ui/file_explorer.dart';
import 'package:dart_monty_ide/src/ui/monty_console.dart';
import 'package:dart_monty_ide/src/ui/monty_editor.dart';
import 'package:dart_monty_ide/src/ui/monty_ui_panel.dart';
import 'package:dart_monty_ide/src/spikes/wind_particle_demo.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';
import 'package:hhg_flchart_flutter/hhg_flchart_flutter.dart';
import 'package:hhg_map_flutter/hhg_map_flutter.dart';
import 'package:hhg_svg_flutter/hhg_svg_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:re_editor/re_editor.dart';

/// A full-featured Python IDE widget with file management and Flutter Bridge.
class MontyIde extends StatefulWidget {
  /// Creates a [MontyIde].
  const MontyIde({
    required this.vfs,
    this.controller,
    this.registry,
    this.svgHostApi,
    this.mapHostApi,
    this.chartHostApi,
    super.key,
  });

  /// Virtual filesystem backing the file explorer and script loading.
  final MontyVfs vfs;

  /// Optional pre-configured IDE controller; one is created if omitted.
  final MontyIdeController? controller;

  /// Optional widget registry shared with the running script.
  final WidgetRegistry? registry;

  /// Optional SVG host api to render `svg_render(...)` output in the
  /// editor area's preview panel. When `null`, no preview is shown.
  final JovialSvgHostApi? svgHostApi;

  /// Optional map host api. When non-null, the UI panel mounts a map
  /// widget driven by `map_*` host function calls.
  final FlutterMapHostApi? mapHostApi;

  /// Optional chart host api. When non-null, the UI panel mounts a chart
  /// widget driven by `chart_*` host function calls.
  final FlChartHostApiImpl? chartHostApi;

  @override
  State<MontyIde> createState() => _MontyIdeState();
}

class _MontyIdeState extends State<MontyIde> {
  late final MontyIdeController _controller;

  /// Resolved live from `_controller.extensions` so a Reset Interpreter
  /// (which swaps in fresh instances) is picked up automatically on the
  /// next rebuild.
  EventLoopExtension? get _eventLoop {
    final exts = _controller.extensions ?? const <MontyExtension>[];
    for (final e in exts) {
      if (e is EventLoopExtension) return e;
    }

    return null;
  }

  MontyPromptExtension? get _promptExtension {
    final exts = _controller.extensions ?? const <MontyExtension>[];
    for (final e in exts) {
      if (e is MontyPromptExtension) return e;
    }

    return null;
  }

  final CodeLineEditingController _editorController =
      CodeLineEditingController();
  final CodeLineEditingController _assistantCodeController =
      CodeLineEditingController();
  final GlobalKey<MontyEditorState> _editorKey = GlobalKey<MontyEditorState>();

  String? _currentFilePath;
  bool _isSaving = false;
  // Default closed — opening it triggers the Ollama probe and shows
  // the "Can't reach Ollama" banner when no local Ollama is running.
  // Users who want the AI Pilot click the chat icon to open it.
  bool _showAssistant = false;
  bool _showExternals = false;
  bool _showFileExplorer = true;
  bool _showUiPanel = false;
  bool _viewingAssistantBuffer = false;

  double _explorerWidth = 200;
  double _assistantWidth = 400;
  double _externalsWidth = 300;
  double _uiPanelWidth = 320;

  int _fileExplorerVersion = 0;
  // Bumped inside setState to mark the element dirty when reactive state
  // lives in the IDE controller and not on this state.
  int _rebuildSentinel = 0;
  final StreamController<String> _consoleStreamController =
      StreamController<String>.broadcast();

  // Assistant Background State
  late final AssistantController _assistant;
  final List<ChatMessage> _assistantMessages = [];
  bool _isAssistantStreaming = false;
  double _assistantTemperature = 0.1;
  String _assistantDebugLog = '';

  /// Tri-state Ollama reachability — null until the first probe completes.
  bool? _ollamaReachable;

  /// Debounced "script running" banner state. We only flip this after the
  /// run has been in flight for >500ms so fast scripts (hello.py-style)
  /// don't flash the banner on every Run.
  bool _showRunBanner = false;
  Timer? _runBannerDelay;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MontyIdeController();
    _controller.addListener(_onControllerChanged);
    _controller.output.listen(_consoleStreamController.add);
    _editorController.addListener(_onEditorChanged);

    // Auto-open the Monty UI panel when an svg_render(...) arrives so
    // the user doesn't have to click the toggle to see their output.
    // After they close the panel manually, future SVGs re-open it —
    // that matches the el_emit-driven mental model: any UI-bound
    // output pops the panel.
    widget.svgHostApi?.addListener(_onSvgRendered);
    widget.chartHostApi?.addListener(_onChartRendered);

    _initAssistant();
    unawaited(_initController());
    unawaited(_probeOllama());
  }

  void _onSvgRendered() {
    if (!mounted) return;
    if (!_showUiPanel) {
      setState(() => _showUiPanel = true);
    }
  }

  void _onChartRendered() {
    if (!mounted) return;
    if (!_showUiPanel) {
      setState(() => _showUiPanel = true);
    }
  }

  /// Best-effort probe so the chat panel can show a banner when the Pilot
  /// can't reach Ollama. We use `/api/tags` (a simple GET — no preflight)
  /// because if it succeeds we know origin + CORS + reachability are all
  /// fine.
  ///
  /// Failures retry with backoff up to [maxAttempts] times before flipping
  /// `_ollamaReachable` to `false` — early failures are common (browser
  /// private-network-access prompt still up, Ollama still starting,
  /// transient CORS preflight cache) and shouldn't immediately scare the
  /// user with a banner.
  Future<void> _probeOllama({int attempt = 1, int maxAttempts = 4}) async {
    try {
      final resp = await http
          .get(Uri.parse('http://localhost:11434/api/tags'))
          .timeout(const Duration(seconds: 3));
      if (mounted) setState(() => _ollamaReachable = resp.statusCode < 500);
    } on Object catch (_) {
      if (attempt < maxAttempts) {
        // 2s, 4s, 6s = ~12s grace before the banner appears.
        await Future<void>.delayed(Duration(seconds: attempt * 2));
        if (mounted) {
          await _probeOllama(attempt: attempt + 1, maxAttempts: maxAttempts);
        }
      } else if (mounted) {
        setState(() => _ollamaReachable = false);
      }
    }
  }

  void _initAssistant() {
    final handler = IdeToolHandler(vfs: widget.vfs, ideController: _controller);
    _assistant = AssistantController(
      toolHandler: handler,
      llmService: OllamaLlmService(),
      config: LlmConfig(
        baseUrl: 'http://localhost:11434',
        model: 'gpt-oss:20b',
        temperature: _assistantTemperature,
      ),
      systemPromptBuilder: _buildSystemPrompt,
    );

    _assistant.events.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event is AssistantTextEvent) {
          if (_assistantMessages.isEmpty ||
              _assistantMessages.last.role != 'assistant' ||
              _assistantMessages.last.isUiOnly) {
            _assistantMessages.add(
              ChatMessage(role: 'assistant', content: event.text),
            );
          } else {
            _assistantMessages.last.append(event.text);
          }
        } else if (event is ToolCallEvent) {
          _assistantMessages.add(
            ChatMessage(
              role: 'assistant',
              content: '🛠️ Calling tool: ${event.name}...',
              isUiOnly: true,
            ),
          );
          if (event.name == 'run_python' || event.name == 'write_file') {
            final code =
                (event.arguments['code'] ?? event.arguments['content'])
                    as String?;
            if (code != null) _assistantCodeController.text = code;
          }
        } else if (event is ToolResultEvent) {
          _assistantMessages.add(
            ChatMessage(
              role: 'tool',
              content: event.result?.toString() ?? '',
            ),
          );
          if (event.name == 'write_file') _fileExplorerVersion++;
        } else if (event is AssistantLogEvent) {
          _assistantDebugLog =
              '${DateTime.now().toIso8601String()}: ${event.message}\n'
              '$_assistantDebugLog';
        }
      });
    });
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
          (_viewingAssistantBuffer
                  ? _assistantCodeController
                  : _editorController)
              .selection = CodeLineSelection(
            baseIndex: lineIndex,
            baseOffset: 0,
            extentIndex: lineIndex,
            extentOffset: lines[lineIndex].length,
          );
        });
      }
    }
    // Debounce the "script running" banner: only show if a run has been
    // in flight for >500ms.
    if (_controller.isExecuting) {
      if (!_showRunBanner && _runBannerDelay == null) {
        _runBannerDelay = Timer(const Duration(milliseconds: 500), () {
          _runBannerDelay = null;
          if (mounted && _controller.isExecuting) {
            setState(() => _showRunBanner = true);
          }
        });
      }
    } else {
      _runBannerDelay?.cancel();
      _runBannerDelay = null;
      _showRunBanner = false;
    }
    // Trigger a rebuild so _eventLoop / _promptExtension getters re-resolve
    // after Reset Interpreter swapped in fresh extension instances.
    // The setState body bumps a sentinel so dcm's no-empty-block sees
    // a real statement; the value is otherwise unused.
    if (mounted) setState(() => _rebuildSentinel++);
  }

  Timer? _saveTimer;
  void _onEditorChanged() {
    if (_currentFilePath != null) {
      _saveTimer?.cancel();
      _saveTimer = Timer(
        const Duration(milliseconds: 1000),
        () => unawaited(_autoSave()),
      );
    }
  }

  Future<void> _autoSave() async {
    if (_currentFilePath == null) return;
    if (mounted) setState(() => _isSaving = true);
    try {
      await widget.vfs.writeFile(
        _currentFilePath!,
        _editorController.text,
      );
    } on Object catch (e) {
      debugPrint('Auto-save error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _initController() async {
    if (!_controller.isInitialized) await _controller.initialize();
    if (_currentFilePath != null) return;
    try {
      final files = await widget.vfs.listFiles();
      debugPrint('[_initController] vfs files = $files');
      if (files.contains('onboarding.txt')) {
        debugPrint('[_initController] auto-loading onboarding.txt');
        await _loadFile('onboarding.txt');
      } else {
        debugPrint('[_initController] onboarding.txt NOT in file list');
      }
    } on Object catch (e, st) {
      debugPrint('[_initController] ERROR: $e\n$st');
    }
  }

  Future<void> _loadFile(String path) async {
    debugPrint('[_loadFile] path=$path');
    try {
      final content = await widget.vfs.readFile(path);
      debugPrint('[_loadFile] read ${content.length} bytes');
      setState(() {
        _currentFilePath = path;
        _editorController.text = content;
        _viewingAssistantBuffer = false;
      });
      debugPrint(
        '[_loadFile] setState done; '
        'editor.text length=${_editorController.text.length}',
      );
    } on Object catch (e, st) {
      debugPrint('[_loadFile] ERROR for $path: $e\n$st');
    }
  }

  /// Strict mode: when on, Run pre-typechecks via Monty.typeCheck
  /// against the auto-generated host-function stubs. Type errors abort
  /// before execution. Toggle in the toolbar (rule_folded icon).
  bool _strictMode = false;

  void _handleRun() {
    final code = _viewingAssistantBuffer
        ? _assistantCodeController.text
        : _editorController.text;
    // Each Run is a fresh take — drop any prompt fragments the prior
    // script registered.
    _promptExtension?.clear();
    unawaited(_controller.execute(code, strict: _strictMode));
  }

  Future<void> _handleAssistantSendMessage(String prompt) async {
    if (_isAssistantStreaming) return;

    final currentCode = _viewingAssistantBuffer
        ? _assistantCodeController.text
        : _editorController.text;
    final bufferName = _viewingAssistantBuffer ? 'AI Pilot' : 'Editor';
    final context =
        'Current Buffer ($bufferName):\n```python\n$currentCode\n```';

    setState(() {
      _assistantMessages.add(ChatMessage(role: 'user', content: prompt));
      _isAssistantStreaming = true;
    });

    try {
      await _assistant.processPrompt(prompt, context: context);
      if (mounted) setState(() => _ollamaReachable = true);
    } on Object catch (e) {
      setState(
        () => _assistantMessages.add(
          ChatMessage(role: 'assistant', content: 'Error: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAssistantStreaming = false);
      // Re-probe so the banner clears (or appears) without restart.
      unawaited(_probeOllama());
    }
  }

  void _handleAssistantStop() {
    _assistant.stop();
    setState(() => _isAssistantStreaming = false);
  }

  /// Composes the AI Pilot system prompt for the next turn.
  /// See [buildSystemPrompt] for the layering rules.
  String _buildSystemPrompt() => buildSystemPrompt(
    basePrompt: defaultAssistantPrompt,
    extensions: _controller.extensions,
    scriptFragments: _promptExtension?.fragments ?? const [],
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (_showFileExplorer) ...[
          SizedBox(
            width: _explorerWidth,
            child: FileExplorer(
              key: ValueKey('explorer_$_fileExplorerVersion'),
              vfs: widget.vfs,
              onFileSelected: (path) => unawaited(_loadFile(path)),
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
        ],
        Expanded(
          child: Column(
            children: [
              _buildToolbar(),
              if (_showRunBanner) _buildScriptRunningBanner(),
              Expanded(
                flex: 2,
                child: _viewingAssistantBuffer
                    ? MontyAssistantBuffer(
                        controller: _assistantCodeController,
                        isProcessing: _isAssistantStreaming,
                        onPrompt: (prompt) =>
                            unawaited(_handleAssistantSendMessage(prompt)),
                        onRun: (code) => unawaited(_controller.execute(code)),
                        onTypeCheck: (code) =>
                            unawaited(_controller.typeCheck(code)),
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
                child: MontyConsole(
                  outputStream: _consoleStreamController.stream,
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
              onSendMessage: (prompt) =>
                  unawaited(_handleAssistantSendMessage(prompt)),
              onStop: _handleAssistantStop,
              ollamaReachable: _ollamaReachable,
              temperature: _assistantTemperature,
              onTemperatureChanged: (v) =>
                  setState(() => _assistantTemperature = v),
              debugLog: _assistantDebugLog,
              onCopyToEditor: (code) {
                _editorController.text = code;
                setState(() => _viewingAssistantBuffer = false);
              },
              onClose: () => setState(() => _showAssistant = false),
              onClearChat: () {
                _assistant.clearHistory();
                setState(_assistantMessages.clear);
              },
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
        if (_showUiPanel && _eventLoop != null) ...[
          _HorizontalResizer(
            onDrag: (delta) {
              setState(() {
                _uiPanelWidth -= delta;
                if (_uiPanelWidth < 200) _uiPanelWidth = 200;
                if (_uiPanelWidth > 600) _uiPanelWidth = 600;
              });
            },
          ),
          SizedBox(
            width: _uiPanelWidth,
            child: MontyUiPanel(
              eventLoop: _eventLoop!,
              onClose: () => setState(() => _showUiPanel = false),
              svgHostApi: widget.svgHostApi,
              mapHostApi: widget.mapHostApi,
              chartHostApi: widget.chartHostApi,
            ),
          ),
        ],
      ],
    );
  }

  /// Shown when a script is mid-execution. For event-loop scripts (which
  /// block forever on `el_recv`) this is the *only* visible signal that
  /// the bridge is locked, so a fresh Run on a different file silently
  /// fails. Surfaces the state + a one-click Reset.
  Widget _buildScriptRunningBanner() {
    final eventLoopActive =
        _eventLoop?.isWaiting == true || _eventLoop?.lastEmitted != null;
    final message = eventLoopActive
        ? 'Event-loop script is running. New runs are blocked until you reset.'
        : 'A script is running.';

    return Material(
      color: Colors.amber.shade100,
      child: InkWell(
        onTap: _controller.clearState,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.orange.shade800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: Colors.brown.shade900, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _controller.clearState,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Reset'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
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
            IconButton(
              onPressed: () => setState(() => _viewingAssistantBuffer = false),
              icon: Icon(
                Icons.edit_note,
                color: !_viewingAssistantBuffer ? Colors.blue : Colors.grey,
              ),
              tooltip: 'Editor',
            ),
            IconButton(
              onPressed: () => setState(() => _viewingAssistantBuffer = true),
              icon: Icon(
                Icons.bolt,
                color: _viewingAssistantBuffer ? Colors.purple : Colors.grey,
              ),
              tooltip: 'AI Pilot',
            ),
            const SizedBox(width: 8),
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _handleRun,
              icon: const Icon(Icons.play_arrow, color: Colors.green, size: 20),
              tooltip: 'Run',
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _strictMode = !_strictMode),
              icon: Icon(
                _strictMode ? Icons.shield : Icons.shield_outlined,
                color: _strictMode ? Colors.green.shade800 : Colors.grey,
                size: 20,
              ),
              tooltip: _strictMode
                  ? 'Strict mode ON — Run will type-check first'
                  : 'Strict mode OFF — Run executes without typechecking',
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final code = _viewingAssistantBuffer
                    ? _assistantCodeController.text
                    : _editorController.text;
                unawaited(_controller.typeCheck(code));
              },
              icon: const Icon(
                Icons.fact_check_outlined,
                color: Colors.blue,
                size: 20,
              ),
              tooltip: 'Type Check',
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final code = _viewingAssistantBuffer
                    ? _assistantCodeController.text
                    : _editorController.text;
                unawaited(_handleSaveAs(code));
              },
              icon: const Icon(
                Icons.save_alt,
                color: Colors.blueGrey,
                size: 20,
              ),
              tooltip: 'Save As',
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  setState(() => _showFileExplorer = !_showFileExplorer),
              icon: Icon(
                _showFileExplorer ? Icons.folder_open : Icons.folder,
                color: _showFileExplorer ? Colors.blue : null,
                size: 20,
              ),
              tooltip: _showFileExplorer
                  ? 'Hide files'
                  : 'Show files',
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _showAssistant = !_showAssistant),
              icon: const Icon(Icons.chat, size: 20),
              tooltip: 'Assistant',
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _showExternals = !_showExternals),
              icon: Icon(
                _showExternals ? Icons.info : Icons.info_outline,
                color: _showExternals ? Colors.blue : null,
                size: 20,
              ),
              tooltip: 'Externals',
            ),
            if (_eventLoop != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _showUiPanel = !_showUiPanel),
                icon: Icon(
                  _showUiPanel
                      ? Icons.smart_display
                      : Icons.smart_display_outlined,
                  color: _showUiPanel ? Colors.purple : null,
                  size: 20,
                ),
                tooltip: 'Monty UI Panel',
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WindParticleDemoPage(),
                ),
              ),
              icon: const Icon(Icons.air, size: 20),
              tooltip: 'Wind particle spike',
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _controller.clearState,
              icon: const Icon(Icons.restart_alt, color: Colors.red, size: 20),
              tooltip:
                  'Reset Interpreter '
                  '(cancels running scripts, clears UI + console)',
            ),
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
      final fileName = name.endsWith('.py') ? name : '$name.py';
      setState(() => _isSaving = true);
      try {
        await widget.vfs.writeFile(fileName, code);
        setState(() {
          _fileExplorerVersion++;
          _currentFilePath = fileName;
          _editorController.text = code;
          _viewingAssistantBuffer = false;
        });
      } on Object catch (e) {
        debugPrint('Error saving: $e');
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    widget.svgHostApi?.removeListener(_onSvgRendered);
    widget.chartHostApi?.removeListener(_onChartRendered);
    _saveTimer?.cancel();
    _runBannerDelay?.cancel();
    _editorController.dispose();
    _assistantCodeController.dispose();
    unawaited(_consoleStreamController.close());
    _assistant.dispose();
    super.dispose();
  }
}

class _HorizontalResizer extends StatelessWidget {
  const _HorizontalResizer({required this.onDrag});
  final ValueChanged<double> onDrag;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
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
