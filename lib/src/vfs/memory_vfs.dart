import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/foundation.dart';

/// A [MontyVfs] implementation that lives in memory.
///
/// Intentionally a plain `Map<String, String>` — no `package:file` /
/// `package:path` dependency. Earlier versions used `MemoryFileSystem`,
/// but its compiled-JS / dart2wasm behaviour on GitHub Pages produced
/// `FileSystemException` errors with the URL base path leaking into
/// the file path (e.g. `path = 'dart_monty_ide'`). A simple map sidesteps
/// the entire path-resolution surface.
class MemoryMontyVfs implements MontyVfs {
  /// Creates an empty in-memory VFS.
  MemoryMontyVfs();

  final Map<String, String> _files = <String, String>{};

  String _normalise(String path) {
    // Drop leading slashes so callers can use `/foo.py` or `foo.py`.
    var p = path;
    while (p.startsWith('/')) {
      p = p.substring(1);
    }

    return p;
  }

  @override
  Future<List<String>> listFiles() async {
    return _files.keys
        .where((p) => p.endsWith('.py') || p.endsWith('.txt'))
        .toList()
      ..sort();
  }

  @override
  Future<String> readFile(String path) async {
    final key = _normalise(path);
    final content = _files[key];
    if (content == null) {
      throw StateError('File not found: $path');
    }

    return content;
  }

  @override
  Future<void> writeFile(String path, String content) async {
    final key = _normalise(path);
    debugPrint('MemoryMontyVfs: Writing ${content.length} bytes to $key');
    _files[key] = content;
  }

  @override
  Future<void> deleteFile(String path) async {
    _files.remove(_normalise(path));
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    final oldKey = _normalise(oldPath);
    final newKey = _normalise(newPath);
    final content = _files.remove(oldKey);
    if (content != null) {
      _files[newKey] = content;
    }
  }
}
