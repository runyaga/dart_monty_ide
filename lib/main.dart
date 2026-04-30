import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:dart_monty_ide/src/assistant/default_prompt.dart';
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
  final eventLoopExtension = EventLoopExtension();
  final controller = MontyIdeController(
    extensions: [flutterExtension, eventLoopExtension],
  );

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
  await vfs.writeFile(
    'examples/05_gui_temp.py',
    '# Temperature converter — drag the slider or click a preset.\n'
        '# Open the "Monty UI" panel before running.\n'
        'celsius = 20.0\n'
        '\n'
        'while True:\n'
        '    fahrenheit = celsius * 9 / 5 + 32\n'
        '    kelvin = celsius + 273.15\n'
        '    el_emit({\n'
        '        "type": "column",\n'
        '        "children": [\n'
        '            {"type": "text", "value": "🌡️  Temperature Converter", "size": 18},\n'
        '            {"type": "slider", "id": "c", "label": "Celsius", "min": -50, "max": 150, "value": celsius},\n'
        '            {"type": "text", "value": f"{round(celsius, 1)}°C  =  {round(fahrenheit, 1)}°F  =  {round(kelvin, 1)} K", "size": 14},\n'
        '            {"type": "row", "children": [\n'
        '                {"type": "button", "id": "freeze", "label": "Freezing (0°C)"},\n'
        '                {"type": "button", "id": "body", "label": "Body (37°C)"},\n'
        '                {"type": "button", "id": "boil", "label": "Boiling (100°C)"},\n'
        '            ]},\n'
        '        ],\n'
        '    })\n'
        '    evt = el_recv()\n'
        '    if evt["type"] == "quit":\n'
        '        break\n'
        '    target = evt["target"]\n'
        '    if target == "c":\n'
        '        celsius = evt["value"]\n'
        '    elif target == "freeze":\n'
        '        celsius = 0.0\n'
        '    elif target == "body":\n'
        '        celsius = 37.0\n'
        '    elif target == "boil":\n'
        '        celsius = 100.0\n'
        '\n'
        'print(f"Final: {round(celsius, 1)}°C")\n',
  );
  await vfs.writeFile(
    'examples/04_gui_counter.py',
    '# Open the "Monty UI" panel from the toolbar before running.\n'
        'count = 0\n'
        '\n'
        'while True:\n'
        '    el_emit({\n'
        '        "type": "column",\n'
        '        "children": [\n'
        '            {"type": "text", "value": "Monty UI Counter", "size": 18},\n'
        '            {"type": "text", "value": f"Count: {count}"},\n'
        '            {"type": "row", "children": [\n'
        '                {"type": "button", "id": "inc", "label": "+1"},\n'
        '                {"type": "button", "id": "dec", "label": "-1"},\n'
        '                {"type": "button", "id": "reset", "label": "Reset"},\n'
        '            ]},\n'
        '            {"type": "slider", "id": "speed", "label": "Set", "min": 0, "max": 100, "value": count},\n'
        '        ],\n'
        '    })\n'
        '    evt = el_recv()\n'
        '    if evt["type"] == "quit":\n'
        '        break\n'
        '    target = evt["target"]\n'
        '    if target == "inc":\n'
        '        count = count + 1\n'
        '    elif target == "dec":\n'
        '        count = count - 1\n'
        '    elif target == "reset":\n'
        '        count = 0\n'
        '    elif target == "speed":\n'
        '        count = int(evt["value"])\n'
        '\n'
        'print(f"Final count: {count}")\n',
  );

  final files = await vfs.listFiles();
  bool shouldUpdate = !files.contains('system_prompt.txt');
  if (!shouldUpdate) {
    final current = await vfs.readFile('system_prompt.txt');
    if (current.trim() != defaultAssistantPrompt.trim()) {
      shouldUpdate = true;
    }
  }

  if (shouldUpdate) {
    await vfs.writeFile('system_prompt.txt', defaultAssistantPrompt);
  }

  runApp(MyApp(
    vfs: vfs,
    controller: controller,
    registry: registry,
    eventLoop: eventLoopExtension,
  ));
}

/// The main application widget.
class MyApp extends StatelessWidget {
  /// Creates a [MyApp].
  const MyApp({
    required this.vfs,
    required this.controller,
    required this.registry,
    required this.eventLoop,
    super.key,
  });

  /// The VFS instance.
  final MontyVfs vfs;

  /// The Monty IDE controller.
  final MontyIdeController controller;

  /// The widget registry for the bridge.
  final WidgetRegistry registry;

  /// The event-loop extension that powers the Monty UI panel.
  final EventLoopExtension eventLoop;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monty IDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MyHomePage(
        vfs: vfs,
        controller: controller,
        registry: registry,
        eventLoop: eventLoop,
      ),
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
    required this.eventLoop,
    super.key,
  });

  /// The VFS instance.
  final MontyVfs vfs;

  /// The Monty IDE controller.
  final MontyIdeController controller;

  /// The widget registry for the bridge.
  final WidgetRegistry registry;

  /// The event-loop extension that powers the Monty UI panel.
  final EventLoopExtension eventLoop;

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
        eventLoop: eventLoop,
      ),
    );
  }
}
