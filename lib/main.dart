import 'dart:io';

import 'package:dart_duckdb/dart_duckdb.dart';
import 'package:dart_duckdb/open.dart';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:dart_monty_ide/src/assistant/default_prompt.dart';
import 'package:dart_monty_ide/src/assistant/system_prompt_builder.dart';
import 'package:dart_monty_ide/src/bridge/console_svg_host_api.dart';
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
import 'package:hhg_dataframe/hhg_dataframe.dart';
import 'package:hhg_duckdb/hhg_duckdb.dart';
import 'package:hhg_svg/hhg_svg.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // libduckdb resolution for macOS pure-Dart-style FFI binding.
  // dart_duckdb 1.4.4 doesn't bundle the dylib on macOS; with Flutter's
  // plugin layer in play this typically just works, but DUCKDB_LIBPATH
  // wins if set, and a known probe path is the fallback.
  if (!kIsWeb && Platform.isMacOS) {
    final lib = Platform.environment['DUCKDB_LIBPATH'] ??
        '/tmp/duckdb-spatial-probe/duckdb_lib/libduckdb.dylib';
    if (File(lib).existsSync()) {
      open.overrideFor(OperatingSystem.macOS, lib);
    }
  }

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

  // The SvgHostApi takes a callback so it can be constructed before
  // the controller exists (the factory below references the host api
  // before the controller is built). The closure resolves the
  // controller lazily; by the time `render(...)` fires, the controller
  // has been assigned.
  late final MontyIdeController controller;
  final svgHostApi = ConsoleSvgHostApi(
    (line) => controller.appendOutput(line),
  );

  List<MontyExtension> extensionsFactory() {
    final flutterExt = MontyFlutterExtension(registry);
    final eventLoopExt = EventLoopExtension();
    final promptExt = MontyPromptExtension();
    final llmExt = MontyLlmExtension(
      service: OllamaLlmService(),
      config: llmConfig,
    );
    final dataframeExt = DataFrameExtension();
    // autoLoadSpatial: false — loading the unsigned spatial extension
    // triggers macOS Gatekeeper. Scripts that want it can call
    // duck_execute("INSTALL spatial") + duck_execute("LOAD spatial")
    // themselves; the user will see the Gatekeeper prompt once and
    // can Allow Anyway in System Preferences > Privacy & Security.
    final duckDbExt = DuckDbExtension(autoLoadSpatial: false);
    final svgExt = SvgExtension(hostApi: svgHostApi);
    final exts = <MontyExtension>[
      flutterExt,
      eventLoopExt,
      promptExt,
      llmExt,
      dataframeExt,
      duckDbExt,
      svgExt,
    ];
    promptExt.snapshotBuilder = () => buildSystemPrompt(
          basePrompt: defaultAssistantPrompt,
          extensions: exts,
          scriptFragments: promptExt.fragments,
        );
    return exts;
  }

  controller = MontyIdeController(extensionsFactory: extensionsFactory);

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
    r'''# REQUIRES OLLAMA: this script calls pilot_ask(...) for narrative.
# Each click of "Continue" sends the running story to the LLM and
# appends what comes back. Type a custom action to steer the plot.
prompt_extend(
    "Text adventure: the script calls pilot_ask() to continue a "
    "branching narrative. Don't drive this with ui_dispatch — let the user play."
)

START = (
    "You are standing in a dusty library, three doors before you. "
    "The brass door hums faintly."
)

story: str = START
last_action: str = ""

while True:
    el_emit({
        "type": "column",
        "children": [
            {"type": "text", "value": "📖 Monty Adventure", "size": 18},
            {"type": "text", "value": story},
            {"type": "text_field", "id": "action", "value": last_action,
             "hint": "What do you do? (or just press Continue)"},
            {"type": "row", "children": [
                {"type": "button", "id": "continue", "label": "Continue"},
                {"type": "button", "id": "restart", "label": "Restart"},
            ]},
        ],
    })
    evt = el_recv()
    if evt["type"] == "quit":
        break
    target = evt["target"]
    if target == "action" and evt["type"] == "submit":
        last_action = evt["value"]
    elif target == "restart":
        story = START
        last_action = ""
    elif target == "continue":
        # Show a thinking state while pilot_ask blocks on the LLM.
        el_emit({
            "type": "column",
            "children": [
                {"type": "text", "value": "📖 Monty Adventure", "size": 18},
                {"type": "text", "value": story},
                {"type": "text", "value": "🤔 The narrator is thinking…", "size": 12},
            ],
        })
        action_text = last_action if last_action else "the player waits"
        prompt = (
            "You are the narrator of a short, atmospheric text adventure. "
            "Continue the story with ONE short paragraph (2-3 sentences). "
            "End by hinting at 2-3 possible next actions.\n"
            f"Story so far: {story}\n"
            f"Player action: {action_text}"
        )
        next_chunk = pilot_ask(prompt)
        story = story + "\n\n" + next_chunk.strip()
        last_action = ""

print("THE END")
''',
  );
  await seed(
    'examples/05_llm_trivia.py',
    r'''# REQUIRES OLLAMA: this script generates trivia via pilot_ask(...).
# Click "New question" — the LLM produces Q + 4 options. Pick one;
# the script grades it locally and rotates topics to avoid repeats.
prompt_extend(
    "Trivia: the script calls pilot_ask() to generate a question. "
    "Score and history are kept in Python state. Topics rotate."
)

import json

score: int = 0
asked: int = 0
question: str = 'Click "New question" to begin.'
options: list[str] = ["A", "B", "C", "D"]
feedback: str = ""
last_correct: str = ""
topics: list[str] = [
    "1980s movies", "ancient history", "marine biology",
    "world capitals", "classical music", "computer science",
    "mythology", "famous paintings", "space exploration",
    "physics", "Olympic sports", "literature",
]
recent: list[str] = []


def fetch_question() -> dict:
    topic = topics[asked % len(topics)]
    avoid = "; ".join(recent[-5:]) if recent else "(none)"
    prompt = (
        f"Generate ONE trivia question about {topic}. "
        f"Avoid repeating these recent questions: {avoid}. "
        'Return ONLY valid JSON with these keys: '
        '"q" (string, the question), '
        '"options" (list of 4 distinct short strings, no A/B/C/D labels, in random order), '
        '"answer" (one of the option strings, exactly matching). '
        "No markdown, no preamble, just the JSON object."
    )
    raw = pilot_ask(prompt)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {
            "q": "(LLM produced invalid JSON; click New question to retry)",
            "options": ["retry", "retry", "retry", "retry"],
            "answer": "retry",
        }


while True:
    score_label = f"Score: {score} / {asked}"
    el_emit({
        "type": "column",
        "children": [
            {"type": "text", "value": "🧠 Monty Trivia", "size": 18},
            {"type": "text", "value": score_label, "size": 12},
            {"type": "text", "value": question, "size": 14},
            {"type": "row", "children": [
                {"type": "button", "id": "opt0", "label": options[0]},
                {"type": "button", "id": "opt1", "label": options[1]},
            ]},
            {"type": "row", "children": [
                {"type": "button", "id": "opt2", "label": options[2]},
                {"type": "button", "id": "opt3", "label": options[3]},
            ]},
            {"type": "text", "value": feedback, "size": 12},
            {"type": "button", "id": "next", "label": "New question"},
        ],
    })
    evt = el_recv()
    if evt["type"] == "quit":
        break
    target = evt["target"]
    if target == "next":
        # Emit a thinking-state view before the (blocking) LLM call,
        # otherwise the panel looks frozen while we wait for Ollama.
        el_emit({
            "type": "column",
            "children": [
                {"type": "text", "value": "🧠 Monty Trivia", "size": 18},
                {"type": "text", "value": f"Score: {score} / {asked}", "size": 12},
                {"type": "text", "value": "🤔 Thinking…", "size": 14},
            ],
        })
        q = fetch_question()
        question = q["q"]
        options = q["options"]
        last_correct = q["answer"]
        recent.append(question)
        feedback = ""
    elif target.startswith("opt"):
        idx = int(target[3:])
        picked = options[idx]
        asked = asked + 1
        if picked == last_correct:
            score = score + 1
            feedback = "✅ Correct!"
        else:
            feedback = "❌ Wrong. Answer: " + last_correct

print(f"Final score: {score} / {asked}")
''',
  );
  // HHG examples are canonical demos — always overwrite so updates
  // ship. Don't edit these in the IDE; edit the script constants
  // below and rebuild.
  await vfs.writeFile('examples/06_hhg_dataframe.py', _hhgDataframeScript);
  await vfs.writeFile('examples/07_hhg_duckdb.py', _hhgDuckdbScript);
  await vfs.writeFile(
    'examples/08_hhg_data_pillars.py',
    _hhgDataPillarsScript,
  );
  await vfs.writeFile(
    'examples/09_hhg_duckdb_spatial.py',
    _hhgDuckdbSpatialScript,
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
    svgHostApi: svgHostApi,
  ));
}

