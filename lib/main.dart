import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:dart_monty_ide/src/assistant/default_prompt.dart';
import 'package:dart_monty_ide/src/assistant/system_prompt_builder.dart';
import 'package:dart_monty_ide/src/bridge/flutter_extension.dart';
import 'package:dart_monty_ide/src/bridge/llm_extension.dart';
import 'package:dart_monty_ide/src/bridge/prompt_extension.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:dart_monty_ide/src/llm/ollama_service.dart';
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

  // Setup Flutter Bridge.
  // The WidgetRegistry is durable (UI state across runs); extension instances
  // are recreated by the factory on each clearState(), because some — e.g.
  // EventLoopExtension — are one-shot and cannot be reused after dispose.
  final registry = WidgetRegistry();
  // Shared LLM config for the pilot_ask host function. Higher temperature
  // than the chat panel's default — pilot_ask is mostly used for creative
  // generation (text adventures, trivia, magic 8-balls).
  final llmConfig = LlmConfig(
    provider: LlmProvider.ollama,
    baseUrl: 'http://localhost:11434',
    model: 'gpt-oss:20b',
    temperature: 0.7,
  );

  List<MontyExtension> extensionsFactory() {
    final flutterExt = MontyFlutterExtension(registry);
    final eventLoopExt = EventLoopExtension();
    final promptExt = MontyPromptExtension();
    final llmExt = MontyLlmExtension(
      service: OllamaLlmService(),
      config: llmConfig,
    );
    final exts = <MontyExtension>[flutterExt, eventLoopExt, promptExt, llmExt];
    promptExt.snapshotBuilder = () => buildSystemPrompt(
          basePrompt: defaultAssistantPrompt,
          extensions: exts,
          scriptFragments: promptExt.fragments,
        );
    return exts;
  }

  final controller = MontyIdeController(extensionsFactory: extensionsFactory);

  // Seed sample files only if missing — never overwrite user edits.
  final existing = (await vfs.listFiles()).toSet();
  Future<void> seed(String path, String content) async {
    if (existing.contains(path)) return;
    await vfs.writeFile(path, content);
  }

  await seed(
    'onboarding.txt',
    '''# Welcome to Monty IDE

This is a small IDE for Monty — a sandboxed Python 3 interpreter
written in Rust and embedded in Flutter via dart_monty. Code runs in
the browser (web build) or a local Flutter app (macOS/Linux/Windows)
with no Python install required.


## What's in front of you

- File explorer (left): seeded examples + your own files.
- Editor: edit and Run any .py file.
- Console (below editor): print() output and errors.
- Monty UI panel (toolbar, "smart_display" icon): live Flutter widgets
  driven by Python via el_emit / el_recv.
- AI Pilot panel (chat icon): natural-language assistant that reads
  your buffer, writes/runs verified code, and can drive the running
  Monty UI script via ui_dispatch.
- Reset Interpreter (red restart button on toolbar): cancels any
  running script and clears the bridge — required after Monty UI
  loops, which run forever until reset.


## Try it

1. Open `examples/01_basics.py` and click Run — see the console.
2. Open `examples/04_gui_counter.py`, toggle the Monty UI panel,
   click Run. Use the buttons / slider in the panel.
3. Click Reset Interpreter (red button) before running another file.
4. Open `examples/06_thermostat.py` for a richer event-loop demo.


## Using the AI Pilot

The Pilot needs a *local* Ollama install. It is NOT bundled.

Steps:

1. Install Ollama: https://ollama.com/download
2. Pull the default model:
       ollama pull gpt-oss:20b
3. Allow this page's origin (CORS) — without this, the browser
   blocks every request even though Ollama is on localhost:

       OLLAMA_ORIGINS="*" ollama serve

   On macOS, if you launch Ollama from the menu bar app instead of a
   terminal:

       launchctl setenv OLLAMA_ORIGINS "*"
       # then quit and relaunch the Ollama app.

4. Reload this IDE. The blue "Connecting to Ollama…" banner above
   the chat input should turn green/disappear. If it goes red with
   "Can't reach Ollama", check the readme link in that banner.


## Asking the Pilot to drive the GUI

While a Monty UI script is running you can say things like:

- "set the target to 25"
- "click heat then step three times"
- "press +1"

The Pilot calls `ui_state` to read the panel, then `ui_dispatch` to
inject events into the running event loop — no need to write more
Python.


## Hello world (with type hints)

Open `hello.py`. Click Type Check, then Run. Both work even on the
event-loop demos because Type Check is pure static analysis.


## Where to go next

- docs/monty_ui.md — Monty UI panel + layered system prompt deep dive
- docs/web_deploy.md — Flutter web build, GitHub Pages, Ollama setup
- README.md — top-level overview

Have fun.
''',
  );
  await seed(
    'hello.py',
    'def hi(name: str) -> str:\n    return f"hello {name}"\n\nprint(hi("Monty"))\n',
  );
  await seed(
    'examples/01_python_tour.py',
    '"""A short tour of Monty\'s Python subset.\n'
        'Typed functions, comprehensions, f-strings, slicing, error handling.\n'
        'Records are dicts — Monty restricts plain `class`."""\n'
        '\n'
        'people: list[dict] = [\n'
        '    {"name": "Alice", "age": 30},\n'
        '    {"name": "Bob",   "age": 25},\n'
        '    {"name": "Carol", "age": 41},\n'
        '    {"name": "Dan",   "age": 17},\n'
        ']\n'
        '\n'
        'adults: list[dict] = [p for p in people if p["age"] >= 18]\n'
        'by_age: dict[int, str] = {p["age"]: p["name"] for p in adults}\n'
        '\n'
        'print(f"People: {len(people)}, adults: {len(adults)}")\n'
        'print(f"By age (adults only): {by_age}")\n'
        'print(f"First two names: {[p[\'name\'] for p in people[:2]]}")\n'
        '\n'
        '\n'
        'def safe_divide(a: int, b: int) -> float | None:\n'
        '    try:\n'
        '        return a / b\n'
        '    except ZeroDivisionError as e:\n'
        '        print(f"oops: {e}")\n'
        '        return None\n'
        '\n'
        '\n'
        'print(f"10 / 3 = {safe_divide(10, 3)}")\n'
        'print(f"10 / 0 = {safe_divide(10, 0)}")\n',
  );
  await seed(
    'examples/02_gui_counter.py',
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
  await seed(
    'examples/03_gui_thermostat.py',
    'prompt_extend(\n'
        '    "Thermostat: target temperature slider in Celsius (range 0..50), "\n'
        '    "Heat / Cool / Off mode buttons, fan-speed slider (1..5), and a "\n'
        '    "Step button that advances the simulated room temperature toward "\n'
        '    "the target. If the user gives a Fahrenheit value (e.g. 103 °F), "\n'
        '    "convert: C = (F - 32) * 5 / 9 and clamp to 0..50."\n'
        ')\n'
        '\n'
        'target = 20.0\n'
        'current = 18.0\n'
        'mode = "off"\n'
        'fan = 3\n'
        'ticks = 0\n'
        '\n'
        'while True:\n'
        '    delta = target - current\n'
        '    abs_delta = delta if delta >= 0 else -delta\n'
        '\n'
        '    if abs_delta < 0.05:\n'
        '        status = "✓ At target"\n'
        '    elif mode == "heat" and current < target:\n'
        '        status = "🔥 Heating"\n'
        '    elif mode == "cool" and current > target:\n'
        '        status = "❄️ Cooling"\n'
        '    elif mode == "off":\n'
        '        status = "⏸️ Off"\n'
        '    else:\n'
        '        status = "⏸️ Idle"\n'
        '\n'
        '    target_label = "Target: " + str(round(target, 1)) + " °C"\n'
        '    current_label = "Current: " + str(round(current, 1)) + " °C"\n'
        '    ticks_label = "Ticks: " + str(ticks)\n'
        '\n'
        '    el_emit({\n'
        '        "type": "column",\n'
        '        "children": [\n'
        '            {"type": "text", "value": "🏠 Thermostat", "size": 18},\n'
        '            {"type": "text", "value": target_label, "size": 14},\n'
        '            {"type": "slider", "id": "target", "label": "Target",\n'
        '             "min": 0, "max": 50, "value": target},\n'
        '            {"type": "text", "value": current_label, "size": 14},\n'
        '            {"type": "text", "value": status, "size": 14},\n'
        '            {"type": "row", "children": [\n'
        '                {"type": "button", "id": "heat", "label": "Heat"},\n'
        '                {"type": "button", "id": "cool", "label": "Cool"},\n'
        '                {"type": "button", "id": "off",  "label": "Off"},\n'
        '                {"type": "button", "id": "step", "label": "Step ▶"},\n'
        '            ]},\n'
        '            {"type": "slider", "id": "fan", "label": "Fan speed",\n'
        '             "min": 1, "max": 5, "value": fan},\n'
        '            {"type": "text", "value": ticks_label, "size": 12},\n'
        '        ],\n'
        '    })\n'
        '\n'
        '    evt = el_recv()\n'
        '    if evt["type"] == "quit":\n'
        '        break\n'
        '\n'
        '    t = evt["target"]\n'
        '    if t == "target":\n'
        '        target = evt["value"]\n'
        '    elif t == "fan":\n'
        '        fan = int(evt["value"])\n'
        '    elif t == "heat":\n'
        '        mode = "heat"\n'
        '    elif t == "cool":\n'
        '        mode = "cool"\n'
        '    elif t == "off":\n'
        '        mode = "off"\n'
        '    elif t == "step":\n'
        '        ticks = ticks + 1\n'
        '        rate = 0.2 * fan\n'
        '        if mode == "heat" and current < target:\n'
        '            current = current + rate\n'
        '            if current > target:\n'
        '                current = target\n'
        '        elif mode == "cool" and current > target:\n'
        '            current = current - rate\n'
        '            if current < target:\n'
        '                current = target\n',
  );
  await seed(
    'examples/04_llm_text_adventure.py',
    '# REQUIRES OLLAMA: this script calls pilot_ask(...) for narrative.\n'
        '# Each click of "Continue" sends the running story to the LLM and\n'
        '# appends what comes back. Type a custom action to steer the plot.\n'
        'prompt_extend(\n'
        '    "Text adventure: the script calls pilot_ask() to continue a "\n'
        "    \"branching narrative. Don't drive this with ui_dispatch — let the user play.\"\n"
        ')\n'
        '\n'
        'story: str = "You are standing in a dusty library, three doors before you. The brass door hums faintly."\n'
        'last_action: str = ""\n'
        '\n'
        'while True:\n'
        '    el_emit({\n'
        '        "type": "column",\n'
        '        "children": [\n'
        '            {"type": "text", "value": "📖 Monty Adventure", "size": 18},\n'
        '            {"type": "text", "value": story},\n'
        '            {"type": "text_field", "id": "action", "value": last_action,\n'
        '             "hint": "What do you do? (or just press Continue)"},\n'
        '            {"type": "row", "children": [\n'
        '                {"type": "button", "id": "continue", "label": "Continue"},\n'
        '                {"type": "button", "id": "restart", "label": "Restart"},\n'
        '            ]},\n'
        '        ],\n'
        '    })\n'
        '    evt = el_recv()\n'
        '    if evt["type"] == "quit":\n'
        '        break\n'
        '    target = evt["target"]\n'
        '    if target == "action" and evt["type"] == "submit":\n'
        '        last_action = evt["value"]\n'
        '    elif target == "restart":\n'
        '        story = "You are standing in a dusty library, three doors before you. The brass door hums faintly."\n'
        '        last_action = ""\n'
        '    elif target == "continue":\n'
        '        action_text = last_action if last_action else "the player waits"\n'
        '        prompt = (\n'
        '            "You are the narrator of a short, atmospheric text adventure. "\n'
        '            "Continue the story with ONE short paragraph (2-3 sentences). "\n'
        '            "End by hinting at 2-3 possible next actions. "\n'
        '            "Story so far: " + story + "\\n"\n'
        '            "Player action: " + action_text\n'
        '        )\n'
        '        next_chunk = pilot_ask(prompt)\n'
        '        story = story + "\\n\\n" + next_chunk.strip()\n'
        '        last_action = ""\n'
        '\n'
        'print("THE END")\n',
  );
  await seed(
    'examples/05_llm_trivia.py',
    '# REQUIRES OLLAMA: this script generates trivia via pilot_ask(...).\n'
        '# Click "New question" — the LLM produces Q + 4 options. Pick one;\n'
        '# the script asks the LLM to judge.\n'
        'prompt_extend(\n'
        '    "Trivia: the script calls pilot_ask() to generate a question and "\n'
        '    "to grade the user\'s answer. Score is kept in Python state."\n'
        ')\n'
        '\n'
        'import json\n'
        '\n'
        'score: int = 0\n'
        'asked: int = 0\n'
        'question: str = "Click \\"New question\\" to begin."\n'
        'options: list[str] = ["A", "B", "C", "D"]\n'
        'feedback: str = ""\n'
        'last_correct: str = ""\n'
        '\n'
        'def fetch_question() -> dict:\n'
        '    raw = pilot_ask(\n'
        '        \'Generate a single trivia question. Return ONLY valid JSON \'\n'
        '        \'with these keys: "q" (the question, string), "options" (list \'\n'
        '        \'of 4 short strings, no labels), "answer" (one of the option \'\n'
        '        \'strings, exactly matching). No markdown, no preamble.\'\n'
        '    )\n'
        '    try:\n'
        '        return json.loads(raw)\n'
        '    except json.JSONDecodeError:\n'
        '        return {"q": "(parse error)", "options": ["A", "B", "C", "D"], "answer": "A"}\n'
        '\n'
        'while True:\n'
        '    score_label = "Score: " + str(score) + " / " + str(asked)\n'
        '    el_emit({\n'
        '        "type": "column",\n'
        '        "children": [\n'
        '            {"type": "text", "value": "🧠 Monty Trivia", "size": 18},\n'
        '            {"type": "text", "value": score_label, "size": 12},\n'
        '            {"type": "text", "value": question, "size": 14},\n'
        '            {"type": "row", "children": [\n'
        '                {"type": "button", "id": "opt0", "label": options[0]},\n'
        '                {"type": "button", "id": "opt1", "label": options[1]},\n'
        '            ]},\n'
        '            {"type": "row", "children": [\n'
        '                {"type": "button", "id": "opt2", "label": options[2]},\n'
        '                {"type": "button", "id": "opt3", "label": options[3]},\n'
        '            ]},\n'
        '            {"type": "text", "value": feedback, "size": 12},\n'
        '            {"type": "button", "id": "next", "label": "New question"},\n'
        '        ],\n'
        '    })\n'
        '    evt = el_recv()\n'
        '    if evt["type"] == "quit":\n'
        '        break\n'
        '    target = evt["target"]\n'
        '    if target == "next":\n'
        '        feedback = "Thinking..."\n'
        '        q = fetch_question()\n'
        '        question = q["q"]\n'
        '        options = q["options"]\n'
        '        last_correct = q["answer"]\n'
        '        feedback = ""\n'
        '    elif target.startswith("opt"):\n'
        '        idx = int(target[3:])\n'
        '        picked = options[idx]\n'
        '        asked = asked + 1\n'
        '        if picked == last_correct:\n'
        '            score = score + 1\n'
        '            feedback = "✅ Correct!"\n'
        '        else:\n'
        '            feedback = "❌ Wrong. Answer: " + last_correct\n'
        '\n'
        'print("Final score: " + str(score) + " / " + str(asked))\n',
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
  ));
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

  /// The Monty IDE controller. The current extension instances are
  /// resolved live from `controller.extensions` so they can be swapped on
  /// Reset Interpreter.
  final MontyIdeController controller;

  /// The widget registry for the bridge (durable across runs).
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
