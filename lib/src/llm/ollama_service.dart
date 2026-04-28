import 'dart:async';
import 'dart:io';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:ollama_dart/ollama_dart.dart';

/// Implementation of [LlmService] using the Ollama local API.
class OllamaLlmService implements LlmService {
  void _log(String text) {
    stderr.writeln('OLLAMA: $text');
  }

  @override
  Stream<LlmResponseChunk> streamResponse({
    required List<Map<String, dynamic>> messages,
    required LlmConfig config,
    List<LlmTool>? tools,
  }) {
    final client = OllamaClient(
      config: OllamaConfig(baseUrl: config.baseUrl),
    );
    final controller = StreamController<LlmResponseChunk>();

    final ollamaMessages = messages.map((m) {
      final roleStr = m['role'] ?? 'user';
      final role = switch (roleStr) {
        'system' => MessageRole.system,
        'assistant' => MessageRole.assistant,
        'tool' => MessageRole.tool,
        _ => MessageRole.user,
      };

      final content = m['content'] as String? ?? '';
      final toolCallsData = m['tool_calls'] as List<dynamic>?;

      return ChatMessage(
        role: role,
        content: content,
        toolCalls: toolCallsData
            ?.map((tc) => ToolCall(
                  function: ToolCallFunction(
                    name: tc['function']['name'] as String? ?? '',
                    arguments:
                        tc['function']['arguments'] as Map<String, dynamic>? ??
                            {},
                  ),
                ))
            .toList(),
      );
    }).toList();

    final ollamaTools = tools?.map((t) {
      return ToolDefinition(
        type: ToolType.function,
        function: ToolFunction(
          name: t.name,
          description: t.description,
          parameters: t.parameters,
        ),
      );
    }).toList();

    // SIMPLE CONTROL: Force low temperature and strict stop sequences
    final request = ChatRequest(
      model: config.model,
      messages: ollamaMessages,
      tools: ollamaTools,
      options: const ModelOptions(
        temperature: 0.1,
        numPredict: 2048,
        stop: StopSequence.list(['<|end_of_text|>', 'USER:', 'ASSISTANT:']),
      ),
    );

    _log(
        'Requesting turn with roles: ${messages.map((m) => m['role']).toList()}');

    unawaited(() async {
      var fullContent = '';
      var toolCalled = false;

      try {
        final stream = client.chat.createStream(request: request);
        await for (final chunk in stream) {
          final delta = chunk.message?.content;
          final toolCalls = chunk.message?.toolCalls?.map((tc) {
            toolCalled = true;
            final name = tc.function?.name ?? '';
            _log('LLM requested tool: $name');
            return LlmToolCall(
              id: '', // Positional, no ID support in ollama_dart
              name: name,
              arguments: tc.function?.arguments ?? {},
            );
          }).toList();

          if (delta != null) fullContent += delta;

          if ((delta != null && delta.isNotEmpty) ||
              (toolCalls != null && toolCalls.isNotEmpty)) {
            controller.add(LlmResponseChunk(text: delta, toolCalls: toolCalls));
          }
        }

        // HEURISTIC REPAIR
        if (!toolCalled) {
          final codeBlockRegex = RegExp(r'```(?:python)?\n([\s\S]*?)```');
          final match = codeBlockRegex.firstMatch(fullContent);

          if (match != null) {
            final code = match.group(1)?.trim();
            if (code != null && code.isNotEmpty) {
              _log('Heuristic: Triggering type_check for code block');
              controller.add(
                LlmResponseChunk(
                  toolCalls: [
                    LlmToolCall(
                      id: '',
                      name: 'type_check',
                      arguments: {'code': code},
                    ),
                  ],
                ),
              );
            }
          }
        }
      } on Exception catch (e) {
        _log('ERROR: $e');
        controller.addError(e);
      } finally {
        await controller.close();
        client.close();
      }
    }());

    return controller.stream;
  }

  @override
  void dispose() {
    // No-op.
  }
}
