import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';

/// Exposes the AI Pilot's LLM to running scripts as a host function.
///
/// `pilot_ask(prompt: str) -> str` makes a one-shot call to the configured
/// LLM (same provider as the chat panel) and blocks until the full response
/// is assembled. Use it for "script consults the LLM" patterns — text
/// adventures, trivia generation, magic 8-balls — without coupling to the
/// chat panel's history or tool surface.
///
/// Note: this is a one-shot call with NO system prompt and NO conversation
/// history. Each call is independent. If you need multi-turn, accumulate
/// the prompt yourself.
class MontyLlmExtension extends MontyExtension {
  /// Creates a [MontyLlmExtension] backed by [service] and [config].
  MontyLlmExtension({required this.service, required this.config});

  /// The LLM transport used to issue `pilot_ask` calls.
  final LlmService service;

  /// The LLM configuration (base URL, model, temperature) for `pilot_ask`.
  final LlmConfig config;

  @override
  String get namespace => 'pilot';

  @override
  String? get systemPromptContext =>
      'Scripts may call pilot_ask(prompt) to send a one-shot prompt to the '
      'AI Pilot LLM and receive the full response as a string. Blocks until '
      'the response completes. Requires a reachable LLM endpoint.';

  @override
  List<HostFunction> get functions => [
    HostFunction(
      schema: const HostFunctionSchema(
        name: 'pilot_ask',
        description:
            'Send a one-shot prompt to the AI Pilot LLM and return its '
            'full response as a plain string. Blocks until the LLM has '
            'finished streaming. No system prompt, no history — each '
            'call is independent.',
        params: [
          HostParam(name: 'prompt', type: HostParamType.string),
        ],
      ),
      handler: (args, ctx) async {
        final prompt = (args['prompt'] as String?) ?? '';
        if (prompt.isEmpty) return '';
        final stream = service.streamResponse(
          messages: [
            <String, dynamic>{'role': 'user', 'content': prompt},
          ],
          config: config,
        );
        final buf = StringBuffer();
        await for (final chunk in stream) {
          if (chunk.text != null) buf.write(chunk.text);
        }
        return buf.toString();
      },
    ),
  ];
}
