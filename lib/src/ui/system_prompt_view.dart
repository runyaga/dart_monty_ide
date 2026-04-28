import 'dart:async';
import 'package:dart_monty_ide/src/assistant/default_prompt.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/material.dart';

/// A widget for viewing and editing the Assistant's system prompt.
class SystemPromptView extends StatefulWidget {
  /// Creates a [SystemPromptView].
  const SystemPromptView({required this.vfs, super.key});

  /// The VFS for file operations.
  final MontyVfs vfs;

  @override
  State<SystemPromptView> createState() => _SystemPromptViewState();
}

class _SystemPromptViewState extends State<SystemPromptView> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final content = await widget.vfs.readFile('system_prompt.txt');
      _controller.text = content;
    } on Exception catch (_) {
      _controller.text = defaultAssistantPrompt;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    await widget.vfs.writeFile('system_prompt.txt', _controller.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System prompt saved.')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Prompt', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.save),
            tooltip: 'Save Prompt',
          ),
        ],
      ),
      body: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.all(16),
          border: InputBorder.none,
          hintText: 'Enter assistant instructions here...',
        ),
      ),
    );
  }
}
