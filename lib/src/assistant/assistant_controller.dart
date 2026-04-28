import 'dart:async';
import 'dart:convert';
import 'package:dart_monty_ide/src/assistant/assistant_tool_handler.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';

/// Headless controller that manages the AI Assistant's verification loop.
class AssistantController {
  /// Creates an [AssistantController].
  AssistantController({
    required this.toolHandler,
    required this.llmService,
    required this.config,
    required this.systemPrompt,
  });

  final AssistantToolHandler toolHandler;
  final LlmService llmService;
  final LlmConfig config;
  final String systemPrompt;

  final List<Map<String, dynamic>> _history = [];
  int _turnCount = 0;

  /// Returns the current conversation history.
  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  /// Processes a user prompt and runs the verification loop.
  Future<String> processPrompt(String prompt) async {
    _history.add({'role': 'user', 'content': prompt});
    _turnCount = 0;
    return await _loop();
  }

  Future<String> _loop() async {
    if (_turnCount >= 10) {
      return '⚠️ Verification turn limit reached.';
    }

    final fullHistory = [
      {'role': 'system', 'content': systemPrompt},
      ..._history,
    ];

    final stream = llmService.streamResponse(
      messages: fullHistory,
      config: config,
      tools: _tools,
    );

    String assistantText = '';
    final toolCalls = <LlmToolCall>[];

    await for (final chunk in stream) {
      if (chunk.text != null) assistantText += chunk.text!;
      if (chunk.toolCalls != null) toolCalls.addAll(chunk.toolCalls!);
    }

    if (toolCalls.isEmpty) {
      _history.add({'role': 'assistant', 'content': assistantText});
      return assistantText;
    }

    // Record the assistant's tool call in history
    _history.add({
      'role': 'assistant',
      'content': assistantText,
      'tool_calls': toolCalls
          .map((tc) => {
                'id': tc.id,
                'type': 'function',
                'function': {
                  'name': tc.name,
                  'arguments': tc.arguments,
                }
              })
          .toList(),
    });

    _turnCount++;

    // Execute tools and add results to history
    for (final call in toolCalls) {
      final result = await _executeTool(call);
      _history.add({
        'role': 'tool',
        'tool_call_id': call.id,
        'content': jsonEncode(result),
      });
    }

    // Recurse for the next turn
    return await _loop();
  }

  Future<Object?> _executeTool(LlmToolCall call) async {
    try {
      if (call.name == 'type_check') {
        final code = (call.arguments['code'] as String?) ?? '';
        return await toolHandler.typeCheck(code);
      } else if (call.name == 'run_python') {
        final code = (call.arguments['code'] as String?) ?? '';
        return await toolHandler.runPython(code);
      } else if (call.name == 'write_file') {
        final path = (call.arguments['path'] as String?) ?? 'file.py';
        final content = (call.arguments['content'] as String?) ?? '';
        return await toolHandler.writeFile(path, content);
      }
    } catch (e) {
      return {'error': e.toString()};
    }
    return {'error': 'Unknown tool: ${call.name}'};
  }

  static const List<LlmTool> _tools = [
    LlmTool(
      name: 'type_check',
      description: 'Static analysis. ALWAYS call before run_python.',
      parameters: {
        'type': 'object',
        'properties': {
          'code': {'type': 'string'},
        },
        'required': ['code'],
      },
    ),
    LlmTool(
      name: 'run_python',
      description: 'Execute Python. Only call after clean type_check.',
      parameters: {
        'type': 'object',
        'properties': {
          'code': {'type': 'string'},
        },
        'required': ['code'],
      },
    ),
    LlmTool(
      name: 'write_file',
      description: 'Save file to workspace.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
        },
        'required': ['path', 'content'],
      },
    ),
  ];
}
