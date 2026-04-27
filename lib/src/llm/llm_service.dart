import 'dart:async';

/// Enum defining supported LLM providers.
enum LlmProvider {
  /// Local Ollama instance.
  ollama,

  /// OpenAI or compatible via open_responses.
  openResponses,
}

/// Configuration for the LLM service.
class LlmConfig {
  /// Creates a [LlmConfig].
  LlmConfig({
    this.provider = LlmProvider.ollama,
    this.baseUrl = 'http://localhost:11434/api',
    this.model = 'gpt-oss:latest',
    this.apiKey,
  });  /// The selected provider.
  final LlmProvider provider;

  /// Base URL for the service (e.g. Ollama host).
  final String baseUrl;

  /// Model name (e.g. llama3, gpt-4).
  final String model;

  /// Optional API key for remote services.
  final String? apiKey;
}

/// Abstract base class for LLM interactions.
abstract interface class LlmService {
  /// Streams a response from the LLM based on the [prompt] and [systemPrompt].
  Stream<String> streamResponse({
    required String prompt,
    required String systemPrompt,
    required LlmConfig config,
  });
}
