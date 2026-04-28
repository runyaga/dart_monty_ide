import 'dart:async';
import 'package:dart_monty_ide/src/assistant/assistant_controller.dart';
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:dart_monty_ide/src/vfs/memory_vfs.dart';
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

void main() {
  test('AssistantController verification loop test', () async {
    final vfs = MemoryMontyVfs();
    final ideController = MontyIdeController();
    await ideController.initialize();

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
      vfs: vfs,
      ideController: ideController,
      llmService: mockLlm,
      config: LlmConfig(),
      systemPrompt: 'You are an assistant.',
    );

    final result = await controller.processPrompt('Verify the value of x');

    expect(result, contains('x equals 42'));

    // Verify history structure (System + User + 3 turns: 1 call, 1 result, 1 call, 1 result, 1 final)
    // History stores User(0) + AsstTool(1) + ToolResult(2) + AsstTool(3) + ToolResult(4) + AsstFinal(5)
    expect(controller.history.length, equals(6));
    expect(controller.history[0]['role'], equals('user'));
    expect(controller.history[1]['role'], equals('assistant'));
    expect(controller.history[2]['role'], equals('tool'));
    expect(controller.history[3]['role'], equals('assistant'));
    expect(controller.history[4]['role'], equals('tool'));
    expect(controller.history[5]['role'], equals('assistant'));
  });
}
