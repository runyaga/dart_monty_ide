import 'dart:async';
import 'package:open_responses/open_responses.dart';
import 'llm_service.dart';

/// Implementation of [LlmService] using the OpenResponses API.
class OpenResponsesLlmService implements LlmService {
  @override
  Stream<String> streamResponse({
    required String prompt,
    required String systemPrompt,
    required LlmConfig config,
  }) {
    final client = OpenResponsesClient(
      config: OpenResponsesConfig(
        baseUrl: config.baseUrl,
        authProvider: config.apiKey != null
            ? BearerTokenProvider(config.apiKey!)
            : const NoAuthProvider(),
      ),
    );
    
    final controller = StreamController<String>();

    // For open_responses, we'll combine system and user prompt for now
    final fullInput = '$systemPrompt\n\nUser: $prompt';

    final runner = client.responses.stream(
      CreateResponseRequest.text(
        model: config.model,
        input: fullInput,
      ),
    );

    runner.onTextDelta((delta) {
      controller.add(delta);
    });

    runner.finalResponse.then((_) {
      controller.close();
    }).catchError((Object e) {
      controller.addError(e);
      controller.close();
    });

    return controller.stream;
  }
}
