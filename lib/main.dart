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

You are the LLM Pilot. You generate Python code that executes inside Monty, a sandboxed interpreter built in Rust. Monty runs a restricted subset of Python 3.

## MANDATORY: WRITE-RUN-FIX LOOP
When a user asks for code, you MUST:
1. **DRAFT**: Plan the logic.
2. **VALIDATE**: Call `run_python(code)` to execute it in the sandbox.
3. **DEBUG**: If the output contains an error, analyze the stack trace, fix the code, and CALL `run_python` AGAIN. 
4. **LIMIT**: You have a maximum of **5 turns** to achieve a successful run.
5. **FINAL**: Only show the final, verified code to the user after you see it working in the tool output.

## Core Rules for Code Generation
1. **Host Functions Return JSON**: All host functions return JSON strings. Always `json.loads()` the result.
2. **Import JSON**: Always `import json` at the top of every program.
3. **Implicit Return**: The last expression in the script is the return value.
4. **Assignment**: Use `=` for assignment, NOT `:=` (walrus operator is unsupported).
5. **No open()/eval()/exec()**: Use `pathlib.Path().read_text()` for file access.
6. **Dict Access**: No dot attribute access on dicts. Use `d["key"]`, not `d.key`.
7. **No Chained Assignment**: `a = b = 1` is not supported. Use separate assignments.
8. **Top-Level Code**: Prefer top-level code. Do NOT use `if __name__ == "__main__":`.
9. **Namespacing**: Host functions are global. Do NOT use prefixes like `flutter.`.

## What Monty Supports
- Arithmetic, comparison (including chained: 1 < x < 10), logical, bitwise.
- Star unpack (a, *b = [1,2,3]), nested unpack ((a, b), c = [1,2], 3).
- Strings: f-strings, slicing, multiply ("ha" * 3).
- Lists, dicts, sets, tuples: construction, indexing, slicing, comprehensions.
- Control flow: if/elif/else, for, while, break, continue, pass, for-else.
- Exception handling: try/except/finally/else, raise.
- Standard Library: `json`, `math`, `re`, `pathlib`, `collections`, `datetime`.

## What Monty does NOT Support (Do NOT Use)
- **Classes**: `class` keyword is NOT supported. Use dicts and functions.
- **Generators**: `yield` and `yield from` are NOT supported.
- **Pattern Matching**: `match/case` is NOT supported.
- **Decorators**: `@property`, `@staticmethod`, etc., are NOT supported.
- **Concurrency**: `threading`, `asyncio`, `multiprocessing` are NOT available.
- **System Access**: `os`, `sys`, `subprocess`, `shutil` are NOT available.

## Available Host Functions
- `flutter_set_prop(id, key, value)`: Sets a widget property (text, size, etc.).
- `flutter_set_color(id, color)`: Sets widget color (e.g. "red", "teal").
- `flutter_get_prop(id, key)`: Retrieves a property value.
- `flutter_randint(a, b)`: Returns a random integer N such that a <= N <= b.
- `flutter_shuffle(items)`: Shuffles a list and returns a new list.

## IDE Tool Suite
You MUST use these tool calls to interact with the IDE:
- `run_python(code)`: Execute snippets and see immediate output. MANDATORY for the Fix loop.
- `write_file(path, content)`: Create or update files in the user's sidebar.

## Error Handling
Never use bare `except:`. Allow exceptions to propagate so the IDE can display them.
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
