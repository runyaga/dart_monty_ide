import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:dart_monty_ide/src/bridge/flutter_extension.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:dart_monty_ide/src/vfs/local_vfs.dart';
import 'package:dart_monty_ide/src/vfs/memory_vfs.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MontyVfs vfs;
  if (kIsWeb) {
    vfs = MemoryMontyVfs();
  } else {
    final appDocsDir = await getApplicationDocumentsDirectory();
    final workspacePath = '${appDocsDir.path}/monty_workspace';
    vfs = LocalMontyVfs(rootPath: workspacePath);
  }

  // Setup Flutter Bridge
  final registry = WidgetRegistry();
  final flutterExtension = MontyFlutterExtension(registry);
  final controller = MontyIdeController(extensions: [flutterExtension]);

  // Seed sample files
  await vfs.writeFile(
    'hello.py',
    'def hi(name):\n    return f"hello {name}"\n\nprint(hi("Monty"))\n',
  );

  await vfs.writeFile(
    'examples/01_basics.py',
    'def welcome(name):\n'
        '    return f"Greetings, {name}!"\n\n'
        'print(welcome("Engineer"))\n',
  );
  await vfs.writeFile(
    'examples/02_logic.py',
    'numbers = [1, 2, 3, 4, 5]\n'
        'print(f"Squares: {[n**2 for n in numbers]}")\n',
  );
  await vfs.writeFile(
    'examples/03_gui.py',
    'print("🎨 Updating Flutter widgets...")\n'
        'flutter_set_color("box_1", "teal")\n'
        'flutter_set_prop("label_1", "text", "Updated from Monty Python!")\n'
        'print("Done.")\n',
  );

  const defaultPrompt = '''
# Monty Sandbox — AI Assistant Prompt Rules

You are the LLM Pilot. You operate inside a secure Python IDE.

## MANDATORY: WRITE-RUN-FIX LOOP
When a user asks for code, you MUST:
1. **DRAFT**: Plan the code.
2. **VALIDATE**: Call `run_python(code)` to execute it in the sandbox.
3. **DEBUG**: If the output contains an error, analyze it, fix the code, and CALL `run_python` AGAIN. 
4. **LIMIT**: Do this up to 5 times until it works.
5. **FINAL**: Only after you see it working in the tool output, you may show the final code to the user.

## Core Rules
- Monty is Python 3 subset. No classes.
- Use `flutter_set_prop(id, key, value)` and `flutter_set_color(id, color)` for GUI.
- Host functions return JSON strings.
- import json at the top of every program.
- No `if __name__ == "__main__":`. Run instructions directly at the end.

## Tools
- `run_python(code)`: Execute code in sandbox.
- `write_file(path, content)`: Save to workspace.

If you don't call `run_python` to verify your code, you have failed your mission.
''';

  final files = await vfs.listFiles();
  if (!files.contains('system_prompt.txt')) {
    await vfs.writeFile('system_prompt.txt', defaultPrompt);
  }

  runApp(MyApp(vfs: vfs, controller: controller, registry: registry));
}

/// The main application widget.
class MyApp extends StatelessWidget {
  /// Creates a [MyApp].
  const MyApp({
    required this.vfs,
    required this.controller,
    required this.registry,
    super.key,
  });

  /// The VFS instance.
  final MontyVfs vfs;

  /// The Monty IDE controller.
  final MontyIdeController controller;

  /// The widget registry for the bridge.
  final WidgetRegistry registry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monty IDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MyHomePage(vfs: vfs, controller: controller, registry: registry),
    );
  }
}

/// The home page of the Monty IDE application.
class MyHomePage extends StatelessWidget {
  /// Creates a [MyHomePage].
  const MyHomePage({
    required this.vfs,
    required this.controller,
    required this.registry,
    super.key,
  });

  /// The VFS instance.
  final MontyVfs vfs;

  /// The Monty IDE controller.
  final MontyIdeController controller;

  /// The widget registry for the bridge.
  final WidgetRegistry registry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Monty Python IDE'),
      ),
      body: MontyIde(
        vfs: vfs,
        controller: controller,
        registry: registry,
      ),
    );
  }
}