/// The main application widget.
class MyApp extends StatelessWidget {
  /// Creates a [MyApp].
  const MyApp({
    required this.vfs,
    required this.controller,
    required this.registry,
    required this.svgHostApi,
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

  /// The host api the SVG preview panel watches for `svg_render(...)`
  /// output.
  final ConsoleSvgHostApi svgHostApi;

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
        svgHostApi: svgHostApi,
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
    required this.svgHostApi,
    super.key,
  });

  /// The VFS instance.
  final MontyVfs vfs;

  /// The Monty IDE controller.
  final MontyIdeController controller;

  /// The widget registry for the bridge.
  final WidgetRegistry registry;

  /// SVG host api for the preview panel.
  final ConsoleSvgHostApi svgHostApi;

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
        svgHostApi: svgHostApi,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Seeded HHG example scripts.
//
// Raw triple-single (r'''...''') strings so single quotes inside the
// Python source don't need escaping. Dart only ends r''' on three
// consecutive ' characters.
// ---------------------------------------------------------------------------

const _hhgDataframeScript = r'''
# HHG: pure dataframe round-trip — no SQL, no SVG, no LLM.
# Builds a frame from row dicts, filters, projects, returns rows.
requires(["df_from_records", "df_filter", "df_select", "df_to_records"])

records = [
    {"name": "Alice",   "city": "NYC",    "age": 25},
    {"name": "Bob",     "city": "London", "age": 30},
    {"name": "Carol",   "city": "Paris",  "age": 41},
    {"name": "Dan",     "city": "NYC",    "age": 17},
    {"name": "Eve",     "city": "London", "age": 22},
]

df = df_from_records(records)
print("Loaded " + str(len(records)) + " records")

nyc = df_filter(df, where={"city": "NYC"})
nyc_count = len(nyc["name"])
print("NYC rows: " + str(nyc_count))

names_and_ages = df_select(nyc, columns=["name", "age"])

# Last expression = the IDE return value.
df_to_records(names_and_ages)
''';

const _hhgDuckdbScript = r'''
# HHG: DuckDB SQL — basic SELECT / aggregations / row-form output.
# (Spatial works on FFI but triggers macOS Gatekeeper for the unsigned
# extension binary; the IDE keeps autoLoadSpatial disabled. Scripts
# that want spatial can call duck_execute("INSTALL spatial") and
# duck_execute("LOAD spatial") themselves and Allow Anyway in
# System Preferences > Privacy & Security on first prompt.)
requires(["duck_execute", "duck_query", "duck_query_records"])

duck_execute("CREATE OR REPLACE TABLE cities (name VARCHAR, country VARCHAR, pop INTEGER)")
duck_execute("""
INSERT INTO cities VALUES
    ('NYC',    'US',  8336000),
    ('LA',     'US',  3990000),
    ('London', 'UK',  9000000),
    ('Paris',  'FR',  2148000),
    ('Tokyo',  'JP', 13960000)
""")
print("Loaded cities table")

# Aggregation — group by country, count + sum.
totals = duck_query("""
SELECT country, count(*) AS n, sum(pop) AS total_pop
FROM cities
GROUP BY country
ORDER BY total_pop DESC
""")
print("Aggregated by country: " + str(totals))

# Row-form output — a top-N query as a list of dicts.
top_three = duck_query_records("""
SELECT name, pop FROM cities
ORDER BY pop DESC
LIMIT 3
""")
print("Top 3 by population: " + str(top_three))

# Last expression = the IDE return value.
top_three
''';

const _hhgDataPillarsScript = r'''
# HHG: all three pillars composed — duckdb + dataframe + svg.
# DuckDB aggregates; dataframe round-trips the columnar wire format;
# we hand-roll a tiny SVG bar chart and svg_render it.
# The IDE's ConsoleSvgHostApi prints a one-line preview to the
# console below — that's the visual confirmation in v1.
requires([
    "duck_execute", "duck_query",
    "df_to_records",
    "svg_render",
])

duck_execute("CREATE OR REPLACE TABLE sales (region VARCHAR, sales INTEGER)")
duck_execute("""
INSERT INTO sales VALUES
    ('W', 10), ('W', 20), ('E', 30), ('E', 40), ('W', 50)
""")
print("Loaded sales table")

totals = duck_query("""
SELECT region, sum(sales) AS total
FROM sales
GROUP BY region
ORDER BY region
""")
print("Totals: " + str(totals))

rows = df_to_records(totals)
print("As records: " + str(rows))

# Hand-roll a tiny SVG bar chart.
regions = totals["region"]
values  = totals["total"]
max_v = max(values)
bar_w = 30
gap = 10
chart_h = 60
chart_w = (bar_w + gap) * len(regions) + gap

bars = ""
labels = ""
i = 0
for r in regions:
    v = values[i]
    h = (v / max_v) * chart_h
    x = gap + i * (bar_w + gap)
    y = chart_h - h
    cx = x + bar_w / 2
    bars = bars + '<rect x="' + str(x) + '" y="' + str(y) + '" width="' + str(bar_w) + '" height="' + str(h) + '" fill="steelblue"/>'
    labels = labels + '<text x="' + str(cx) + '" y="' + str(chart_h + 12) + '" text-anchor="middle" font-size="10">' + r + '</text>'
    labels = labels + '<text x="' + str(cx) + '" y="' + str(chart_h + 24) + '" text-anchor="middle" font-size="9">' + str(v) + '</text>'
    i = i + 1

svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + str(chart_w) + '" height="' + str(chart_h + 30) + '">' + bars + labels + '</svg>'
svg_render(svg)
print("Rendered SVG via SvgExtension; check the line above for the host preview.")

# Last expression = the IDE return value.
{"regions": regions, "values": values}
''';

const _hhgDuckdbSpatialScript = r'''
# HHG: DuckDB-spatial — relationship operations for soliplex-style
# scripts. Spatial joins, point-in-polygon, proximity, nearest-N,
# polygon overlap. The kind of geo work where the script returns
# data and the host UI renders.
#
# First Run on macOS native may pop a Gatekeeper prompt for the
# unsigned spatial.duckdb_extension binary — Allow Anyway in System
# Settings > Privacy & Security and re-run. On Chrome the extension
# is fetched from the duckdb-wasm CDN; no signing, no popup.
requires(["duck_execute", "duck_query"])

duck_execute("INSTALL spatial")
duck_execute("LOAD spatial")
print("Spatial extension loaded")

# Service zones — polygons in WGS84 (made-up boxes around NYC).
duck_execute("""
CREATE OR REPLACE TABLE zones (name VARCHAR, geom GEOMETRY)
""")
duck_execute("""
INSERT INTO zones VALUES
    ('downtown',   ST_GeomFromText('POLYGON((-74.02 40.70, -73.97 40.70, -73.97 40.78, -74.02 40.78, -74.02 40.70))')),
    ('airport',    ST_GeomFromText('POLYGON((-73.79 40.63, -73.76 40.63, -73.76 40.66, -73.79 40.66, -73.79 40.63))')),
    ('industrial', ST_GeomFromText('POLYGON((-74.02 40.65, -73.97 40.65, -73.97 40.69, -74.02 40.69, -74.02 40.65))'))
""")

# A small fleet of vehicles — points.
duck_execute("""
CREATE OR REPLACE TABLE vehicles (plate VARCHAR, geom GEOMETRY)
""")
duck_execute("""
INSERT INTO vehicles VALUES
    ('V-101', ST_Point(-73.99, 40.74)),
    ('V-102', ST_Point(-73.78, 40.65)),
    ('V-103', ST_Point(-74.00, 40.67)),
    ('V-104', ST_Point(-73.95, 40.80)),
    ('V-105', ST_Point(-73.99, 40.75))
""")

# Two pickups waiting for rides.
duck_execute("""
CREATE OR REPLACE TABLE pickups (id VARCHAR, geom GEOMETRY)
""")
duck_execute("""
INSERT INTO pickups VALUES
    ('P-1', ST_Point(-74.00, 40.74)),
    ('P-2', ST_Point(-73.78, 40.65))
""")

# 1. Spatial join — which vehicle is in which zone? (ST_Within)
in_zone = duck_query("""
SELECT v.plate, z.name AS zone
FROM vehicles v
JOIN zones z ON ST_Within(v.geom, z.geom)
ORDER BY v.plate
""")
print("Vehicles in zones: " + str(in_zone))

# 2. Vehicles outside every zone (anti-join via NOT EXISTS).
unzoned = duck_query("""
SELECT v.plate
FROM vehicles v
WHERE NOT EXISTS (
    SELECT 1 FROM zones z WHERE ST_Within(v.geom, z.geom)
)
ORDER BY v.plate
""")
print("Vehicles outside zones: " + str(unzoned))

# 3. Vehicles within 3 km of each pickup. ST_Distance_Sphere returns
# meters between two WGS84 points (great-circle approximation).
nearby = duck_query("""
SELECT
    p.id AS pickup,
    v.plate,
    round(ST_Distance_Sphere(p.geom, v.geom), 0) AS meters
FROM pickups p
JOIN vehicles v ON ST_Distance_Sphere(p.geom, v.geom) < 3000
ORDER BY p.id, meters
""")
print("Within 3 km of each pickup: " + str(nearby))

# 4. Nearest-vehicle per pickup (correlated subquery).
closest = duck_query("""
SELECT
    p.id AS pickup,
    (SELECT v.plate
     FROM vehicles v
     ORDER BY ST_Distance_Sphere(p.geom, v.geom)
     LIMIT 1) AS closest_plate
FROM pickups p
ORDER BY p.id
""")
print("Closest vehicle: " + str(closest))

# 5. Zone topology — pairs that overlap (none in this dataset, but
# the query is the soliplex-style boilerplate for "which areas
# share territory").
overlaps = duck_query("""
SELECT a.name AS zone_a, b.name AS zone_b
FROM zones a
JOIN zones b ON a.name < b.name AND ST_Intersects(a.geom, b.geom)
ORDER BY a.name, b.name
""")
print("Overlapping zone pairs: " + str(overlaps))

# Last expression = the IDE return value. GeoJSON of every vehicle,
# ready for any downstream map renderer (soliplex frontend, future
# hhg_map, anything that consumes GeoJSON FeatureCollections).
duck_query("""
SELECT plate, ST_AsGeoJSON(geom) AS geom_geojson
FROM vehicles
ORDER BY plate
""")
''';
