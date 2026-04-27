import 'dart:async';
import 'package:ollama_dart/ollama_dart.dart';
import 'llm_service.dart';

/// Implementation of [LlmService] using the Ollama local API.
class OllamaLlmService implements LlmService {
  @override
  Stream<String> streamResponse({
    required String prompt,
    required String systemPrompt,
    required LlmConfig config,
  }) {
    final client = OllamaClient(baseUrl: config.baseUrl);
    final controller = StreamController<String>();

    final request = GenerateChatCompletionRequest(
      model: config.model,
      messages: [
        Message(
          role: MessageRole.system,
          content: systemPrompt,
        ),
        Message(
          role: MessageRole.user,
          content: prompt,
        ),
      ],
    );

    unawaited(() async {
      try {
        final stream = client.generateChatCompletionStream(request: request);
        await for (final chunk in stream) {
          final content = chunk.message?.content;
          if (content != null) {
            controller.add(content);
          }
        }
      } catch (e) {
        controller.addError(e);
      } finally {
        await controller.close();
      }
    }());

    return controller.stream;
  }
}
