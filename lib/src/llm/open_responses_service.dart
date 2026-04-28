import 'dart:async';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:open_responses/open_responses.dart';

/// Implementation of [LlmService] using the OpenResponses API.
class OpenResponsesLlmService implements LlmService {
  @override
  Stream<LlmResponseChunk> streamResponse({
    required List<Map<String, String>> messages,
    required LlmConfig config,
    List<LlmTool>? tools,
  }) {
    final client = OpenResponsesClient(
      config: OpenResponsesConfig(
        baseUrl: config.baseUrl,
        authProvider: config.apiKey != null
            ? BearerTokenProvider(config.apiKey!)
            : const NoAuthProvider(),
      ),
    );

    final controller = StreamController<LlmResponseChunk>();

    final fullInput = messages
        .map((m) => '${m['role']?.toUpperCase()}: ${m['content']}')
        .join('\n\n');

    final runner = client.responses.stream(
      CreateResponseRequest.text(
        model: config.model,
        input: fullInput,
      ),
    );

    unawaited(() async {
      runner.onTextDelta((delta) {
        controller.add(LlmResponseChunk(text: delta));
      });

      try {
        await runner.finalResponse;
        await controller.close();
      } on Exception catch (e) {
        controller.addError(e);
        await controller.close();
      }
    }());

    return controller.stream;
  }

  @override
  void dispose() {
    // No-op.
  }
}
