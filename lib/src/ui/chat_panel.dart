import 'dart:async';
import 'dart:convert';
import 'package:dart_monty_ide/src/assistant/assistant_controller.dart';
import 'package:dart_monty_ide/src/assistant/default_prompt.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:dart_monty_ide/src/ui/system_prompt_view.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
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
    _throttledStream = _contentController.stream
        .throttleTime(const Duration(milliseconds: 100), trailing: true);
  }

  final String role;
  final bool isUiOnly;
  final String? toolCallId;
  final List<LlmToolCall>? toolCalls;
  String _content;

  String get content => _content;

  final StreamController<String> _contentController = StreamController<String>.broadcast();
  late final Stream<String> _throttledStream;
  Stream<String> get contentStream => _throttledStream;

  void append(String text) {
    _content += text;
    _contentController.add(_content);
  }

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
    required this.assistant,
    required this.messages,
    required this.isStreaming,
    required this.onSendMessage,
    required this.onCopyToEditor,
    required this.onClose,
    required this.temperature,
    required this.onTemperatureChanged,
    this.onClearChat,
    this.debugLog = '',
    super.key,
  });

  final MontyVfs vfs;
  final MontyIdeController controller;
  final AssistantController assistant;
  final List<ChatMessage> messages;
  final bool isStreaming;
  final ValueChanged<String> onSendMessage;
  final ValueChanged<String> onCopyToEditor;
  final VoidCallback onClose;
  final VoidCallback? onClearChat;
  final double temperature;
  final ValueChanged<double> onTemperatureChanged;
  final String debugLog;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showSettings = false;
  bool _showDebug = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final prompt = _inputController.text.trim();
    if (prompt.isEmpty || widget.isStreaming) return;
    _inputController.clear();
    widget.onSendMessage(prompt);
    _scrollToBottom(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: Theme.of(context).secondaryHeaderColor,
          height: 40,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('ASSISTANT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _viewSystemPrompt(context),
                  icon: const Icon(Icons.shield_outlined, size: 14),
                  tooltip: 'View System Prompt',
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _showDebug = !_showDebug),
                  icon: Icon(Icons.bug_report, size: 14, color: _showDebug ? Colors.red : null),
                  tooltip: 'Show Debug Logs',
                ),
                if (widget.onClearChat != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onClearChat,
                    icon: const Icon(Icons.delete_outline, size: 14),
                    tooltip: 'Clear Chat',
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _showSettings = !_showSettings),
                  icon: Icon(Icons.settings, size: 14, color: _showSettings ? Colors.blue : null),
                  tooltip: 'LLM Settings',
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
        ),
        if (_showSettings)
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Temperature', style: TextStyle(fontSize: 10)),
                    Expanded(
                      child: Slider(
                        value: widget.temperature,
                        min: 0,
                        max: 1,
                        divisions: 10,
                        label: widget.temperature.toStringAsFixed(1),
                        onChanged: widget.onTemperatureChanged,
                      ),
                    ),
                    Text(widget.temperature.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
                  ],
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
                widget.debugLog,
                style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: widget.messages.length,
            itemBuilder: (context, index) {
              final msg = widget.messages[index];
              if (msg.role == 'tool') return const SizedBox.shrink();
              return _ChatMessageWidget(
                key: ValueKey(msg),
                message: msg,
                isStreaming: widget.isStreaming && index == widget.messages.length - 1,
                onCopyToEditor: widget.onCopyToEditor,
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  decoration: const InputDecoration(hintText: 'Ask the Monty Assistant...', border: InputBorder.none),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              IconButton(
                onPressed: widget.isStreaming ? null : _sendMessage,
                icon: widget.isStreaming ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
    if (force) {
      unawaited(_scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  void _viewSystemPrompt(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 600,
          height: 600,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          child: SystemPromptView(vfs: widget.vfs),
        ),
      ),
    );
  }
}

class _ChatMessageWidget extends StatefulWidget {
  const _ChatMessageWidget({required this.message, required this.onCopyToEditor, this.isStreaming = false, super.key});
  final ChatMessage message;
  final ValueChanged<String> onCopyToEditor;
  final bool isStreaming;
  @override
  State<_ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<_ChatMessageWidget> with AutomaticKeepAliveClientMixin {
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
          Text(widget.message.role.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: widget.message.role == 'user' ? Colors.blue : Colors.purple)),
          const SizedBox(height: 4),
          StreamBuilder<String>(
            stream: widget.message.contentStream,
            initialData: widget.message.content,
            builder: (context, snapshot) {
              return MarkdownBody(
                data: snapshot.data ?? '',
                selectable: !widget.isStreaming,
                builders: {'code': _CodeBlockBuilder(onCopy: widget.onCopyToEditor)},
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
                const Text('Python', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                const Spacer(),
                InkWell(
                  onTap: () => onCopy(text),
                  child: const Row(
                    children: [Icon(Icons.copy_all, size: 14), SizedBox(width: 4), Text('COPY TO EDITOR', style: TextStyle(fontSize: 10))],
                  ),
                ),
              ],
            ),
          ),
          Container(padding: const EdgeInsets.all(8), color: Colors.black87, child: Text(text, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12))),
        ],
      ),
    );
  }
}
