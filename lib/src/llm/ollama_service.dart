import 'dart:async';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:ollama_dart/ollama_dart.dart';

/// Implementation of [LlmService] using the Ollama local API.
class OllamaLlmService implements LlmService {
  @override
  Stream<LlmResponseChunk> streamResponse({
    required List<Map<String, String>> messages,
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
      return ChatMessage(role: role, content: m['content'] ?? '');
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

    final request = ChatRequest(
      model: config.model,
      messages: ollamaMessages,
      tools: ollamaTools,
    );

    unawaited(() async {
      try {
        final stream = client.chat.createStream(request: request);
        await for (final chunk in stream) {
          final delta = chunk.message?.content;
          final toolCalls = chunk.message?.toolCalls?.map((tc) {
            return LlmToolCall(
              id: '',
              name: tc.function?.name ?? '',
              arguments: tc.function?.arguments ?? {},
            );
          }).toList();

          if ((delta != null && delta.isNotEmpty) ||
              (toolCalls != null && toolCalls.isNotEmpty)) {
            controller.add(LlmResponseChunk(text: delta, toolCalls: toolCalls));
          }
        }
      } on Exception catch (e) {
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
    // No-op for now.
  }
}
