import 'dart:async';
import 'dart:convert';

import 'package:dart_monty_ide/src/assistant/assistant_controller.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:dart_monty_ide/src/ui/system_prompt_view.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:rxdart/rxdart.dart';
import 'package:url_launcher/url_launcher.dart';

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
    _throttledStream = _contentController.stream.throttleTime(
      const Duration(milliseconds: 100),
      trailing: true,
    );
  }

  /// The role producing this message (`'user'`, `'assistant'`, `'tool'`).
  final String role;

  /// Whether the message is rendered for UI feedback only (no LLM history).
  final bool isUiOnly;

  /// Identifier of the tool call this message responds to, if any.
  final String? toolCallId;

  /// Tool calls requested by the assistant in this message, if any.
  final List<LlmToolCall>? toolCalls;
  String _content;

  /// The current accumulated text content of the message.
  String get content => _content;

  final StreamController<String> _contentController =
      StreamController<String>.broadcast();
  late final Stream<String> _throttledStream;

  /// Throttled stream of content updates suitable for streaming UI.
  Stream<String> get contentStream => _throttledStream;

  /// Appends [text] to the message content and notifies listeners.
  void append(String text) {
    _content += text;
    _contentController.add(_content);
  }

  /// Releases the underlying stream resources.
  void dispose() {
    unawaited(_contentController.close());
  }
}

