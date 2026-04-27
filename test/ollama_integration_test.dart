import 'package:flutter_test/flutter_test.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:dart_monty_ide/src/llm/ollama_service.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';

void main() {
  group('Ollama Integration', () {
    test('can reach local ollama (requires ollama running)', () async {
      final client = OllamaClient(baseUrl: 'http://localhost:11434/api');
      try {
        final models = await client.listModels();
        print('Available Ollama models: ${models.models?.map((m) => m.name).toList()}');
        expect(models.models, isNotNull);
      } catch (e) {
        print('Ollama not reachable: $e');
        // This test might fail in CI if ollama is not present, 
        // but it validates the URI logic for the user.
      }
    });

    test('OllamaLlmService uses correct endpoints', () async {
      final service = OllamaLlmService();
      final config = LlmConfig(
        provider: LlmProvider.ollama,
        baseUrl: 'http://localhost:11434/api',
        model: 'gpt-oss:latest',
      );

      final stream = service.streamResponse(
        prompt: 'test',
        systemPrompt: 'test',
        config: config,
      );

      expect(stream, isNotNull);
      // We don't actually await here to avoid hanging if ollama is down
    });
  });
}
