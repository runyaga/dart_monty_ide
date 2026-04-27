import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A widget that displays the Monty Sandbox system prompt rules.
class SystemPromptView extends StatelessWidget {
  /// Creates a [SystemPromptView].
  const SystemPromptView({super.key});

  static const String _prompt = '''
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
  Widget build(BuildContext context) {
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
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: _prompt));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Prompt copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy for LLM', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
        ),
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: SelectableText(
              _prompt,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}
