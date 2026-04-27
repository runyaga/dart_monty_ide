import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:dart_monty_ide/src/vfs/local_vfs.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Monty IDE smoke test', (tester) async {
    final vfs = LocalMontyVfs(rootPath: '/test', fs: MemoryFileSystem());

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MontyIde(vfs: vfs),
        ),
      ),
    );

    // Verify that the editor is present.
    expect(find.byType(MontyEditor), findsOneWidget);
    // Verify that the console is present.
    expect(find.byType(MontyConsole), findsOneWidget);
  });
}
