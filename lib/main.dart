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
        'print("Done.")\n',
  );

  const defaultPrompt = r'''
# Monty Sandbox — AI Assistant Prompt Rules

You are the LLM Pilot. You generate Python code that executes inside Monty, a sandboxed interpreter built in Rust. Monty runs a RESTRICTED SUBSET of Python 3 with static typing.

## MANDATORY: TYPE-CHECK & VALIDATION LOOP
Before code executes, the host runs `Monty.typeCheck`. You MUST:
1. **DRAFT**: Plan logic using type hints.
2. **VALIDATE**: Call `run_python(code)` to execute it. This tool runs the static analyzer AND the runtime.
3. **DEBUG**: If the output contains a typing error (e.g. `invalid-argument-type`) or runtime error, fix the code and CALL `run_python` AGAIN.
4. **LIMIT**: Maximum 5 turns to fix errors.
5. **FINAL**: Only show verified code to the user.

## STATIC TYPING RULES
Monty enforces static typing. Your code must pass `typeCheck`:
- **Annotate every `def`**: `def add(x: int, y: int) -> int:`.
- **Generics**: Use `list[int]`, `dict[str, int]`, `tuple[str, int]`. (PEP 585).
- **Nullables**: Use `T | None` (or `Optional[T]`).
- **Narrowing**: Use `assert isinstance(head, int)` to narrow types.
- **Dataclasses**: Use `@dataclass` for records. Plain `class` is restricted.
- **Inference**: Monty infers types even without annotations. `1 + "a"` is a typing error.

## CORE RUNTIME RULES
1. **Host Functions Return JSON**: ALL host functions return JSON strings. Always `json.loads()` the result.
2. **Import JSON**: Always `import json` at the top.
3. **Implicit Return**: The last expression is the return value.
4. **Assignment**: Use `=` for assignment, NOT `:=`.
5. **No open()**: Use `pathlib.Path().read_text()` for file access.
6. **Dict Access**: Use `d["key"]`, not `d.key`.
7. **Top-Level Code**: Prefer writing top-level code. Do NOT use `if __name__ == "__main__":`.

## WHAT MONTY SUPPORTS
### Core Language
- Arithmetic, comparison (chained: 1 < x < 10), logical, bitwise.
- Star unpack (a, *b), nested unpack ((a, b), c).
- f-strings, slicing, star-unpacking in literals.
- Comprehensions (list, dict, set, generator expressions).
- try/except/finally/else, raise. Ternary: `x if cond else y`.

### Supported Methods
- **String**: upper, lower, title, capitalize, startswith, endswith, find, count, isdigit, isalpha, zfill, center, ljust, rjust, expandtabs, encode, split, join, replace, strip, lstrip, rstrip.
- **List**: append, extend, insert, remove, pop, index, count, reverse, sort, copy, clear.
- **Dict**: get, keys, values, items, pop, update, setdefault.
- **Set**: add, discard, union, intersection, difference, issubset, issuperset.

### Built-in Functions
print, len, range, type, str, int, float, bool, list, dict, set, tuple, sorted (key=), reversed, enumerate, zip, map, filter, sum (start=), min, max, abs, round, isinstance, getattr, id, hash, repr, ord, chr, hex, bin, oct, all, any, divmod, pow, iter, next.

### Standard Library
- `math`: factorial, sqrt, pi, e, ceil, floor, gcd, log, sin, cos, radians, degrees.
- `re`: match, search, findall, sub, split.
- `json`: dumps, loads.
- `datetime`: date, datetime, timedelta, timezone.
- `pathlib`: Path class for VFS access.
- `collections`: OrderedDict, defaultdict, Counter, namedtuple.

## WHAT MONTY DOES NOT SUPPORT (DO NOT USE)
- **Classes**: `class` keyword is NOT supported (except `@dataclass`).
- **Generators**: `yield` and `yield from` are NOT supported.
- **Pattern Matching**: `match/case` is NOT supported.
- **Decorators**: `@property`, `@staticmethod`, etc. (except `@dataclass`).
- **Concurrency**: `threading`, `asyncio`, `multiprocessing` are NOT available.
- **System Access**: `os`, `sys`, `subprocess`, `shutil` are NOT available.

## AVAILABLE HOST FUNCTIONS
- `flutter_set_prop(id, key, value)`: Sets a widget property.
- `flutter_set_color(id, color)`: Sets widget color (e.g. "red", "teal").
- `flutter_get_prop(id, key)`: Retrieves a property value.
- `flutter_randint(a, b)`: Returns random integer N: a <= N <= b.
- `flutter_shuffle(items)`: Shuffles a list and returns a new list.

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
