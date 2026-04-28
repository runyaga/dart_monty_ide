import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dart_monty_ide/assistant.dart';

class HeadlessToolHandler implements AssistantToolHandler {
  @override
  Future<Map<String, dynamic>> runPython(String code) async {
    print('   [TOOL] Headless RunPython requested');
    return {'output': 'Success (Mocked for Headless Validation)'};
  }

  @override
  Future<Map<String, dynamic>> typeCheck(String code) async {
    print('   [TOOL] Headless TypeCheck requested');
    return {'ok': true, 'errors': []};
  }

  @override
  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    print('   [TOOL] Headless WriteFile requested: $path');
    return {'status': 'success'};
  }
}

void main() async {
  print('--- Assistant Empirical Validation ---');

  final llmService = OllamaLlmService();
  final config = LlmConfig(
    provider: LlmProvider.ollama,
    baseUrl: 'http://localhost:11434',
    model: 'gpt-oss:20b',
  );

  final controller = AssistantController(
    toolHandler: HeadlessToolHandler(),
    llmService: llmService,
    config: config,
    systemPrompt: defaultAssistantPrompt,
  );

  print('Prompting: "build a depth first search"');

  final startTime = DateTime.now();
  final response = await controller.processPrompt('build a depth first search');
  final duration = DateTime.now().difference(startTime);

  print('\n--- VERIFICATION LOG ---');
  bool hasTypeCheck = false;
  bool hasRunPython = false;

  for (var i = 0; i < controller.history.length; i++) {
    final msg = controller.history[i];
    final role = msg['role'];
    final toolCalls = msg['tool_calls'] as List<dynamic>?;

    if (role == 'assistant' && toolCalls != null) {
      for (final tc in toolCalls) {
        final name = tc['function']['name'];
        print('[Turn ${i}] Assistant requested tool: $name');
        if (name == 'type_check') hasTypeCheck = true;
        if (name == 'run_python') hasRunPython = true;
      }
    } else if (role == 'tool') {
      print('[Turn ${i}] Tool result sent back to LLM.');
    }
  }

  print('\n--- FINAL RESPONSE ---');
  print(response);

  print('\n--- VALIDATION RESULTS ---');
  print('Duration: ${duration.inSeconds}s');
  print('Has type_check turn: $hasTypeCheck');
  print('Has run_python turn: $hasRunPython');

  if (hasTypeCheck && hasRunPython) {
    print(
        '\n✅ EMPIRICAL VALIDATION SUCCESS: Verification loop strictly followed.');
    exit(0);
  } else {
    print(
        '\n❌ EMPIRICAL VALIDATION FAILED: Assistant bypassed mandatory verification sequence.');
    exit(1);
  }
}
