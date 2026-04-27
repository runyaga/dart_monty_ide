import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;

/// A [MontyVfs] implementation that lives in memory.
class MemoryMontyVfs implements MontyVfs {
  /// Creates a [MemoryMontyVfs].
  MemoryMontyVfs({
    FileSystem? fs,
  }) : _fs = fs ?? MemoryFileSystem();

  final FileSystem _fs;
  final String _rootPath = '/';

  @override
  Future<List<String>> listFiles() async {
    final files = <String>[];
    final root = _fs.directory(_rootPath);
    if (!await root.exists()) {
      await root.create(recursive: true);
    }

    await for (final entity in root.list(recursive: true)) {
      if (entity is File && (entity.path.endsWith('.py') || entity.path.endsWith('.txt'))) {
        files.add(p.relative(entity.path, from: _rootPath));
      }
    }
    return files;
  }

  @override
  Future<String> readFile(String path) async {
    final file = _fs.file(p.join(_rootPath, path));
    return file.readAsString();
  }

  @override
  Future<void> writeFile(String path, String content) async {
    final fullPath = p.join(_rootPath, path);
    final file = _fs.file(fullPath);
    debugPrint('MemoryMontyVfs: Writing ${content.length} bytes to $fullPath');
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(content);
    debugPrint('MemoryMontyVfs: Write complete.');
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = _fs.file(p.join(_rootPath, path));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    final file = _fs.file(p.join(_rootPath, oldPath));
    if (await file.exists()) {
      await file.rename(p.join(_rootPath, newPath));
    }
  }
}
