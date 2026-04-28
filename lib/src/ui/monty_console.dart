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

  @override
  Widget build(BuildContext context) {
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
              child: SelectableText(
                _lines.join(''),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
