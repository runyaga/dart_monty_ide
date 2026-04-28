import 'dart:async';
import 'package:dart_monty_ide/src/assistant/assistant_controller.dart';
import 'package:dart_monty_ide/src/assistant/assistant_tool_handler.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';

class MockLlmService implements LlmService {
  final List<LlmResponseChunk> responses;
  int _callCount = 0;
  List<Map<String, dynamic>>? lastMessages;

  MockLlmService(this.responses);

  @override
  Stream<LlmResponseChunk> streamResponse({
    required List<Map<String, dynamic>> messages,
    required LlmConfig config,
    List<LlmTool>? tools,
  }) {
    lastMessages = messages;
    if (_callCount >= responses.length) {
      return Stream.fromIterable([const LlmResponseChunk(text: 'Done')]);
    }
    return Stream.fromIterable([responses[_callCount++]]);
  }

  @override
  void dispose() {}
}

class MockToolHandler implements AssistantToolHandler {
  @override
  Future<Map<String, dynamic>> runPython(String code) async => {'output': '42'};

  @override
  Future<Map<String, dynamic>> typeCheck(String code) async => {'ok': true};

  @override
  Future<Map<String, dynamic>> writeFile(String path, String content) async =>
      {'status': 'success'};
}

void main() {
  test('AssistantController verification loop test', () async {
    // Mock sequence:
    // 1. LLM requests type_check
    // 2. LLM sees clean type_check, then requests run_python
    // 3. LLM sees successful run, provides final answer
    final mockLlm = MockLlmService([
      const LlmResponseChunk(
        toolCalls: [
          LlmToolCall(
            id: 'call_1',
            name: 'type_check',
            arguments: {'code': 'x: int = 42'},
          )
        ],
      ),
      const LlmResponseChunk(
        toolCalls: [
          LlmToolCall(
            id: 'call_2',
            name: 'run_python',
            arguments: {'code': 'print(42)'},
          )
        ],
      ),
      const LlmResponseChunk(text: 'I have verified that x equals 42.'),
    ]);

    final controller = AssistantController(
      toolHandler: MockToolHandler(),
      llmService: mockLlm,
      config: LlmConfig(),
      systemPrompt: 'You are an assistant.',
    );

    final result = await controller.processPrompt('Verify the value of x');

    expect(result, contains('x equals 42'));
    expect(controller.history.length, equals(6));
  });
}
