import 'dart:async';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/github.dart';

/// A widget that displays a read-only buffer of code from the Assistant.
class MontyAssistantBuffer extends StatefulWidget {
  /// Creates a [MontyAssistantBuffer].
  const MontyAssistantBuffer({
    required this.codeStream,
    super.key,
  });

  /// Stream of code updates to display.
  final Stream<String> codeStream;

  @override
  State<MontyAssistantBuffer> createState() => _MontyAssistantBufferState();
}

class _MontyAssistantBufferState extends State<MontyAssistantBuffer> {
  final CodeLineEditingController _controller = CodeLineEditingController();

  @override
  void initState() {
    super.initState();
    widget.codeStream.listen((code) {
      if (mounted) {
        setState(() {
          _controller.text = code;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          color: Colors.purple[800],
          child: const Text(
            'LLM BUFFER',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: CodeEditor(
            controller: _controller,
            readOnly: true,
            style: CodeEditorStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              codeTheme: CodeHighlightTheme(
                languages: {'python': CodeHighlightThemeMode(mode: langPython)},
                theme: githubTheme,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
