import 'dart:async';
import 'dart:io';
import 'package:dart_monty_ide/assistant.dart';

/// Headless tool handler used by the validation script.
class HeadlessToolHandler implements AssistantToolHandler {
  @override
  Future<Map<String, dynamic>> runPython(String code) async {
    return {'output': 'Success (Mocked for Headless Validation)'};
  }

  @override
  Future<Map<String, dynamic>> typeCheck(String code) async {
    return {'ok': true, 'errors': <Object?>[]};
  }

  @override
  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    return {'status': 'success'};
  }

  @override
  Future<Map<String, dynamic>> readFile(String path) async {
    return {
      'status': 'success',
      'content': '# mocked file content',
    };
  }

  @override
  Future<Map<String, dynamic>> listFiles() async {
    return {
      'status': 'success',
      'files': <String>['main.py'],
    };
  }

  @override
  Future<Map<String, dynamic>> uiState() async {
    return {
      'status': 'success',
      'tree': null,
      'awaiting': false,
    };
  }

  @override
  Future<Map<String, dynamic>> uiDispatch({
    required String target,
    required String eventType,
    Object? value,
  }) async {
    return {'status': 'success'};
  }
}

void main() async {
  final llmService = OllamaLlmService();
  final config = LlmConfig(
    baseUrl: 'http://localhost:11434',
    model: 'gpt-oss:20b',
  );

  final controller = AssistantController(
    toolHandler: HeadlessToolHandler(),
    llmService: llmService,
    config: config,
    systemPrompt: defaultAssistantPrompt,
  );

  await controller.processPrompt('build a depth first search');

  var hasTypeCheck = false;
  var hasRunPython = false;

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
