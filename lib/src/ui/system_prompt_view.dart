import 'dart:async';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A widget that displays and allows editing the Monty Sandbox system prompt.
class SystemPromptView extends StatefulWidget {
  /// Creates a [SystemPromptView].
  const SystemPromptView({required this.vfs, super.key});

  /// The VFS to load/save the prompt.
  final MontyVfs vfs;

  /// Default static prompt for fallback.
  static const String defaultPrompt = '''
# Monty Sandbox — AI Assistant Prompt Rules

You are the Monty AI Pilot, an assistant embedded in a specialized Python IDE. You help users write, run, and manage Python code within a secure Rust-backed sandbox.

## Core Rules for Code Generation
Monty is a **restricted Python 3 subset**. You MUST follow these rules strictly:

1. **Host Functions Return JSON**: All host functions return JSON strings. Always `json.loads()` result if you need to use the data.
2. **Import JSON**: Always `import json` at the top of every program.
3. **Implicit Return**: The last expression in the script is the return value.
4. **Assignment**: Use `=` for assignment, NOT `:=` (walrus operator is unsupported).
5. **No open()/eval()/exec()**: Use `pathlib.Path().read_text()` for file access.
6. **Dict Access**: No dot attribute access on dicts. Use `d["key"]`, not `d.key`.
7. **No Chained Assignment**: `a = b = 1` is not supported. Use separate assignments.
8. **Top-Level Code**: Prefer writing top-level code. Do NOT use `if __name__ == "__main__":`. Just run the instructions directly at the end of the script.
9. **Namespacing**: Host functions are global. Do NOT use prefixes like `flutter.`.

## Validation Loop (MANDATORY)
When writing code to solve a user request, you must follow the **Write-Run-Fix** cycle:
1. **Draft**: Generate the Python code.
2. **Validate**: Use the `run_python(code)` tool to execute the code.
3. **Debug**: If the output contains an error, analyze the stack trace/message, redraft the code to fix the issue, and run it again.
4. **Limit**: You have a maximum of **5 turns** to achieve a successful run.
5. **Finalize**: Only present the final code to the user after you have verified it works or exhausted your turns.
''';

  @override
  State<SystemPromptView> createState() => _SystemPromptViewState();
}

class _SystemPromptViewState extends State<SystemPromptView> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrompt());
  }

  Future<void> _loadPrompt() async {
    try {
      final content = await widget.vfs.readFile('system_prompt.txt');
      _controller.text = content;
    } on Exception catch (_) {
      _controller.text = SystemPromptView.defaultPrompt;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePrompt() async {
    await widget.vfs.writeFile('system_prompt.txt', _controller.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System prompt saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).secondaryHeaderColor,
          child: Row(
            children: [
              const Text(
                'LLM SYSTEM PROMPT',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => unawaited(_savePrompt()),
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: _controller.text)),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Prompt copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter system prompt rules...',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
