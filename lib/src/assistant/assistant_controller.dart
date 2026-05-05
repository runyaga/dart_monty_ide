import 'dart:async';
import 'dart:convert';
import 'package:dart_monty_ide/src/assistant/assistant_tool_handler.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';

/// Events emitted by the [AssistantController] during the verification loop.
sealed class AssistantEvent {}

/// Emitted when the assistant appends text to its response.
class AssistantTextEvent extends AssistantEvent {
  /// Creates an [AssistantTextEvent].
  AssistantTextEvent(this.text);

  /// The text appended by the assistant.
  final String text;
}

/// Emitted when a tool is being called.
class ToolCallEvent extends AssistantEvent {
  /// Creates a [ToolCallEvent].
  ToolCallEvent(this.name, this.arguments);

  /// The name of the tool.
  final String name;

  /// The arguments passed to the tool.
  final Map<String, dynamic> arguments;
}

/// Emitted when a tool returns a result.
class ToolResultEvent extends AssistantEvent {
  /// Creates a [ToolResultEvent].
  ToolResultEvent(this.name, this.result);

  /// The name of the tool.
  final String name;

  /// The result returned by the tool.
  final Object? result;
}

/// Emitted for raw debug logging.
class AssistantLogEvent extends AssistantEvent {
  /// Creates an [AssistantLogEvent].
  AssistantLogEvent(this.message);

  /// The log message.
  final String message;
}

/// Headless controller that manages the AI Assistant's verification loop.
class AssistantController {
  /// Creates an [AssistantController].
  ///
  /// Provide either [systemPrompt] (static) or [systemPromptBuilder]
  /// (rebuilt per turn — useful when extensions register prompt fragments
  /// at runtime). If both are provided, [systemPromptBuilder] wins.
  ///
  /// [maxHistoryMessages] caps how many messages are retained across turns.
  /// When the history exceeds this limit it is trimmed from the front,
  /// always snapping to a user-message boundary so tool call/result pairs
  /// are never split. Defaults to 40 (≈ 10 full exchanges).
  AssistantController({
    required this.toolHandler,
    required this.llmService,
    required this.config,
    String? systemPrompt,
    String Function()? systemPromptBuilder,
    this.maxHistoryMessages = 40,
  }) : assert(
         systemPrompt != null || systemPromptBuilder != null,
         'Provide systemPrompt or systemPromptBuilder',
       ),
       _staticSystemPrompt = systemPrompt,
       _systemPromptBuilder = systemPromptBuilder;

  /// The tool handler to execute tools.
  final AssistantToolHandler toolHandler;

  /// The LLM service to stream responses.
  final LlmService llmService;

  /// The LLM configuration.
  final LlmConfig config;

  /// Maximum number of messages kept in history before trimming.
  final int maxHistoryMessages;

  final String? _staticSystemPrompt;
  final String Function()? _systemPromptBuilder;

  /// Returns the system prompt for the next turn.
  String get systemPrompt =>
      _systemPromptBuilder?.call() ?? _staticSystemPrompt!;

  /// Character count of the serialised tool schemas sent on every API call.
  int get toolSchemaChars => jsonEncode(
    _tools
        .map(
          (t) => {
            'name': t.name,
            'description': t.description,
            'parameters': t.parameters,
          },
        )
        .toList(),
  ).length;

  final List<Map<String, dynamic>> _history = [];
  int _turnCount = 0;
  bool _isStopped = false;

  /// The maximum number of turns allowed in the verification loop.
  static const int maxTurns = 5;

  final StreamController<AssistantEvent> _eventController =
      StreamController<AssistantEvent>.broadcast();

  /// Stream of events during processing.
  Stream<AssistantEvent> get events => _eventController.stream;

  /// Returns the current conversation history.
  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  /// Clears the conversation history.
  void clearHistory() {
    _history.clear();
    _log('--- HISTORY CLEARED ---');
  }

  /// Trims [_history] to at most [maxHistoryMessages] entries by removing
  /// the oldest messages. Always snaps the cut point forward to the next
  /// user-role message so tool call / result pairs are never orphaned.
  void _trimHistory() {
    if (_history.length <= maxHistoryMessages) return;
    var cutFrom = _history.length - maxHistoryMessages;
    // Snap to the next user message so we don't start mid-exchange.
    while (cutFrom < _history.length &&
        _history[cutFrom]['role'] != 'user') {
      cutFrom++;
    }
    if (cutFrom > 0 && cutFrom < _history.length) {
      _history.removeRange(0, cutFrom);
      _log('--- HISTORY TRIMMED to ${_history.length} messages ---');
    }
  }

  /// Stops the current processing loop.
  void stop() {
    _isStopped = true;
    _log('--- STOP REQUESTED ---');
  }

  /// Processes a user prompt and runs the verification loop.
  ///
  /// An optional [context] can be provided to give the assistant more
  /// information about the current state.
  Future<String> processPrompt(String prompt, {String? context}) async {
    _isStopped = false;
    final content = context != null ? '$context\n\n$prompt' : prompt;
    _history.add({'role': 'user', 'content': content});
    _trimHistory();
    _turnCount = 0;
    _log('--- NEW SESSION: $prompt ---');
    try {
      return await _loop();
    } finally {
      _log('--- SESSION FINISHED ---');
    }
  }

  void _log(String message) {
    _eventController.add(AssistantLogEvent(message));
  }

