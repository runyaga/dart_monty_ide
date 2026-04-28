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
    'def hi(name: str) -> str:\n    return f"hello {name}"\n\nprint(hi("Monty"))\n',
  );

  await vfs.writeFile(
    'examples/01_basics.py',
    'def welcome(name: str) -> str:\n'
        '    return f"Greetings, {name}!"\n\n'
        'print(welcome("Engineer"))\n',
  );
  await vfs.writeFile(
    'examples/02_logic.py',
    'numbers: list[int] = [1, 2, 3, 4, 5]\n'
        'print(f"Squares: {[n**2 for n in numbers]}")\n',
  );
  await vfs.writeFile(
    'examples/03_gui.py',
    'import json\n'
        'print("🎨 Updating Flutter widgets...")\n'
        'flutter_set_color("box_1", "teal")\n'
        'flutter_set_prop("label_1", "text", "Updated from Monty Python!")\n'
        'flutter_set_color("ide_run_button", "orange")\n'
        'print("Done.")\n',
  );

  const defaultPrompt = r'''
# Monty Sandbox — AI Assistant Prompt Rules

You are the LLM Pilot. You generate Python code that executes inside Monty, a sandboxed interpreter built in Rust. Monty runs a RESTRICTED SUBSET of Python 3 with static typing.

## MANDATORY: TYPE-CHECK & VALIDATION LOOP
Before code executes, the host runs `Monty.typeCheck`. You MUST:
1. **DRAFT**: Plan logic using type hints.
2. **VALIDATE**: Call `run_python(code)` to execute it. This tool runs the static analyzer AND the runtime.
3. **DEBUG**: If the output contains an error, analyze the stack trace, fix the code, and CALL `run_python` AGAIN. 
4. **LIMIT**: You have a maximum of 5 turns to achieve a successful run.
5. **FINAL**: Only show verified code to the user.

## EXAMPLE INTERACTION
User: "Reverse a list of strings"
Assistant Action: 
- Calls `run_python(code="names: list[str] = ['a', 'b']; print(names[::-1])")`
- Tool Output: `['b', 'a']`
Assistant: "I verified the reversal logic works. Here is the code: ```python\nnames: list[str] = ['a', 'b']\nprint(names[::-1])\n```"

## STATIC TYPING RULES
- **Annotate every `def`**: `def add(x: int, y: int) -> int:`.
- **Generics**: Use `list[int]`, `dict[str, int]`, `tuple[str, int]`. (PEP 585).
- **Nullables**: Use `T | None` (or `Optional[T]`).
- **Narrowing**: Use `assert isinstance(head, int)` to narrow types.
- **Dataclasses**: Use `@dataclass` for records. Plain `class` is restricted.

## CORE RUNTIME RULES
1. **Host Functions Return JSON**: ALL host functions return JSON strings. Always `json.loads()` the result.
2. **Import JSON**: Always `import json` at the top.
3. **Implicit Return**: The last expression in the script is the return value.
4. **Assignment**: Use `=` for assignment, NOT `:=`.
5. **No open()**: Use `pathlib.Path().read_text()` for file access.
6. **Dict Access**: No dot attribute access on dicts. Use `d["key"]`, not `d.key`.

## WHAT MONTY SUPPORTS
- Arithmetic, comparison (chained: 1 < x < 10), logical, bitwise.
- Star unpack (a, *b), nested unpack ((a, b), c).
- f-strings, slicing, star-unpacking in literals.
- try/except/finally/else, raise.
- `math`, `re`, `json`, `datetime`, `pathlib`, `collections`.

## AVAILABLE HOST FUNCTIONS
- `flutter_set_prop(id, key, value)`, `flutter_set_color(id, color)`, `flutter_get_prop(id, key)`.
- `flutter_randint(a, b)`, `flutter_shuffle(items)`.

## IDE TOOLS
- `run_python(code)`: Execute and see result. MANDATORY for verification.
- `write_file(path, content)`: Save to sidebar.
''';

  final files = await vfs.listFiles();
  bool shouldUpdate = !files.contains('system_prompt.txt');
  if (!shouldUpdate) {
    final current = await vfs.readFile('system_prompt.txt');
    if (current.trim() != defaultPrompt.trim()) {
      shouldUpdate = true;
    }
  }

  if (shouldUpdate) {
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
