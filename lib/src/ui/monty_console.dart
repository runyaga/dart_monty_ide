import 'dart:async';
import 'package:flutter/material.dart';

/// A widget that displays the output of Python execution.
class MontyConsole extends StatefulWidget {
  /// Creates a [MontyConsole].
  const MontyConsole({
    required this.outputStream,
    super.key,
  });

  /// The stream of output messages.
  ///
  /// Sending the exact string '___CLEAR_CONSOLE___' will clear all lines.
  final Stream<String> outputStream;

  @override
  State<MontyConsole> createState() => _MontyConsoleState();
}

class _MontyConsoleState extends State<MontyConsole> {
  final List<String> _lines = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.outputStream.listen((event) {
      if (mounted) {
        setState(() {
          if (event == '___CLEAR_CONSOLE___') {
            _lines.clear();
          } else {
            _lines.add(event);
          }
        });
        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _lines.isNotEmpty) {
            unawaited(
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              ),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static Color _colorFor(String line) {
    final t = line.trimLeft();
    if (t.startsWith('🛑') || t.startsWith('❌')) return Colors.red[300]!;
    if (t.startsWith('⚠️')) return Colors.orange[300]!;
    if (t.startsWith('[') && RegExp(r'^\[[A-Za-z]+Error').hasMatch(t)) {
      return Colors.red[300]!;
    }
    if (t.startsWith('Error:') || t.startsWith('error:')) return Colors.red[300]!;
    if (t.contains('Traceback') || t.contains(' at line ')) {
      return Colors.orange[300]!;
    }
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    for (final line in _lines) {
      spans.add(TextSpan(
        text: line,
        style: TextStyle(color: _colorFor(line)),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          color: Colors.grey[800],
          child: const Text(
            'CONSOLE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SelectableText.rich(
                TextSpan(
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  children: spans,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
