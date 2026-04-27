import 'dart:async';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:dart_monty_ide/src/llm/ollama_service.dart';
import 'package:dart_monty_ide/src/llm/open_responses_service.dart';
import 'package:dart_monty_ide/src/ui/system_prompt_view.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// A message in the chat.
class ChatMessage {
  /// Creates a [ChatMessage].
  ChatMessage({
    required this.role,
    required this.content,
  });

  /// Role of the message sender (user or assistant).
  final String role;

  /// Content of the message.
  String content;
}

/// A panel for interacting with an LLM to generate Python code.
class ChatPanel extends StatefulWidget {
  /// Creates a [ChatPanel].
  const ChatPanel({
    required this.vfs,
    required this.onCopyToEditor,
    super.key,
  });

  /// The VFS to load the system prompt from.
  final MontyVfs vfs;

  /// Callback when code should be copied to the editor.
  final ValueChanged<String> onCopyToEditor;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  LlmProvider _provider = LlmProvider.ollama;
  bool _isStreaming = false;

  late LlmService _ollamaService;
  late LlmService _openResponsesService;

  @override
  void initState() {
    super.initState();
    _ollamaService = OllamaLlmService();
    _openResponsesService = OpenResponsesLlmService();
  }

  LlmService get _currentService =>
      _provider == LlmProvider.ollama ? _ollamaService : _openResponsesService;

  Future<void> _sendMessage() async {
    final prompt = _inputController.text.trim();
    if (prompt.isEmpty || _isStreaming) return;

    _inputController.clear();
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: prompt));
      _messages.add(ChatMessage(role: 'assistant', content: ''));
      _isStreaming = true;
    });

    _scrollToBottom();

    // Fetch the current system prompt from disk
    String sysPrompt;
    try {
      sysPrompt = await widget.vfs.readFile('system_prompt.txt');
    } catch (_) {
      sysPrompt = SystemPromptView.defaultPrompt;
    }

    final config = LlmConfig(
      provider: _provider,
      baseUrl: _provider == LlmProvider.ollama
          ? 'http://localhost:11434/api'
          : 'http://localhost:8080/v1',
    );

    try {
      final stream = _currentService.streamResponse(
        prompt: prompt,
        systemPrompt: sysPrompt,
        config: config,
      );

      await for (final delta in stream) {
        if (mounted) {
          setState(() {
            _messages.last.content += delta;
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
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
              const Text('ASSISTANT',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              const Spacer(),
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
                        'code': _CodeBlockBuilder(onCopy: widget.onCopyToEditor),
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
            border:
                Border(top: BorderSide(color: Theme.of(context).dividerColor)),
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
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              IconButton(
                onPressed: _isStreaming ? null : _sendMessage,
                icon: _isStreaming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
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
  _CodeBlockBuilder({required this.onCopy});
  final ValueChanged<String> onCopy;

  @override
  Widget? visitElementAfter(element, preferredStyle) {
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
                const Text('Python',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
                  color: Colors.white, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
