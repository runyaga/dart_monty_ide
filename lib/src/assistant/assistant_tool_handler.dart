import 'dart:async';

/// Abstract interface for executing tools requested by the Assistant.
/// This allows headless execution (CLI/Tests) without depending on Flutter.
abstract interface class AssistantToolHandler {
  /// Executes a Python script in a sandbox.
  ///
  /// [inputs] are injected as Python variables before [code] runs.
  Future<Map<String, dynamic>> runPython(
    String code, {
    Map<String, Object?>? inputs,
  });

  /// Performs static analysis on Python code.
  Future<Map<String, dynamic>> typeCheck(String code);

  /// Writes a file to the workspace.
  Future<Map<String, dynamic>> writeFile(String path, String content);

  /// Reads a file from the workspace.
  Future<Map<String, dynamic>> readFile(String path);

  /// Lists files in the workspace.
  Future<Map<String, dynamic>> listFiles();

  /// Returns the most recent widget tree emitted by the running script via
  /// `el_emit(...)`, plus a flag indicating whether Python is currently
  /// paused at `el_recv()`. Lets the Pilot see what's on screen before
  /// dispatching events.
  Future<Map<String, dynamic>> uiState();

  /// Dispatches an event into the running script's `el_recv()` queue.
  /// [eventType] is typically `click` (buttons), `change` (sliders/checkbox),
  /// `submit` (text_field), or `quit` (close the loop).
  Future<Map<String, dynamic>> uiDispatch({
    required String target,
    required String eventType,
    Object? value,
  });
}