/// Approximate token count using the 1 token ≈ 4 chars heuristic.
///
/// Rules:
/// - [systemPromptChars]: character count of the system prompt (sent every
///   turn, dominant cost, not in [messages]).
/// - `isUiOnly` messages are skipped — they are never sent to the LLM.
/// - `content` is counted for all real messages (user, assistant, tool).
/// - Tool-call invocations on assistant messages are counted via their
///   serialised id + name + arguments, since those occupy context too.
int approxTokenCount(
  List<ChatMessage> messages, {
  int systemPromptChars = 0,
}) {
  var chars = systemPromptChars;
  for (final m in messages) {
    if (m.isUiOnly) continue;
    chars += m.content.length;
    for (final tc in m.toolCalls ?? const <LlmToolCall>[]) {
      chars += tc.id.length + tc.name.length;
      for (final entry in tc.arguments.entries) {
        chars += entry.key.length + entry.value.toString().length;
      }
    }
  }
  return (chars / 4).round();
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
    required this.onStop,
    required this.onCopyToEditor,
    required this.onClose,
    required this.temperature,
    required this.onTemperatureChanged,
    this.onClearChat,
    this.debugLog = '',
    this.ollamaReachable,
    super.key,
  });

  /// VFS used by the system-prompt viewer to read script fragments.
  final MontyVfs vfs;

  /// Controller backing the IDE; used to read live host extensions.
  final MontyIdeController controller;

  /// Controller that runs the verification loop for chat prompts.
  final AssistantController assistant;

  /// Messages currently displayed in the chat history.
  final List<ChatMessage> messages;

  /// Whether the assistant is currently streaming a response.
  final bool isStreaming;

  /// Called when the user submits a chat prompt.
  final ValueChanged<String> onSendMessage;

  /// Called when the user requests the in-flight assistant turn to stop.
  final VoidCallback onStop;

  /// Called when the user copies a code block back into the editor.
  final ValueChanged<String> onCopyToEditor;

  /// Called when the user closes the chat panel.
  final VoidCallback onClose;

  /// Called when the user clears the chat history, if provided.
  final VoidCallback? onClearChat;

  /// Sampling temperature for the LLM.
  final double temperature;

  /// Called when the user adjusts [temperature] via the slider.
  final ValueChanged<double> onTemperatureChanged;

  /// Free-form debug log displayed beneath the chat input.
  final String debugLog;

  /// Tri-state reachability: `null` = not yet probed, `true` = healthy,
  /// `false` = unreachable (CORS, not running, or wrong origin). The
  /// banner only shows when `false`.
  final bool? ollamaReachable;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _showSettings = false;
  bool _showDebug = false;

  String get _approxTokens {
    final tokens = approxTokenCount(
      widget.messages,
      systemPromptChars:
          widget.assistant.systemPrompt.length +
          widget.assistant.toolSchemaChars,
    );
    if (tokens >= 1000) {
      return '≈${(tokens / 1000).toStringAsFixed(1)}k tok';
    }
    return '≈$tokens tok';
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final prompt = _inputController.text.trim();
    if (prompt.isEmpty || widget.isStreaming) return;
    _inputController.clear();
    widget.onSendMessage(prompt);
    _scrollToBottom(force: true);
    _inputFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: theme.secondaryHeaderColor,
          height: 40,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text(
                  'ASSISTANT',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                const SizedBox(width: 6),
                Text(
                  _approxTokens,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
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
                  icon: Icon(
                    Icons.bug_report,
                    size: 14,
                    color: _showDebug ? Colors.red : null,
                  ),
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
                  onPressed: () =>
                      setState(() => _showSettings = !_showSettings),
                  icon: Icon(
                    Icons.settings,
                    size: 14,
                    color: _showSettings ? Colors.blue : null,
                  ),
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
            color: theme.cardColor,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Temperature', style: TextStyle(fontSize: 10)),
                    Expanded(
                      child: Slider(
                        value: widget.temperature,
                        divisions: 10,
                        label: widget.temperature.toStringAsFixed(1),
                        onChanged: widget.onTemperatureChanged,
                      ),
                    ),
                    Text(
                      widget.temperature.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 10),
                    ),
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
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        if (widget.ollamaReachable == false)
          _OllamaUnreachableBanner()
        else if (widget.ollamaReachable == null)
          _OllamaProbingBanner(),
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
                isStreaming:
                    widget.isStreaming && index == widget.messages.length - 1,
                onCopyToEditor: widget.onCopyToEditor,
              );
            },
          ),
        ),
        Material(
          color: theme.cardColor,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Ask the Monty Assistant...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    autofocus: true,
                  ),
                ),
                if (widget.isStreaming)
                  IconButton(
                    onPressed: widget.onStop,
                    icon: const Icon(Icons.stop_circle, color: Colors.red),
                    tooltip: 'Stop Assistant',
                  )
                else
                  IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send),
                    tooltip: 'Send Prompt',
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
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

  void _viewSystemPrompt(BuildContext context) {
    unawaited(
      showDialog(
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
      ),
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

    final role = widget.message.role;

    if (role == 'tool') {
      return _ToolResultWidget(message: widget.message);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            role.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 10,
              color: role == 'user' ? Colors.blue : Colors.purple,
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

/// Compact, collapsible display for a `role='tool'` result message.
///
/// Shows: tool name + one-line summary by default; full JSON on expand.
class _ToolResultWidget extends StatefulWidget {
  const _ToolResultWidget({required this.message});
  final ChatMessage message;

  @override
  State<_ToolResultWidget> createState() => _ToolResultWidgetState();
}

class _ToolResultWidgetState extends State<_ToolResultWidget> {
  bool _expanded = false;

  /// Parse content as JSON if possible, otherwise treat as plain string.
  Object? get _parsed {
    try {
      return jsonDecode(widget.message.content);
    } on FormatException {
      return null;
    }
  }

  /// One-line summary from the parsed result map.
  String _summary(Object? parsed) {
    final name = widget.message.toolCallId ?? '?';
    if (parsed is! Map<String, dynamic>) {
      final raw = widget.message.content;
      return raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
    }
    switch (name) {
      case 'run_python':
        final err = parsed['error'];
        if (err != null && err != 'null') return '❌ $err';
        final out = parsed['output'] as String? ?? '';
        final lines = out.trim().split('\n');
        final first = lines.first.trim();
        return lines.length > 1
            ? '$first  (+${lines.length - 1} lines)'
            : first.isEmpty
                ? '(no output)'
                : first;
      case 'type_check':
        final ok = parsed['ok'] as bool? ?? false;
        if (ok) return '✅ no type errors';
        final n = (parsed['errors'] as List?)?.length ?? 0;
        return '❌ $n error${n == 1 ? '' : 's'}';
      case 'write_file':
        return '✅ wrote ${parsed['path'] ?? ''}';
      case 'read_file':
        final content = parsed['content'] as String? ?? '';
        return '📄 ${content.length} chars';
      case 'list_files':
        final files = parsed['files'] as List?;
        return '📁 ${files?.length ?? 0} files';
      case 'ui_state':
        final awaiting = parsed['awaiting'] as bool? ?? false;
        return awaiting ? '🖥️ UI awaiting event' : '🖥️ UI idle';
      case 'ui_dispatch':
        final evt = parsed['event'] as Map?;
        return '📡 dispatched ${evt?['type'] ?? ''}';
      default:
        final status = parsed['status'];
        return status != null ? '$status' : '✅ ok';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.message.toolCallId ?? 'tool';
    final parsed = _parsed;
    final summary = _summary(parsed);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                color: theme.colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        summary,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                color: Colors.black,
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  child: SelectableText(
                    // Pretty-print JSON when available.
                    parsed != null
                        ? const JsonEncoder.withIndent('  ').convert(parsed)
                        : widget.message.content,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
          ],
        ),
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

/// Shown above the chat input when the Pilot can't reach Ollama. Most
/// commonly the user hasn't set `OLLAMA_ORIGINS` (CORS), denied a
/// browser network-permission prompt, or Ollama isn't running. Links
/// to the README setup walkthrough; opens in a new tab.
class _OllamaUnreachableBanner extends StatelessWidget {
  static const _setupUrl =
      'https://github.com/runyaga/dart_monty_ide#connecting-the-ai-pilot';

  Future<void> _open() async {
    final uri = Uri.parse(_setupUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange.shade800,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Can't reach Ollama at http://localhost:11434",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Make sure Ollama is running and OLLAMA_ORIGINS allows '
                  "this page's origin. If your browser asked for network "
                  'permission, allow it.',
                  style: TextStyle(color: Colors.brown.shade900, fontSize: 11),
                ),
                const SizedBox(height: 4),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => unawaited(_open()),
                    child: Text(
                      'Setup walkthrough →',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontSize: 11,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft, transient version of [_OllamaUnreachableBanner] shown while the
/// initial probe is still retrying — tells the user to allow any browser
/// network-permission prompt without flatly declaring failure.
class _OllamaProbingBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.blueGrey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.blueGrey.shade700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Connecting to Ollama… If your browser asked for network '
              'permission, please allow it.',
              style: TextStyle(color: Colors.blueGrey.shade800, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
