import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// A [MontyVfs] implementation that uses the local filesystem.
class LocalMontyVfs implements MontyVfs {
  /// Creates a [LocalMontyVfs] rooted at [rootPath].
  LocalMontyVfs({
    required this.rootPath,
    FileSystem? fs,
  }) : _fs = fs ?? const LocalFileSystem();

  /// The root directory of the workspace.
  final String rootPath;
  final FileSystem _fs;

  Directory get _root => _fs.directory(rootPath);

  @override
  Future<List<String>> listFiles() async {
    if (!await _root.exists()) {
      await _root.create(recursive: true);
    }

    final files = <String>[];
    await for (final entity in _root.list(recursive: true)) {
      if (entity is File &&
          (entity.path.endsWith('.py') || entity.path.endsWith('.txt'))) {
        files.add(p.relative(entity.path, from: rootPath));
      }
    }

    return files;
  }

  @override
  Future<String> readFile(String path) {
    final file = _fs.file(p.join(rootPath, path));

    return file.readAsString();
  }

  @override
  Future<void> writeFile(String path, String content) async {
    final fullPath = p.join(rootPath, path);
    final file = _fs.file(fullPath);
    debugPrint('LocalMontyVfs: Writing ${content.length} bytes to $fullPath');
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(content);
    debugPrint('LocalMontyVfs: Write complete.');
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = _fs.file(p.join(rootPath, path));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    final file = _fs.file(p.join(rootPath, oldPath));
    if (await file.exists()) {
      await file.rename(p.join(rootPath, newPath));
    }
  }
}
