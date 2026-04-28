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
  });

  /// The selected provider.
  final LlmProvider provider;

  /// Base URL for the service.
  final String baseUrl;

  /// Model name.
  final String model;

  /// Optional API key.
  final String? apiKey;
}

/// Represents a tool that the LLM can call.
class LlmTool {
  /// Creates a [LlmTool].
  const LlmTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// The tool name.
  final String name;

  /// Tool description.
  final String description;

  /// Tool parameter schema.
  final Map<String, dynamic> parameters;
}

/// Represents a call to a tool by the LLM.
class LlmToolCall {
  /// Creates a [LlmToolCall].
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// The unique call ID.
  final String id;

  /// The tool name.
  final String name;

  /// The arguments passed to the tool.
  final Map<String, dynamic> arguments;
}

/// A response chunk from the LLM, which can be text or a tool call.
class LlmResponseChunk {
  /// Creates a [LlmResponseChunk].
  const LlmResponseChunk({this.text, this.toolCalls});

  /// The text content of the chunk.
  final String? text;

  /// Any tool calls in the chunk.
  final List<LlmToolCall>? toolCalls;
}

/// Abstract base class for LLM interactions.
abstract interface class LlmService {
  /// Streams a response from the LLM.
  Stream<LlmResponseChunk> streamResponse({
    required List<Map<String, String>> messages,
    required LlmConfig config,
    List<LlmTool>? tools,
  });

  /// Releases resources held by the service.
  void dispose();
}
