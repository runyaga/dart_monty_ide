import 'package:flutter_test/flutter_test.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:http/http.dart' as http;

void main() {
  group('Ollama Connection Validation', () {
    const standardUrl = 'http://localhost:11434';
    const apiUrl = 'http://localhost:11434/api';

    test('Verify raw connectivity to port 11434', () async {
      try {
        final response = await http.get(Uri.parse(standardUrl));
        print('Raw port 11434 response: ${response.statusCode} - ${response.body}');
      } catch (e) {
        print('Could not reach port 11434: $e');
        fail('Ollama must be running on localhost:11434 for this test to pass');
      }
    });

    test('Probe /api/tags endpoint directly', () async {
      try {
        final response = await http.get(Uri.parse('$standardUrl/api/tags'));
        print('/api/tags response: ${response.statusCode}');
        expect(response.statusCode, 200, reason: 'Ollama standard API should be at /api/tags');
      } catch (e) {
        print('Error probing /api/tags: $e');
      }
    });

    test('Validate OllamaClient with $apiUrl', () async {
      final client = OllamaClient(baseUrl: apiUrl);
      try {
        final res = await client.listModels();
        print('OllamaClient (with /api) success. Models: ${res.models?.length}');
        expect(res.models, isNotNull);
      } catch (e) {
        print('OllamaClient (with /api) failed: $e');
        rethrow;
      }
    });

    test('Validate OllamaClient with $standardUrl', () async {
      final client = OllamaClient(baseUrl: standardUrl);
      try {
        final res = await client.listModels();
        print('OllamaClient (no /api) success. Models: ${res.models?.length}');
        expect(res.models, isNotNull);
      } catch (e) {
        print('OllamaClient (no /api) failed: $e');
      }
    });
  });
}