  Future<String> _loop() async {
    if (_isStopped) {
      const msg = '🛑 Assistant stopped by user.';
      _log(msg);

      return msg;
    }

    _log('--- STARTING TURN ${_turnCount + 1} / $maxTurns ---');
    if (_turnCount >= maxTurns) {
      const msg = '⚠️ Verification turn limit reached ($maxTurns).';
      _log(msg);

      return msg;
    }

    final fullHistory = [
      {'role': 'system', 'content': systemPrompt},
      ..._history,
    ];

    _log('Turn ${_turnCount + 1}: Requesting response from LLM...');
    _log('RAW HISTORY: ${jsonEncode(fullHistory)}');

    final stream = llmService.streamResponse(
      messages: fullHistory,
      config: config,
      tools: _tools,
    );

    var assistantText = '';
    final toolCalls = <LlmToolCall>[];

    try {
      await for (final chunk in stream) {
        if (_isStopped) break;
        if (chunk.text != null) {
          assistantText += chunk.text!;
          _eventController.add(AssistantTextEvent(chunk.text!));
        }
        if (chunk.toolCalls != null) {
          toolCalls.addAll(chunk.toolCalls!);
        }
      }
    } on Object catch (e) {
      _log('LLM Stream Error: $e');

      return 'Error: $e';
    }

    if (_isStopped) {
      const msg = '🛑 Assistant stopped by user.';
      _log(msg);

      return msg;
    }

    if (toolCalls.isEmpty) {
      _history.add({'role': 'assistant', 'content': assistantText});
      _log('Assistant finished: $assistantText');

      return assistantText;
    }

    // Record the assistant's tool call in history
    final toolCallsJson = toolCalls
        .map(
          (tc) => {
            'id': tc.id,
            'type': 'function',
            'function': {
              'name': tc.name,
              'arguments': tc.arguments,
            },
          },
        )
        .toList();

    _history.add({
      'role': 'assistant',
      'content': assistantText,
      'tool_calls': toolCallsJson,
    });

    _log('Assistant requested tools: ${jsonEncode(toolCallsJson)}');

    _turnCount++;

    // Execute tools and add results to history
    for (final call in toolCalls) {
      if (_isStopped) break;
      _eventController.add(ToolCallEvent(call.name, call.arguments));
      final result = await _executeTool(call);
      _eventController.add(ToolResultEvent(call.name, result));
      final encodedResult = jsonEncode(result);
      _log('Tool result [${call.name}]: $encodedResult');
      _history.add({
        'role': 'tool',
        'tool_call_id': call.id,
        'content': encodedResult,
      });
    }

    if (_isStopped) {
      const msg = '🛑 Assistant stopped by user.';
      _log(msg);

      return msg;
    }

    // Recurse for the next turn
    return _loop();
  }

  Future<Object?> _executeTool(LlmToolCall call) async {
    try {
      if (call.name == 'type_check') {
        final code = (call.arguments['code'] as String?) ?? '';

        return await toolHandler.typeCheck(code);
      } else if (call.name == 'run_python') {
        final code = (call.arguments['code'] as String?) ?? '';
        final rawInputs = call.arguments['inputs'] as Map<String, dynamic>?;
        final inputs = rawInputs?.map((k, v) => MapEntry(k, v as Object?));

        return await toolHandler.runPython(code, inputs: inputs);
      } else if (call.name == 'write_file') {
        final path = (call.arguments['path'] as String?) ?? 'file.py';
        final content = (call.arguments['content'] as String?) ?? '';

        return await toolHandler.writeFile(path, content);
      } else if (call.name == 'read_file') {
        final path = (call.arguments['path'] as String?) ?? '';

        return await toolHandler.readFile(path);
      } else if (call.name == 'list_files') {
        return await toolHandler.listFiles();
      } else if (call.name == 'ui_state') {
        return await toolHandler.uiState();
      } else if (call.name == 'ui_dispatch') {
        final target = (call.arguments['target'] as String?) ?? '';
        final eventType = (call.arguments['event_type'] as String?) ?? 'click';

        return await toolHandler.uiDispatch(
          target: target,
          eventType: eventType,
          value: call.arguments['value'],
        );
      }
    } on Object catch (e) {
      return {'error': e.toString()};
    }

    return {'error': 'Unknown tool: ${call.name}'};
  }

  /// Closes the event stream.
  void dispose() {
    unawaited(_eventController.close());
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
          'inputs': {
            'type': 'object',
            'description':
                'Optional key/value pairs injected as Python variables before code runs.',
            'additionalProperties': true,
          },
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
    LlmTool(
      name: 'read_file',
      description: 'Read file from workspace.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
      },
    ),
    LlmTool(
      name: 'list_files',
      description: 'List all files in the workspace.',
      parameters: {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    ),
    LlmTool(
      name: 'ui_state',
      description:
          'Inspect the running Monty UI script: returns the latest widget '
          'tree emitted via el_emit(), and whether Python is paused at '
          'el_recv(). Use BEFORE ui_dispatch to see what ids exist and '
          'their current values.',
      parameters: {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    ),
    LlmTool(
      name: 'ui_dispatch',
      description:
          "Send an event into the running script's el_recv() queue, as if "
          'the user clicked / dragged / typed in the panel. event_type is '
          "typically 'click' (button), 'change' (slider/checkbox), 'submit' "
          "(text_field), or 'quit'. Do NOT call this if no Monty UI script "
          'is running — call ui_state first to confirm.',
      parameters: {
        'type': 'object',
        'properties': {
          'target': {'type': 'string'},
          'event_type': {'type': 'string'},
          'value': <String, dynamic>{},
        },
        'required': ['target', 'event_type'],
      },
    ),
  ];
}
