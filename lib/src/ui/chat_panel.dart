import 'dart:async';
import 'dart:convert';
import 'package:dart_monty_ide/src/assistant/assistant_controller.dart';
import 'package:dart_monty_ide/src/assistant/assistant_tool_handler.dart';
import 'package:dart_monty_ide/src/assistant/default_prompt.dart';
import 'package:dart_monty_ide/src/assistant/ide_tool_handler.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:dart_monty_ide/src/llm/ollama_service.dart';
import 'package:dart_monty_ide/src/llm/open_responses_service.dart';
import 'package:dart_monty_ide/src/ui/system_prompt_view.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:rxdart/rxdart.dart';

/// A message in the chat.
class ChatMessage {
  /// Creates a [ChatMessage].
  ChatMessage({
    required this.role,
    String content = '',
    this.isUiOnly = false,
    this.toolCallId,
    this.toolCalls,
  }) : _content = content {
    // Throttle the UI updates to every 100ms for smoother markdown parsing.
    _throttledStream = _contentController.stream
        .throttleTime(const Duration(milliseconds: 100), trailing: true);
  }

  /// Role of the message sender.
  final String role;

  /// Whether this message is for UI display only and not sent to the LLM.
  final bool isUiOnly;

  /// Optional ID if this is a tool result.
  final String? toolCallId;

  /// Optional list of tool calls if this is an assistant message.
  final List<LlmToolCall>? toolCalls;

  String _content;

  /// Current content of the message.
  String get content => _content;

  final StreamController<String> _contentController =
      StreamController<String>.broadcast();

  late final Stream<String> _throttledStream;

  /// Stream of content updates (throttled for performance).
  Stream<String> get contentStream => _throttledStream;

  /// Appends text to the message and notifies listeners.
  void append(String text) {
    _content += text;
    _contentController.add(_content);
  }

  /// Closes the content stream.
  void dispose() {
    _contentController.close();
  }
}

/// A panel for interacting with an LLM with tool support.
class ChatPanel extends StatefulWidget {
  /// Creates a [ChatPanel].
  const ChatPanel({
    required this.vfs,
    required this.controller,
    required this.onCopyToEditor,
    required this.onClose,
    this.onFileWritten,
    this.onAssistantCode,
    super.key,
  });

  /// The VFS for file operations.
  final MontyVfs vfs;

  /// The Monty IDE controller for code execution.
  final MontyIdeController controller;

  /// Callback when code should be copied to the editor.
  final ValueChanged<String> onCopyToEditor;

  /// Callback when the panel should be closed.
  final VoidCallback onClose;

  /// Callback when a file is written by a tool.
  final VoidCallback? onFileWritten;

  /// Callback when the assistant generates or runs code.
  final ValueChanged<String>? onAssistantCode;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final TextEditingController _ollamaUrlController =
      TextEditingController(text: 'http://localhost:11434');
  final TextEditingController _modelController =
      TextEditingController(text: 'gpt-oss:20b');

  LlmProvider _provider = LlmProvider.ollama;
  bool _isStreaming = false;
  bool _showSettings = false;
  bool _showDebug = false;
  String _lastDebugLog = '';

  // RECURSION SAFETY: Track tool call count and history to prevent loops.
  int _toolCallCount = 0;
  final Set<String> _toolCallHistory = {};

  late LlmService _ollamaService;
  late LlmService _openResponsesService;

  @override
  void initState() {
    super.initState();
    _ollamaService = OllamaLlmService();
    _openResponsesService = OpenResponsesLlmService();
    unawaited(_logDebug('Chat initialized.'));
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _ollamaUrlController.dispose();
    _modelController.dispose();
    _ollamaService.dispose();
    _openResponsesService.dispose();
    for (final m in _messages) {
      m.dispose();
    }
    super.dispose();
  }

  LlmService get _currentService =>
      _provider == LlmProvider.ollama ? _ollamaService : _openResponsesService;

