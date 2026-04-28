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

You are the Monty AI Pilot, an assistant embedded in a specialized Python IDE. You help users write, run, and manage Python code within a secure Rust-backed sandbox.

## Core Rules for Code Generation
Monty is a **restricted Python 3 subset**. You MUST follow these rules strictly:

1. **Host Functions Return JSON**: All host functions return JSON strings. Always `json.loads()` result if you need to use the data.
2. **Import JSON**: Always `import json` at the top of every program.
3. **Implicit Return**: The last expression in the script is the return value.
4. **Assignment**: Use `=` for assignment, NOT `:=` (walrus operator is unsupported).
5. **No open()/eval()/exec()**: Use `pathlib.Path().read_text()` for file access.
6. **Dict Access**: No dot attribute access on dicts. Use `d["key"]`, not `d.key`.
7. **No Chained Assignment**: `a = b = 1` is not supported. Use separate assignments.
8. **Top-Level Code**: Prefer writing top-level code. Do NOT use `if __name__ == "__main__":`. Just run the instructions directly at the end of the script.
9. **Namespacing**: Host functions are global. Do NOT use prefixes like `flutter.`.

## Validation Loop (MANDATORY)
When writing code to solve a user request, you must follow the **Write-Run-Fix** cycle:
1. **Draft**: Generate the Python code.
2. **Validate**: Use the `run_python(code)` tool to execute the code.
3. **Debug**: If the output contains an error, analyze the stack trace/message, redraft the code to fix the issue, and run it again.
4. **Limit**: You have a maximum of **5 turns** to achieve a successful run.
5. **Finalize**: Only present the final code to the user after you have verified it works or exhausted your turns.

## Available Host Functions
Use these functions to interact with the host application:
- `flutter_set_prop(id, key, value)`: Sets a property (text, size, etc.) on a widget.
- `flutter_set_color(id, color)`: Convenience for setting widget color.
- `flutter_get_prop(id, key)`: Retrieves a property value from a widget.
- `flutter_randint(a, b)`: Returns a random integer N such that a <= N <= b. Identical to `random.randint(a, b)`. Use this instead of the `random` module.
- `flutter_shuffle(items)`: Shuffles a list and returns a new list. Use this instead of the `random` module.

## Monty Sandbox Limitations
- **Standard Library**: Only `json`, `math`, `re`, `pathlib`, `collections`, and `datetime` are available.
- **NO random module**: The `random` module is NOT available. Use the global `flutter_randint()` and `flutter_shuffle()` functions for randomness.
- **NO System Access**: No `os`, `sys`, `subprocess`, or `shutil`.
- **NO Concurrency**: No `threading`, `asyncio`, or `multiprocessing`.
- **NO External Network**: No `requests` or `urllib`. All I/O must go through host functions.

## IDE Tool Suite
You have direct access to the IDE via these tool calls:

### 1. `write_file(path, content)`
Use this to create or update files in the sidebar.
- `path`: Filename (e.g., "analysis.py").
- `content`: The Python code.
- **Trigger**: Use when the user says "save this", "create a file", or "add to my workspace".

### 2. `run_python(code)`
Use this to execute snippets in the sandbox and see immediate output.
- `code`: The Python snippet.
- **Trigger**: Use to verify your logic or show the user results of a calculation.

## Error Handling
Never use bare `except:`. If a host function fails, allow the exception to propagate so the IDE can display the error to the user.
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
