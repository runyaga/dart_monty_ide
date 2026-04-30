import 'dart:async';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ollama_dart/ollama_dart.dart';

/// HTTP client that strips `X-Request-ID` before sending. ollama_dart's
/// LoggingInterceptor adds the header by default, but Ollama's CORS
/// preflight does NOT include `X-Request-ID` in `Access-Control-Allow-Headers`,
/// so browsers reject the actual request. Stripping it preserves correct
/// behavior on web while leaving native unaffected.
class _StripRequestIdClient extends http.BaseClient {
  _StripRequestIdClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.remove('X-Request-ID');
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Implementation of [LlmService] using the Ollama local API.
class OllamaLlmService implements LlmService {
  void _log(String text) {
    // debugPrint works on every platform (incl. browser); stderr would
    // throw `StdIOUtils._getStdioOutputStream` on web.
    debugPrint('OLLAMA: $text');
  }

  @override
  Stream<LlmResponseChunk> streamResponse({
    required List<Map<String, dynamic>> messages,
    required LlmConfig config,
    List<LlmTool>? tools,
  }) {
    final client = OllamaClient(
      config: OllamaConfig(baseUrl: config.baseUrl),
      httpClient: _StripRequestIdClient(http.Client()),
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
        toolCalls: toolCallsData?.map((dynamic tc) {
          final map = tc as Map<String, dynamic>;
          final function = map['function'] as Map<String, dynamic>;
          return ToolCall(
            function: ToolCallFunction(
              name: function['name'] as String? ?? '',
              arguments:
                  function['arguments'] as Map<String, dynamic>? ?? {},
            ),
          );
        }).toList(),
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
      options: ModelOptions(
        temperature: config.temperature,
        stop: const StopSequence.list([
          '<|end_of_text|>',
          'USER:',
          'ASSISTANT:',
        ]),
      ),
    );

    _log(
        'Requesting turn with roles: ${messages.map((m) => m['role']).toList()}');

    unawaited(() async {
      try {
        final stream = client.chat.createStream(request: request).timeout(
          const Duration(seconds: 30),
          onTimeout: (sink) {
            _log('TURN TIMED OUT after 30s');
            sink.addError(Exception('LLM turn timed out'));
          },
        );
        await for (final chunk in stream) {
          final delta = chunk.message?.content;
          final toolCalls = chunk.message?.toolCalls?.map((tc) {
            final name = tc.function?.name ?? '';
            _log('LLM requested tool: $name');
            return LlmToolCall(
              id: '', // Positional, no ID support in ollama_dart
              name: name,
              arguments: tc.function?.arguments ?? {},
            );
          }).toList();

          if ((delta != null && delta.isNotEmpty) ||
              (toolCalls != null && toolCalls.isNotEmpty)) {
            controller.add(
              LlmResponseChunk(
                text: delta,
                toolCalls: toolCalls,
              ),
            );
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
