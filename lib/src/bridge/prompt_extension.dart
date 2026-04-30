import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:flutter/foundation.dart';

/// A Monty extension that lets a running script append fragments to the
/// AI Pilot's system prompt via the host function `prompt_extend(text)`,
/// and inspect the synthesized prompt via `prompt_show()`.
///
/// Fragments are intentionally cleared each time a fresh run begins (call
/// [clear] from the IDE before [MontyIdeController.execute]) so the assistant
/// only sees the brief declared by the *currently* running script.
class MontyPromptExtension extends MontyExtension with ChangeNotifier {
  final List<String> _fragments = [];

  /// Optional callback returning the currently-synthesized system prompt.
  /// Wired from the IDE so `prompt_show()` can reveal what the LLM sees.
  String Function()? snapshotBuilder;

  /// Read-only view of the fragments registered so far.
  List<String> get fragments => List.unmodifiable(_fragments);

  /// Clears all registered fragments. Call before each fresh run so a prior
  /// script's brief doesn't leak into the next.
  void clear() {
    if (_fragments.isEmpty) return;
    _fragments.clear();
    notifyListeners();
  }

  @override
  String get namespace => 'prompt';

  @override
  String? get systemPromptContext =>
      'Scripts may call prompt_extend(text) to inject additional context '
      "(their \"design brief\") into the AI Pilot's system prompt, and "
      'prompt_show() to read the currently-synthesized prompt.';

  @override
  List<HostFunction> get functions => [
        HostFunction(
          schema: const HostFunctionSchema(
            name: 'prompt_extend',
            description:
                'Register a fragment that will be injected into the AI '
                "Pilot's system prompt for the current script. Call near the "
                'top of the script to declare its purpose / inputs / scope.',
            params: [
              HostParam(name: 'text', type: HostParamType.string),
            ],
          ),
          handler: (args, ctx) async {
            final text = (args['text'] as String?)?.trim() ?? '';
            if (text.isNotEmpty) {
              _fragments.add(text);
              notifyListeners();
            }
            return null;
          },
        ),
        HostFunction(
          schema: const HostFunctionSchema(
            name: 'prompt_show',
            description:
                'Return the currently-synthesized AI Pilot system prompt '
                '(default rules + extension contexts + runtime API + this '
                "script's registered fragments). Useful for debugging the "
                'layered prompt.',
          ),
          handler: (args, ctx) async => snapshotBuilder?.call() ?? '',
        ),
      ];
}
