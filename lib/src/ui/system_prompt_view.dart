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
# Monty Sandbox — Prompt Rules for Code Generation

When generating Python code for the Monty sandbox, follow these rules:

## Core Rules
1. All host functions return JSON strings. Always json.loads() the result.
2. import json at the top of every program.
3. The last expression is the return value.
4. Use = for assignment, NOT :=. The walrus operator is not supported.
5. No open(), eval(), exec(). Use Path().read_text() for files.
6. No dot attribute access on dicts. Use d["key"] not d.key.
7. No chained assignment. a = b = 1 is not supported.
8. No locals(), globals().
9. Write top-level code, not function definitions.

## Monty Sandbox Limitations
Monty is a restricted Python interpreter. It is NOT full CPython.

### Available standard library
- json (loads, dumps)
- math (basic math)
- re (regex)
- pathlib (Path - in-memory ONLY)
- collections (defaultdict, Counter, etc.)

### NOT available
- os, sys, subprocess, shutil (no system access)
- requests, urllib, http (no direct network)
- threading, multiprocessing, asyncio (no concurrency)
- Any pip packages.

### Key differences from CPython
- No file I/O except through pathlib.Path on in-memory filesystem.
- No network except through host functions.
- Host functions ARE the I/O layer.
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
    _loadPrompt();
  }

  Future<void> _loadPrompt() async {
    try {
      final content = await widget.vfs.readFile('system_prompt.txt');
      _controller.text = content;
    } catch (_) {
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
                onPressed: _savePrompt,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _controller.text));
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
