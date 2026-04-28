import 'dart:async';

/// Abstract interface for executing tools requested by the Assistant.
/// This allows headless execution (CLI/Tests) without depending on Flutter.
abstract interface class AssistantToolHandler {
  /// Executes a Python script in a sandbox.
  Future<Map<String, dynamic>> runPython(String code);

  /// Performs static analysis on Python code.
  Future<Map<String, dynamic>> typeCheck(String code);

  /// Writes a file to the workspace.
  Future<Map<String, dynamic>> writeFile(String path, String content);
}
