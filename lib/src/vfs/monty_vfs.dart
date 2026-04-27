import 'dart:async';

/// Abstract interface for the Monty IDE Virtual File System.
abstract interface class MontyVfs {
  /// Lists all files in the current workspace.
  Future<List<String>> listFiles();

  /// Reads the content of a file.
  Future<String> readFile(String path);

  /// Writes [content] to a file at [path].
  Future<void> writeFile(String path, String content);

  /// Deletes the file at [path].
  Future<void> deleteFile(String path);

  /// Renames a file from [oldPath] to [newPath].
  Future<void> renameFile(String oldPath, String newPath);
}