  List<LlmTool> get _tools => [
        const LlmTool(
          name: 'type_check',
          description:
              'Performs static analysis on the code and returns a list of typing errors. ALWAYS call this before run_python.',
          parameters: {
            'type': 'object',
            'properties': {
              'code': {
                'type': 'string',
                'description': 'The Python code to type-check.',
              },
            },
            'required': ['code'],
          },
        ),
        const LlmTool(
          name: 'run_python',
          description:
              'Executes Monty Python code in the sandbox and returns output. Only call if type_check returns no errors.',
          parameters: {
            'type': 'object',
            'properties': {
              'code': {
                'type': 'string',
                'description': 'The Python code to execute.',
              },
            },
            'required': ['code'],
          },
        ),
        const LlmTool(
          name: 'write_file',
          description: 'Creates or updates a file in the workspace.',
          parameters: {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': 'The filename (e.g. "script.py").',
              },
              'content': {
                'type': 'string',
                'description': 'The text content to write.',
              },
            },
            'required': ['path', 'content'],
          },
        ),
      ];

  Future<void> _sendMessage() async {
    final prompt = _inputController.text.trim();
    if (prompt.isEmpty || _isStreaming) return;

    _inputController.clear();
    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(role: 'user', content: prompt));
        _isStreaming = true;
        _toolCallCount = 0; // Reset safety counters
        _toolCallHistory.clear();
      });
    }

    _scrollToBottom(force: true);
    await _getLlmResponse();
  }

  Future<void> _getLlmResponse() async {
    // Check if we hit the turn limit to prevent infinite loops
    if (_toolCallCount >= 10) {
      await _logDebug('Turn limit reached. Stopping tool chain.');
      if (mounted) {
        setState(() => _isStreaming = false);
        _messages.add(ChatMessage(
          role: 'assistant',
          content: '⚠️ Stopping: Verification turn limit (10) reached.',
        ));
      }
      return;
    }

    String sysPrompt;
    try {
      sysPrompt = await widget.vfs.readFile('system_prompt.txt');
    } on Exception catch (e) {
      sysPrompt = defaultAssistantPrompt;
      await _logDebug('Failed to read system_prompt.txt: $e');
    }

    // Filter history to exclude UI-only status messages.
    final history = [
      {'role': 'system', 'content': sysPrompt},
      ..._messages.where((m) => !m.isUiOnly).map(
        (m) {
          final map = <String, dynamic>{
            'role': m.role,
            'content': m.content,
          };
          if (m.toolCallId != null) {
            map['tool_call_id'] = m.toolCallId;
          }
          if (m.toolCalls != null) {
            map['tool_calls'] = m.toolCalls!
                .map((tc) => {
                      'id': tc.id,
                      'type': 'function',
                      'function': {
                        'name': tc.name,
                        'arguments': tc.arguments,
                      }
                    })
                .toList();
          }
          return map;
        },
      ),
    ];

    await _logDebug(
        'SENDING HISTORY TO LLM (${history.length} messages):\n${const JsonEncoder.withIndent('  ').convert(history)}');

    final config = LlmConfig(
      provider: _provider,
      baseUrl: _ollamaUrlController.text.trim(),
      model: _modelController.text.trim(),
    );

    final assistantMsgContent = ChatMessage(role: 'assistant');
    if (mounted) {
      setState(() {
        _messages.add(assistantMsgContent);
      });
    }

    await _logDebug(
      'Turn ${_toolCallCount + 1}: Requesting response from ${config.model}',
    );

    final toolCalls = <LlmToolCall>[];
    try {
      final stream = _currentService.streamResponse(
        messages: history,
        config: config,
        tools: _tools,
      );

      await for (final chunk in stream) {
        if (!mounted) break;
        if (chunk.text != null) {
          assistantMsgContent.append(chunk.text!);
        }
        if (chunk.toolCalls != null) {
          toolCalls.addAll(chunk.toolCalls!);
        }
        _scrollToBottom();
      }

      if (toolCalls.isNotEmpty) {
        await _logDebug('Received ${toolCalls.length} tool calls');

        final assistantToolCallMsg = ChatMessage(
          role: 'assistant',
          content: assistantMsgContent.content,
          toolCalls: toolCalls,
          isUiOnly: false,
        );

        if (_messages.isNotEmpty) {
          _messages.removeLast();
        }
        _messages.add(assistantToolCallMsg);

        _toolCallCount++;
        for (final call in toolCalls) {
          final callSig = '${call.name}:${jsonEncode(call.arguments)}';
          if (_toolCallHistory.contains(callSig)) {
            await _logDebug('Loop detected: LLM repeated call $callSig');
            assistantToolCallMsg
                .append('\n\n⚠️ Loop detected: Stopping execution.');
            if (mounted) setState(() => _isStreaming = false);
            return;
          }
          _toolCallHistory.add(callSig);
          await _handleToolCall(call);
        }
        if (mounted) await _getLlmResponse();
      } else {
        await _logDebug('No tool calls received, sequence finished.');
      }
    } on Exception catch (e) {
      await _logDebug('LLM Error: $e');
      if (mounted) {
        assistantMsgContent.append('\n\n**Error:** $e');
      }
    } finally {
      if (mounted && toolCalls.isEmpty) {
        setState(() => _isStreaming = false);
      }
    }
  }

  Future<void> _logDebug(String text) async {
    final entry = '${DateTime.now().toIso8601String()}: $text';
    if (mounted) {
      setState(() {
        _lastDebugLog = '$entry\n$_lastDebugLog';
        if (_lastDebugLog.length > 30000) {
          _lastDebugLog = _lastDebugLog.substring(0, 30000);
        }
      });
    }
    try {
      String current = '';
      try {
        current = await widget.vfs.readFile('assistant_debug.log');
      } catch (_) {}
      await widget.vfs.writeFile('assistant_debug.log', '$current$entry\n');
    } catch (_) {}
  }

  Future<void> _handleToolCall(LlmToolCall call) async {
    final toolMsg = ChatMessage(
      role: 'assistant',
      content: '🛠️ Calling tool: ${call.name}...',
      isUiOnly: true,
    );
    if (mounted) {
      setState(() {
        _messages.add(toolMsg);
      });
    }
    _scrollToBottom(force: true);

    final toolHandler =
        IdeToolHandler(vfs: widget.vfs, ideController: widget.controller);
    Object? result;
    try {
      if (call.name == 'type_check') {
        result = await toolHandler
            .typeCheck((call.arguments['code'] as String?) ?? '');
      } else if (call.name == 'run_python') {
        widget.onAssistantCode?.call((call.arguments['code'] as String?) ?? '');
        result = await toolHandler
            .runPython((call.arguments['code'] as String?) ?? '');
      } else if (call.name == 'write_file') {
        widget.onAssistantCode
            ?.call((call.arguments['content'] as String?) ?? '');
        result = await toolHandler.writeFile(
          (call.arguments['path'] as String?) ?? 'file.py',
          (call.arguments['content'] as String?) ?? '',
        );
        widget.onFileWritten?.call();
      }
    } on Exception catch (e) {
      result = {'error': e.toString()};
    }

    await _logDebug('TOOL RESULT [${call.id}]: ${jsonEncode(result)}');

    if (mounted) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: 'tool',
            content: jsonEncode(result),
            toolCallId: call.id,
            isUiOnly: false,
          ),
        );
      });
      _scrollToBottom(force: true);
    }
  }

  DateTime _lastScroll = DateTime.now();
  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastScroll).inMilliseconds < 100) return;
    _lastScroll = now;
    if (force) {
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  void _clearChat() {
    setState(() {
      for (final m in _messages) {
        m.dispose();
      }
      _messages.clear();
      _lastDebugLog = '';
    });
    unawaited(
        widget.vfs.writeFile('assistant_debug.log', '--- Chat Cleared ---\n'));
  }

  void _viewSystemPrompt() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 600,
          height: 600,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: SystemPromptView(vfs: widget.vfs),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: Theme.of(context).secondaryHeaderColor,
          child: Row(
            children: [
              const Text(
                'ASSISTANT',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _viewSystemPrompt,
                icon: const Icon(Icons.shield_outlined, size: 14),
                tooltip: 'View System Prompt',
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _showDebug = !_showDebug),
                icon: Icon(
                  Icons.bug_report,
                  size: 14,
                  color: _showDebug ? Colors.red : null,
                ),
                tooltip: 'Show Debug Logs',
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _clearChat,
                icon: const Icon(Icons.delete_outline, size: 14),
                tooltip: 'Clear Chat',
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _showSettings = !_showSettings),
                icon: Icon(
                  Icons.settings,
                  size: 14,
                  color: _showSettings ? Colors.blue : null,
                ),
                tooltip: 'LLM Settings',
              ),
              const SizedBox(width: 8),
              DropdownButton<LlmProvider>(
                value: _provider,
                isDense: true,
                underline: const SizedBox(),
                style: const TextStyle(fontSize: 11, color: Colors.black),
                items: LlmProvider.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(p.name.toUpperCase()),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _provider = v);
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Collapse Assistant',
              ),
            ],
          ),
        ),
        if (_showDebug)
          Container(
            height: 350,
            width: double.infinity,
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: SelectableText(
                _lastDebugLog,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            cacheExtent: 1000,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              if (msg.role == 'tool') return const SizedBox.shrink();

              return _ChatMessageWidget(
                key: ValueKey(msg),
                message: msg,
                isStreaming: _isStreaming && index == _messages.length - 1,
                onCopyToEditor: widget.onCopyToEditor,
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  decoration: const InputDecoration(
                    hintText: 'Ask the Monty Assistant...',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    unawaited(_sendMessage());
                  },
                ),
              ),
              IconButton(
                onPressed: _isStreaming
                    ? null
                    : () {
                        unawaited(_sendMessage());
                      },
                icon: _isStreaming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatMessageWidget extends StatefulWidget {
  const _ChatMessageWidget({
    required this.message,
    required this.onCopyToEditor,
    this.isStreaming = false,
    super.key,
  });

  final ChatMessage message;
  final ValueChanged<String> onCopyToEditor;
  final bool isStreaming;

  @override
  State<_ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<_ChatMessageWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message.role.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 10,
              color:
                  widget.message.role == 'user' ? Colors.blue : Colors.purple,
            ),
          ),
          const SizedBox(height: 4),
          StreamBuilder<String>(
            stream: widget.message.contentStream,
            initialData: widget.message.content,
            builder: (context, snapshot) {
              return MarkdownBody(
                data: snapshot.data ?? '',
                selectable: !widget.isStreaming,
                builders: {
                  'code': _CodeBlockBuilder(onCopy: widget.onCopyToEditor),
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.onCopy});
  final ValueChanged<String> onCopy;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[200],
            child: Row(
              children: [
                const Text(
                  'Python',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => onCopy(text),
                  child: const Row(
                    children: [
                      Icon(Icons.copy_all, size: 14),
                      SizedBox(width: 4),
                      Text('COPY TO EDITOR', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black87,
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
