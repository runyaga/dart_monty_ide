import 'dart:async';
import 'dart:io';
import 'package:dart_monty_ide/assistant.dart';

class HeadlessToolHandler implements AssistantToolHandler {
  @override
  Future<Map<String, dynamic>> runPython(String code) async {
    return <String, dynamic>{
      'output': 'Success (Mocked for Headless Validation)',
    };
  }

  @override
  Future<Map<String, dynamic>> typeCheck(String code) async {
    return <String, dynamic>{'ok': true, 'errors': []};
  }

  @override
  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    return <String, dynamic>{'status': 'success'};
  }
}

void main() async {
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

  final startTime = DateTime.now();
  final response = await controller.processPrompt('build a depth first search');
  final duration = DateTime.now().difference(startTime);

  bool hasTypeCheck = false;
  bool hasRunPython = false;

  for (var i = 0; i < controller.history.length; i++) {
    final msg = controller.history[i];
    final role = msg['role'];
    final toolCalls = msg['tool_calls'] as List<dynamic>?;

    if (role == 'assistant' && toolCalls != null) {
      for (final dynamic tc in toolCalls) {
        final map = tc as Map<String, dynamic>;
        final function = map['function'] as Map<String, dynamic>;
        final name = function['name'];
        if (name == 'type_check') hasTypeCheck = true;
        if (name == 'run_python') hasRunPython = true;
      }
    }
  }

  if (hasTypeCheck && hasRunPython) {
    exit(0);
  } else {
    exit(1);
  }
}
