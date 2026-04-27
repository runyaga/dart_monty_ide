import 'package:dart_monty_ide/src/vfs/local_vfs.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalMontyVfs', () {
    late MemoryFileSystem fs;
    late LocalMontyVfs vfs;
    const rootPath = '/workspace';

    setUp(() {
      fs = MemoryFileSystem();
      vfs = LocalMontyVfs(rootPath: rootPath, fs: fs);
    });

    test('listFiles returns empty list when no files exist', () async {
      final files = await vfs.listFiles();
      expect(files, isEmpty);
    });

    test('writeFile and readFile work correctly', () async {
      await vfs.writeFile('test.py', 'print("hello")');
      final content = await vfs.readFile('test.py');
      expect(content, 'print("hello")');
    });

    test('listFiles only returns .py files', () async {
      await vfs.writeFile('main.py', 'x = 1');
      await vfs.writeFile('README.md', 'hello');

      final files = await vfs.listFiles();
      expect(files, contains('main.py'));
      expect(files, isNot(contains('README.md')));
    });

    test('deleteFile removes the file', () async {
      await vfs.writeFile('temp.py', 'pass');
      await vfs.deleteFile('temp.py');
      final files = await vfs.listFiles();
      expect(files, isNot(contains('temp.py')));
    });
  });
}
