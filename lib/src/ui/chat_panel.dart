import 'dart:async';
import 'dart:convert';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:dart_monty_ide/src/llm/ollama_service.dart';
import 'package:dart_monty_ide/src/llm/open_responses_service.dart';
import 'package:dart_monty_ide/src/ui/system_prompt_view.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// A message in the chat.
class ChatMessage {
  /// Creates a [ChatMessage].
  ChatMessage({
    required this.role,
    required this.content,
  });

  /// Role of the message sender.
  final String role;

  /// Content of the message.
  String content;
}

/// A panel for interacting with an LLM with tool support.
class ChatPanel extends StatefulWidget {
  /// Creates a [ChatPanel].
  const ChatPanel({
    required this.vfs,
    required this.controller,
    required this.onCopyToEditor,
    required this.onClose,
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

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final TextEditingController _ollamaUrlController =
      TextEditingController(text: 'http://localhost:11434/api');
  final TextEditingController _modelController =
      TextEditingController(text: 'gpt-oss:latest');

  LlmProvider _provider = LlmProvider.ollama;
  bool _isStreaming = false;
  bool _showSettings = false;

  late LlmService _ollamaService;
  late LlmService _openResponsesService;

  @override
  void initState() {
    super.initState();
    _ollamaService = OllamaLlmService();
    _openResponsesService = OpenResponsesLlmService();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _ollamaUrlController.dispose();
    _modelController.dispose();
    _ollamaService.dispose();
    _openResponsesService.dispose();
    super.dispose();
  }

  LlmService get _currentService =>
      _provider == LlmProvider.ollama ? _ollamaService : _openResponsesService;

  List<LlmTool> get _tools => [
        const LlmTool(
          name: 'run_python',
          description:
              'Executes Monty Python code in the sandbox and returns output.',
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
      });
    }

    _scrollToBottom();
    await _getLlmResponse();
  }

  Future<void> _getLlmResponse() async {
    String sysPrompt;
    try {
      sysPrompt = await widget.vfs.readFile('system_prompt.txt');
    } on Exception catch (e) {
      debugPrint(
        'ChatPanel: Failed to read system_prompt.txt, using fallback: $e',
      );
      sysPrompt = SystemPromptView.defaultPrompt;
    }

    final history = [
      {'role': 'system', 'content': sysPrompt},
      ..._messages.map((m) => {'role': m.role, 'content': m.content}),
    ];

    final config = LlmConfig(
      provider: _provider,
      baseUrl: _ollamaUrlController.text.trim(),
      model: _modelController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', content: ''));
      });
    }

    try {
      final stream = _currentService.streamResponse(
        messages: history,
        config: config,
        tools: _tools,
      );

      final toolCalls = <LlmToolCall>[];

      await for (final chunk in stream) {
        if (!mounted) break;
        setState(() {
          if (chunk.text != null) {
            _messages.last.content += chunk.text!;
          }
          if (chunk.toolCalls != null) {
            toolCalls.addAll(chunk.toolCalls!);
          }
        });
        _scrollToBottom();
      }

      if (toolCalls.isNotEmpty) {
        for (final call in toolCalls) {
          await _handleToolCall(call);
        }
        if (mounted) await _getLlmResponse();
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _messages.last.content += '\n\n**Error:** $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isStreaming = false);
      }
    }
  }

  Future<void> _handleToolCall(LlmToolCall call) async {
    if (mounted) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            content: '🛠️ Calling tool: ${call.name}...',
          ),
        );
      });
    }
    _scrollToBottom();

    Object? result;
    try {
      if (call.name == 'run_python') {
        final code = (call.arguments['code'] as String?) ?? '';
        final res = await widget.controller.execute(code);
        result = {
          'output': res?.printOutput,
          'error': res?.error?.message,
          'value': res?.value.toString(),
        };
      } else if (call.name == 'write_file') {
        final path = (call.arguments['path'] as String?) ?? 'untitled.py';
        final content = (call.arguments['content'] as String?) ?? '';
        await widget.vfs.writeFile(path, content);
        result = {'status': 'success', 'path': path};
      }
    } on Exception catch (e) {
      result = {'error': e.toString()};
    }

    if (mounted) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: 'tool',
            content: jsonEncode(result),
          ),
        );
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        unawaited(
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        );
      }
    });
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
        if (_showSettings)
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                TextField(
                  controller: _ollamaUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Ollama Base URL',
                    labelStyle: TextStyle(fontSize: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model Name',
                    labelStyle: TextStyle(fontSize: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              if (msg.role == 'tool') return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.role.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        color: msg.role == 'user' ? Colors.blue : Colors.purple,
                      ),
                    ),
                    const SizedBox(height: 4),
                    MarkdownBody(
                      data: msg.content,
                      selectable: true,
                      builders: {
                        'code':
                            _CodeBlockBuilder(onCopy: widget.onCopyToEditor),
                      },
                    ),
                  ],
                ),
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
                  onSubmitted: (value) => unawaited(_sendMessage()),
                ),
              ),
              IconButton(
                onPressed:
                    _isStreaming ? null : () => unawaited(_sendMessage()),
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

class _CodeBlockBuilder extends MarkdownElementBuilder {
  /// Creates a [_CodeBlockBuilder].
  _CodeBlockBuilder({required this.onCopy});

  /// Callback when code should be copied to the editor.
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
