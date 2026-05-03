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
import 'package:hhg_flchart/hhg_flchart.dart';
import 'package:hhg_flchart_flutter/hhg_flchart_flutter.dart';
import 'package:hhg_geoengine/hhg_geoengine.dart';
import 'package:hhg_map/hhg_map.dart';
import 'package:hhg_map_flutter/hhg_map_flutter.dart';
import 'package:hhg_net/hhg_net.dart';
import 'package:hhg_svg/hhg_svg.dart';
import 'package:hhg_svg_flutter/hhg_svg_flutter.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // libduckdb resolution for macOS pure-Dart-style FFI binding.
  // dart_duckdb 1.4.4 doesn't bundle the dylib on macOS; with Flutter's
  // plugin layer in play this typically just works, but DUCKDB_LIBPATH
  // wins if set, and a known probe path is the fallback.
  if (!kIsWeb && Platform.isMacOS) {
    final lib =
        Platform.environment['DUCKDB_LIBPATH'] ??
        '/tmp/duckdb-spatial-probe/duckdb_lib/libduckdb.dylib';
    if (File(lib).existsSync()) {
      open.overrideFor(OperatingSystem.macOS, lib);
    }
  }

  MontyVfs vfs;
  var weatherDbPath = ':memory:';
  if (kIsWeb) {
    vfs = MemoryMontyVfs();
  } else {
    final appDocsDir = await getApplicationDocumentsDirectory();
    final workspacePath = '${appDocsDir.path}/monty_workspace';
    vfs = LocalMontyVfs(rootPath: workspacePath);
    // Persistent DuckDB for weather grid (survives app restarts).
    weatherDbPath = '${appDocsDir.path}/monty_weather.db';
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
    baseUrl: 'http://localhost:11434',
    model: 'gpt-oss:20b',
    temperature: 0.7,
  );

  late final MontyIdeController controller;

  // FlutterSvgHostApi is the primary SvgHostApi: parses SVG once at
  // render time and exposes a pre-built ScalableImage for the preview
  // panel.  ConsoleSvgHostApi is a side-effect: it writes the raw SVG
  // to a temp file and logs the path to the IDE console.  We chain
  // the two via a ChangeNotifier listener so SvgExtension only sees
  // one host API.
  final svgHostApi = FlutterSvgHostApi();
  final consoleSvg = ConsoleSvgHostApi(
    (line) => controller.appendOutput(line),
  );
  svgHostApi.addListener(() {
    final svg = svgHostApi.latestSvg;
    if (svg != null) {
      // Fire-and-forget: file I/O is a side effect, not a blocker.
      // ignore: discarded_futures
      consoleSvg.render(svg);
    }
  });
  final mapHostApi = FlutterMapHostApi();
  final chartHostApi = FlChartHostApiImpl();

  // Mutable reference to the current DuckDbExtension instance.
  // Updated by extensionsFactory() on each interpreter reset so
  // onForecastLoaded can always find the live connection.
  DuckDbExtension? currentDuckDb;

  mapHostApi.onForecastLoaded = (json, lats, lngs) async {
    final conn = currentDuckDb?.connection;
    if (conn != null) {
      await _storeWeatherGrid(conn, json, lats, lngs);
    }
  };

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
    //
    // weatherDbPath is a persistent file so the weather_grid table
    // survives app restarts and is queryable from Monty scripts.
    final duckDbExt = DuckDbExtension(
      databasePath: weatherDbPath,
      autoLoadSpatial: false,
    );
    currentDuckDb = duckDbExt;
    final svgExt = SvgExtension(hostApi: svgHostApi);
    final mapExt = MapExtension(hostApi: mapHostApi);
    final geoExt = GeoEngineExtension();
    final chartExt = FlChartExtension(hostApi: chartHostApi);
    final netExt = NetExtension();
    final exts = <MontyExtension>[
      flutterExt,
      eventLoopExt,
      promptExt,
      llmExt,
      dataframeExt,
      duckDbExt,
      svgExt,
      mapExt,
      geoExt,
      chartExt,
      netExt,
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
    '''
# Welcome to Monty IDE

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
    'def hi(name: str) -> str:\n'
        '    return f"hello {name}"\n'
        '\n'
        'print(hi("Monty"))\n',
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
        '            {"type": "text", "value": "Monty UI Counter",'
        ' "size": 18},\n'
        '            {"type": "text", "value": f"Count: {count}"},\n'
        '            {"type": "row", "children": [\n'
        '                {"type": "button", "id": "inc", "label": "+1"},\n'
        '                {"type": "button", "id": "dec", "label": "-1"},\n'
        '                {"type": "button", "id": "reset", "label": "Reset"},\n'
        '            ]},\n'
        '            {"type": "slider", "id": "speed", "label": "Set",'
        ' "min": 0, "max": 100, "value": count},\n'
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
        '    "Thermostat: target temperature slider in Celsius'
        ' (range 0..50), "\n'
        '    "Heat / Cool / Off mode buttons, fan-speed slider (1..5),'
        ' and a "\n'
        '    "Step button that advances the simulated room temperature'
        ' toward "\n'
        '    "the target. If the user gives a Fahrenheit value'
        ' (e.g. 103 °F), "\n'
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
    r'''
# REQUIRES OLLAMA: this script calls pilot_ask(...) for narrative.
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
    '''
# REQUIRES OLLAMA: this script generates trivia via pilot_ask(...).
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
  await vfs.writeFile(
    'examples/10_hhg_strict.py',
    _hhgStrictScript,
  );
  await vfs.writeFile('examples/11_hhg_geo_mgrs.py', _hhgGeoMgrsScript);
  await vfs.writeFile('examples/12_hhg_geo_utm.py', _hhgGeoUtmScript);
  await vfs.writeFile('examples/13_hhg_geo_airports.py', _hhgGeoAirportsScript);
  await vfs.writeFile('examples/14_hhg_map_basics.py', _hhgMapBasicsScript);
  await vfs.writeFile('examples/15_hhg_map_aviation.py', _hhgMapAviationScript);
  await vfs.writeFile(
    'examples/16_hhg_duckdb_inspector.py',
    _hhgDuckdbInspectorScript,
  );
  await vfs.writeFile('examples/17_hhg_charts.py', _hhgChartsScript);
  await vfs.writeFile('examples/18_remote_weather.py', _remoteWeatherScript);
  await vfs.writeFile(
    'examples/19_remote_earthquakes.py',
    _remoteEarthquakesScript,
  );
  await vfs.writeFile('examples/20_load_weather.py', _loadWeatherScript);
  await vfs.writeFile('examples/21_load_airports.py', _loadAirportsScript);
  await vfs.writeFile('examples/22_report_weather.py', _reportWeatherScript);
  await vfs.writeFile(
    'examples/23_report_airports.py',
    _reportAirportsScript,
  );
  await vfs.writeFile('examples/24_city_explorer.py', _cityExplorerScript);
  await vfs.writeFile(
    'examples/25_load_weather_grid.py',
    _loadWeatherGridScript,
  );

  final files = await vfs.listFiles();
  var shouldUpdate = !files.contains('system_prompt.txt');
  if (!shouldUpdate) {
    final current = await vfs.readFile('system_prompt.txt');
    if (current.trim() != defaultAssistantPrompt.trim()) {
      shouldUpdate = true;
    }
  }

  if (shouldUpdate) {
    await vfs.writeFile('system_prompt.txt', defaultAssistantPrompt);
  }

  runApp(
    MyApp(
      vfs: vfs,
      controller: controller,
      registry: registry,
      svgHostApi: svgHostApi,
      mapHostApi: mapHostApi,
      chartHostApi: chartHostApi,
    ),
  );
}

/// Writes the Open-Meteo forecast JSON list into a persistent DuckDB
/// `weather_grid` table so Monty scripts can query it.
///
/// Schema: lat, lng, valid_time, temp_c, wind_speed_ms, wind_dir_deg,
/// fetched_at.
Future<void> _storeWeatherGrid(
  Connection conn,
  List<dynamic> json,
  List<double> lats,
  List<double> lngs,
) async {
  try {
    await conn.execute('''
CREATE OR REPLACE TABLE weather_grid (
    lat           DOUBLE,
    lng           DOUBLE,
    valid_time    TIMESTAMP,
    temp_c        DOUBLE,
    wind_speed_ms DOUBLE,
    wind_dir_deg  DOUBLE,
    fetched_at    TIMESTAMP
)
''');
    final appender = await conn.append('weather_grid', null);
    final fetchedAt = DateTime.now().toUtc();
    for (var i = 0; i < json.length; i++) {
      final point = json[i] as Map<String, dynamic>;
      final lat = (point['latitude'] as num).toDouble();
      final lng = (point['longitude'] as num).toDouble();
      final hourly = point['hourly'] as Map<String, dynamic>;
      final times =
          (hourly['time'] as List).cast<String>();
      final temps =
          (hourly['temperature_2m'] as List?)?.cast<Object?>() ?? [];
      final speeds =
          (hourly['wind_speed_10m'] as List?)?.cast<Object?>() ?? [];
      final dirs =
          (hourly['wind_direction_10m'] as List?)?.cast<Object?>() ?? [];
      for (var t = 0; t < times.length; t++) {
        final validTime = DateTime.parse('${times[t]}:00Z').toUtc();
        final temp =
            t < temps.length ? (temps[t] as num?)?.toDouble() : null;
        final speed =
            t < speeds.length ? (speeds[t] as num?)?.toDouble() : null;
        final dir =
            t < dirs.length ? (dirs[t] as num?)?.toDouble() : null;
        appender.append(lat);
        appender.append(lng);
        appender.append(validTime);
        appender.append(temp);
        appender.append(speed);
        appender.append(dir);
        appender.append(fetchedAt);
        appender.endRow();
      }
    }
    appender.flush();
    appender.dispose();
  } on Exception catch (e) {
    debugPrint('[weather_grid] DuckDB store failed: $e');
  }
}

/// The main application widget.
class MyApp extends StatelessWidget {
  /// Creates a [MyApp].
  const MyApp({
    required this.vfs,
    required this.controller,
    required this.registry,
    required this.svgHostApi,
    required this.mapHostApi,
    required this.chartHostApi,
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
  final FlutterSvgHostApi svgHostApi;

  /// The host api the map panel watches for `map_*` calls.
  final FlutterMapHostApi mapHostApi;

  /// The host api the chart panel watches for `chart_*` calls.
  final FlChartHostApiImpl chartHostApi;

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
        mapHostApi: mapHostApi,
        chartHostApi: chartHostApi,
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
    required this.mapHostApi,
    required this.chartHostApi,
    super.key,
  });

  /// The VFS instance.
  final MontyVfs vfs;

  /// The Monty IDE controller.
  final MontyIdeController controller;

  /// The widget registry for the bridge.
  final WidgetRegistry registry;

  /// SVG host api for the preview panel.
  final FlutterSvgHostApi svgHostApi;

  /// Map host api for the map panel.
  final FlutterMapHostApi mapHostApi;

  /// Chart host api for the chart panel.
  final FlChartHostApiImpl chartHostApi;

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
        mapHostApi: mapHostApi,
        chartHostApi: chartHostApi,
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

const _hhgDataframeScript = '''
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

const _hhgDuckdbScript = '''
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

const _hhgDataPillarsScript = '''
# HHG v1 demo: duck_query → df_filter → svg_bar_chart → svg_render
#
# Three Holy Hand Grenades packages composed in ~30 lines of Python.
# Works identically on FFI (native) and WASM (flutter run -d chrome):
#  - duck_query aggregates inline data via DuckDB SQL
#  - df_filter / df_select narrow the columnar frame
#  - svg_bar_chart generates a chart string; svg_render hands it to the host
#
# The host prints the SVG path to the console (native) or a preview (web).
requires([
    "duck_query",
    "df_filter", "df_select",
    "svg_bar_chart", "svg_render",
])

# 1. Pull + aggregate with DuckDB SQL (inline VALUES — no CSV needed).
data = duck_query("""
SELECT
    region,
    product,
    SUM(sales) AS total_sales
FROM (VALUES
    ('West',  'Widgets',  1200),
    ('West',  'Gadgets',   850),
    ('East',  'Widgets',  2100),
    ('East',  'Gadgets',   970),
    ('North', 'Widgets',   780),
    ('North', 'Gadgets',   540),
    ('South', 'Widgets',   990),
    ('South', 'Gadgets',   660)
) AS t(region, product, sales)
GROUP BY region, product
ORDER BY region, total_sales DESC
""")
print("Loaded " + str(len(data["region"])) + " region × product rows")

# 2. Narrow with dataframe verbs — keep only Widgets rows.
widgets = df_filter(data, where={"product": "Widgets"})
chart_df = df_select(widgets, columns=["region", "total_sales"])
print("Widgets rows: " + str(len(chart_df["region"])))

# 3. Render as a bar chart — one call, no SVG string-building required.
chart_svg = svg_bar_chart(
    chart_df["region"],
    chart_df["total_sales"],
    width=500,
    height=320,
    color="#4a90d9",
    title="Widgets Sales by Region",
)

svg_render(chart_svg)
print("Chart rendered. Check the console above for the SVG file path.")

# Last expression = the IDE return value (shown in console).
chart_df
''';

const _hhgDuckdbSpatialScript = '''
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

const _hhgStrictScript = '''
# HHG: strict-mode demo. Toggle the shield icon in the toolbar.
#
# Strict ON:  Run pre-typechecks via Monty.typeCheck against the
#             auto-generated host-function stubs. The deliberately
#             wrong call below — passing a string where df_filter
#             expects a dict — is rejected before the interpreter
#             starts. Console shows a structured type error.
#
# Strict OFF: Same script runs. df_filter's handler eventually
#             throws FormatException at runtime — same bug, but
#             you find out later and the message is less precise.
#
# Strict mode is the contract that makes append-only naming
# trustworthy: signatures change → typecheck catches → no
# silent breakage.
requires(["df_from_records", "df_filter"])

records = [
    {"city": "NYC", "n": 5},
    {"city": "LA",  "n": 3},
    {"city": "NYC", "n": 7},
]
df = df_from_records(records)
print("Loaded " + str(len(records)) + " records")

# Deliberate type error: df_filter's `where` parameter is declared
# `dict` in the auto-generated stub, but we pass a string literal.
# Strict typecheck flags this; without strict, dispatch fails at
# runtime with a less precise error.
df_filter(df, where="this should be a dict")
''';

const _hhgGeoMgrsScript = '''
# HHG: MGRS encode / decode — convert a lat/lng to a military-grid
# reference string and back.
#
# geo_mgrs_encode(lat, lng, precision=5) -> str
#   precision 1 = 10 km grid, 2 = 1 km, 3 = 100 m, 4 = 10 m, 5 = 1 m
#
# geo_mgrs_decode(mgrs) -> {"lat", "lng", "precision"}
#   returns the SW corner of the implied grid square; add half the
#   grid-square size to get the centroid.
#
# Polar regions (|lat| > 84 / lat < -80) raise ValueError.
requires(["geo_mgrs_encode", "geo_mgrs_decode"])

# KJFK airport — JFK, New York
mgrs_1m   = geo_mgrs_encode(40.6398, -73.7789)
mgrs_100m = geo_mgrs_encode(40.6398, -73.7789, precision=3)
mgrs_1km  = geo_mgrs_encode(40.6398, -73.7789, precision=2)
print("KJFK MGRS (1 m):   " + mgrs_1m)
print("KJFK MGRS (100 m): " + mgrs_100m)
print("KJFK MGRS (1 km):  " + mgrs_1km)

# Decode back to SW-corner lat/lng
decoded = geo_mgrs_decode(mgrs_1m)
print("decoded SW corner: " + str(round(decoded["lat"], 6)) + ", " + str(round(decoded["lng"], 6)))

# Centroid: add half a 1 m grid-square (≈ 0.5 / 111 111 degrees)
half_m = 0.5 / 111_111
print("centroid approx:   " + str(round(decoded["lat"] + half_m, 6)) + ", " + str(round(decoded["lng"] + half_m, 6)))

# Lower-case and internal whitespace are both tolerated
decoded2 = geo_mgrs_decode("18t xk 03254 99489")
print("whitespace/lower:  " + str(round(decoded2["lat"], 6)) + ", " + str(round(decoded2["lng"], 6)))
''';

const _hhgGeoUtmScript = '''
# HHG: UTM zone discovery + forward/inverse projection.
#
# geo_utm_zone(lat, lng) -> {"zone", "hemisphere", "epsg"}
#   Includes Norway zone-32V exception and Svalbard 31X/33X/35X/37X.
#
# geo_latlon_to_utm(lat, lng, zone=None) -> {"zone","hemisphere","easting","northing","epsg"}
#   Pass zone to force projection into a specific zone (useful for
#   surveys straddling a zone boundary).
#
# geo_utm_to_latlon(zone, hemisphere, easting, northing) -> {"lat","lng"}
requires(["geo_utm_zone", "geo_latlon_to_utm", "geo_utm_to_latlon"])

# KJFK — zone 18N
z = geo_utm_zone(40.6398, -73.7789)
print("KJFK zone:  " + str(z["zone"]) + z["hemisphere"] + "  EPSG:" + str(z["epsg"]))

utm = geo_latlon_to_utm(40.6398, -73.7789)
print("easting:    " + str(round(utm["easting"], 1)) + " m")
print("northing:   " + str(round(utm["northing"], 1)) + " m")

# Round-trip — should close to < 1e-6 degrees (~11 cm)
pt = geo_utm_to_latlon(utm["zone"], utm["hemisphere"], utm["easting"], utm["northing"])
print("round-trip: " + str(round(pt["lat"], 6)) + ", " + str(round(pt["lng"], 6)))
print("original:   40.6398, -73.7789")

# Force a neighbour zone (zone 19 central meridian = -69°; KJFK is off-centre)
utm19 = geo_latlon_to_utm(40.6398, -73.7789, zone=19)
print("zone 19 forced — easting: " + str(round(utm19["easting"], 1)) + " m  (< 500 000 = west of CM)")

# Southern hemisphere — Sydney
s = geo_latlon_to_utm(-33.8688, 151.2093)
print("Sydney: " + str(s["zone"]) + s["hemisphere"] + "  E=" + str(round(s["easting"])) + "  N=" + str(round(s["northing"])))

# Norway special case — Bergen → zone 32V (not 31V)
no = geo_utm_zone(60.39, 5.32)
print("Bergen: zone " + str(no["zone"]) + no["hemisphere"] + "  EPSG:" + str(no["epsg"]))
''';

const _hhgGeoAirportsScript = '''
# HHG: batch airport → MGRS + UTM zone table.
# Shows geo_mgrs_encode and geo_utm_zone used together across a
# list of well-known ICAO airports from different hemispheres and
# UTM zones (including the Norway exception for Heathrow-adjacent
# Scandinavian routes).
requires(["geo_mgrs_encode", "geo_utm_zone"])

airports = [
    ("KJFK", 40.6398,   -73.7789),   # New York — JFK
    ("EGLL", 51.4775,    -0.4614),   # London — Heathrow
    ("LFPG", 49.0097,     2.5479),   # Paris — CDG
    ("YSSY", -33.9461,  151.1772),   # Sydney — Kingsford Smith
    ("NZAA", -37.0082,  174.7917),   # Auckland
    ("UUEE",  55.9726,   37.4125),   # Moscow — Sheremetyevo
    ("ENGM",  60.1939,   11.1004),   # Oslo — Gardermoen (Norway zone 32V)
    ("ENBR",  60.2934,    5.2186),   # Bergen (Norway zone 32V)
]

print(f"{'ICAO':<6}  {'MGRS (1 m)':<20}  UTM zone  EPSG")
print("-" * 56)
for icao, lat, lng in airports:
    try:
        mgrs = geo_mgrs_encode(lat, lng, precision=5)
        z    = geo_utm_zone(lat, lng)
        print(f"{icao:<6}  {mgrs:<20}  {z['zone']}{z['hemisphere']:<8}  {z['epsg']}")
    except ValueError as e:
        print(f"{icao:<6}  ERROR: {e}")
''';

const _hhgMapBasicsScript = '''
# HHG: map basics — fly to, add markers, polyline, events.
# Open the Monty UI panel (smart_display icon) before running.
# The map auto-mounts in the panel; tap markers to see events.
requires([
    "map_fly_to", "map_set_basemap", "map_clear_markers",
    "map_add_marker", "map_add_polyline",
    "map_fit_bounds_to_markers", "map_recv",
])

map_set_basemap("cartodb_positron")
map_clear_markers()

# Fly to New York
map_fly_to(40.7128, -74.0060, zoom=11, animated=True)

# Drop a few landmarks
jfk  = map_add_marker(40.6398, -73.7789, label="KJFK", color="blue",   icon="local_airport")
lga  = map_add_marker(40.7773, -73.8726, label="KLGA", color="blue",   icon="local_airport")
ewr  = map_add_marker(40.6895, -74.1745, label="KEWR", color="blue",   icon="local_airport")
city = map_add_marker(40.7128, -74.0060, label="NYC",  color="red",    icon="place")

# Connect the airports with a polyline
map_add_polyline(
    [[40.6398, -73.7789], [40.7773, -73.8726], [40.6895, -74.1745]],
    color="#0066cc",
    width=3,
)

map_fit_bounds_to_markers(padding=60)
print("Map ready — tap a marker or wait 10 s for timeout.")

evt = map_recv(timeout_ms=10000)
if evt is None:
    print("No event in 10 s.")
elif evt["type"] == "marker_tapped":
    print(f"Tapped: {evt['marker_id']}")
else:
    print(f"Event: {evt['type']}")
''';

const _hhgMapAviationScript = r'''
# HHG: aviation METAR — DuckDB + map cross-pillar demo.
#
# Composes hhg_duckdb (SQL) with hhg_map (camera + colored markers)
# in one dart_monty script. Color-codes each airport by flight
# category (VFR=green, MVFR=orange, IFR=red, LIFR=purple) and waits
# for a marker tap to print the raw METAR observation.
#
# NOTE: the live AviationWeather.gov API is CORS-blocked when run in
# a browser host (`flutter run -d chrome`). This script ships a
# hardcoded snapshot so it runs identically on macOS (FFI) and
# Chrome (WASM). To switch to live data on a backend that proxies
# CORS, replace the INSERTs with:
#   duck_execute("INSTALL httpfs; LOAD httpfs;")
#   duck_execute("CREATE OR REPLACE TABLE metars AS ... read_json_auto(...)")
# Open the Monty UI panel before running so the map is mounted.
requires([
    "duck_execute", "duck_query_records",
    "map_set_basemap", "map_fly_to", "map_clear_markers",
    "map_add_marker", "map_fit_bounds_to_markers", "map_recv",
])

duck_execute("""
CREATE OR REPLACE TABLE airports (
    icaoId VARCHAR, name VARCHAR, lat DOUBLE, lng DOUBLE
)
""")
duck_execute("""
INSERT INTO airports VALUES
    ('KJFK', 'John F. Kennedy Intl', 40.6413, -73.7781),
    ('KEWR', 'Newark Liberty Intl',  40.6895, -74.1745),
    ('KLGA', 'LaGuardia',            40.7769, -73.8740),
    ('KBOS', 'Boston Logan',         42.3656, -71.0096),
    ('KORD', 'Chicago O''Hare',      41.9742, -87.9073)
""")

duck_execute("""
CREATE OR REPLACE TABLE metars (
    icaoId VARCHAR, fltCat VARCHAR, wspd INTEGER, wdir INTEGER,
    altim DOUBLE, temp DOUBLE, rawOb VARCHAR
)
""")
duck_execute("""
INSERT INTO metars VALUES
    ('KJFK', 'VFR',  10, 220, 30.01, 22.0, 'KJFK 011451Z 22010KT 10SM FEW250 22/14 A3001 RMK AO2 SLP163 T02220139'),
    ('KEWR', 'MVFR', 14, 220, 29.99, 18.0, 'KEWR 011451Z 22014KT 6SM BR BKN012 OVC025 18/16 A2999'),
    ('KLGA', 'VFR',   8, 230, 30.00, 21.0, 'KLGA 011451Z 23008KT 10SM SCT040 21/15 A3000 RMK AO2 SLP159'),
    ('KBOS', 'IFR',  18,  40, 29.87, 14.0, 'KBOS 011454Z 04018KT 2SM -RA BR BKN006 OVC012 14/13 A2987'),
    ('KORD', 'LIFR', 22,  90, 29.78, 18.0, 'KORD 011451Z 09022KT 1/2SM TS BKN004 OVC010 18/17 A2978')
""")

rows = duck_query_records("""
SELECT a.icaoId, a.name, a.lat, a.lng,
       m.fltCat, m.wspd, m.wdir, m.altim, m.temp, m.rawOb
FROM airports a JOIN metars m ON a.icaoId = m.icaoId
ORDER BY a.icaoId
""")
print(f"Loaded {len(rows)} METARs")

map_set_basemap("cartodb_positron")
map_fly_to(40.7128, -74.0060, zoom=6, animated=False)
map_clear_markers()

flt_color = {"VFR": "green", "MVFR": "orange", "IFR": "red", "LIFR": "purple"}

for r in rows:
    color = flt_color.get(r["fltCat"], "grey")
    label = f"{r['icaoId']} {r['fltCat'] or '?'}"
    map_add_marker(
        r["lat"], r["lng"],
        label=label, color=color, icon="local_airport",
    )

map_fit_bounds_to_markers(padding=80)
print("Tap a marker to see its METAR. Waiting 60 s…")

while True:
    evt = map_recv(timeout_ms=60000)
    if evt is None:
        print("Timeout — done.")
        break
    if evt["type"] == "marker_tapped":
        mid = evt["marker_id"]
        match = next((r for r in rows if r["icaoId"] in mid), None)
        if match:
            print(f"\n{match['icaoId']} ({match['name']})")
            print(f"  Flight cat: {match['fltCat']}  Wind: {match['wdir']}° @ {match['wspd']} kt")
            print(f"  Altimeter:  {match['altim']} inHg  Temp: {match['temp']}°C")
            print(f"  Raw METAR:  {match['rawOb']}")
''';

const _hhgDuckdbInspectorScript = r'''
# HHG: DuckDB Inspector — generates a Flutter UI to browse the
# in-memory DuckDB database, listing tables and previewing rows.
#
# Demonstrates composing hhg_duckdb (SQL) with the el_emit / el_recv
# UI loop. No live data needed — works on macOS (FFI) and Chrome
# (WASM) identically. Open the Monty UI panel before running.
prompt_extend(
    "DuckDB Inspector: lists every table in the in-memory database, "
    "lets the user click a table to see its schema and the first 10 "
    "rows. Pure el_emit / el_recv UI — no LLM."
)
requires(["duck_execute", "duck_query_records"])

# Seed a couple of sample tables so there's something to inspect on
# a fresh run. If tables already exist (e.g. from running the
# aviation example first) these CREATE OR REPLACEs reset them.
duck_execute("""
CREATE OR REPLACE TABLE airports (
    icao VARCHAR, name VARCHAR, lat DOUBLE, lng DOUBLE
)
""")
duck_execute("""
INSERT INTO airports VALUES
    ('KJFK', 'John F. Kennedy Intl', 40.6413, -73.7781),
    ('KEWR', 'Newark Liberty Intl',  40.6895, -74.1745),
    ('KLGA', 'LaGuardia',            40.7769, -73.8740)
""")
duck_execute("""
CREATE OR REPLACE TABLE flights (
    carrier VARCHAR, route VARCHAR, monthly_pax INTEGER
)
""")
duck_execute("""
INSERT INTO flights VALUES
    ('AA',     'KJFK→KLAX',  92410),
    ('UA',     'KEWR→KSFO',  78650),
    ('DL',     'KLGA→KATL',  64200),
    ('B6',     'KJFK→KBOS',  41780)
""")

def list_tables():
    rows = duck_query_records(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema='main' ORDER BY table_name"
    )
    return [r["table_name"] for r in rows]

def schema_text(table):
    info = duck_query_records(f"PRAGMA table_info('{table}')")
    if not info:
        return "(no columns)"
    return "\n".join(f"  • {r['name']} : {r['type']}" for r in info)

def preview_text(table, n=10):
    rows = duck_query_records(f'SELECT * FROM "{table}" LIMIT {n}')
    if not rows:
        return "(empty)"
    headers = list(rows[0].keys())
    out = "  " + " | ".join(headers)
    for r in rows:
        out = out + "\n  " + " | ".join(str(r[h]) for h in headers)
    return out

def row_count(table):
    return duck_query_records(f'SELECT count(*) AS n FROM "{table}"')[0]["n"]

selected = None  # currently drilled-into table name

while True:
    if selected is None:
        # ------- Table list view --------------------------------
        tables = list_tables()
        children = [
            {"type": "text", "value": "🦆 DuckDB Inspector", "size": 18},
            {"type": "text",
             "value": f"{len(tables)} table(s) in main schema. "
                      f"Click one to drill in."},
        ]
        for t in tables:
            children.append(
                {"type": "button", "id": f"tbl:{t}", "label": f"📋 {t}"}
            )
        children.append({"type": "row", "children": [
            {"type": "button", "id": "refresh", "label": "🔄 Refresh"},
            {"type": "button", "id": "quit", "label": "Quit"},
        ]})
        el_emit({"type": "column", "children": children})
    else:
        # ------- Table detail view ------------------------------
        try:
            schema = schema_text(selected)
            preview = preview_text(selected)
            count = row_count(selected)
        except Exception as e:
            schema = ""
            preview = f"(error: {e})"
            count = 0
        el_emit({
            "type": "column",
            "children": [
                {"type": "row", "children": [
                    {"type": "button", "id": "back",
                     "label": "← Back to tables"},
                    {"type": "button", "id": "quit", "label": "Quit"},
                ]},
                {"type": "text",
                 "value": f"📋 {selected}  ({count} row(s))",
                 "size": 18},
                {"type": "text", "value": "Schema:"},
                {"type": "text", "value": schema},
                {"type": "text", "value": "Preview (first 10):"},
                {"type": "text", "value": preview},
            ],
        })

    evt = el_recv()
    if evt["type"] == "quit" or evt["target"] == "quit":
        break
    target = evt["target"]
    if target == "back":
        selected = None
    elif target == "refresh":
        pass  # loop re-renders the table list
    elif target.startswith("tbl:"):
        selected = target[4:]

print("DuckDB inspector closed.")
''';

const _remoteWeatherScript = r'''
# HHG: load live weather from Open-Meteo into DuckDB.
#
# Fetches current conditions for 5 global cities in one batch API call,
# inserts into DuckDB, then queries for comparisons.
#
# Works on both FFI (native macOS) and WASM (Flutter web) — Open-Meteo
# has permissive CORS headers so no proxy is needed in the browser.
#
# https://open-meteo.com/en/docs  (free, no API key)
requires(["net_http_get_json", "duck_execute", "duck_query_records"])

cities = [
    ("New York",    40.7128,  -74.0060),
    ("London",      51.5074,   -0.1278),
    ("Tokyo",       35.6762,  139.6503),
    ("Sydney",     -33.8688,  151.2093),
    ("Sao Paulo",  -23.5505,  -46.6333),
]

lats = ",".join(str(lat) for _, lat, _ in cities)
lngs = ",".join(str(lng) for _, _, lng in cities)
url = (
    "https://api.open-meteo.com/v1/forecast"
    f"?latitude={lats}&longitude={lngs}"
    "&current=temperature_2m,wind_speed_10m,precipitation,weather_code"
    "&wind_speed_unit=ms"
    "&timezone=auto"
)

print("Fetching weather from Open-Meteo …")
data = net_http_get_json(url)

# Batch requests return a JSON list; single-location returns a dict.
if not isinstance(data, list):
    data = [data]
print(f"Got {len(data)} city responses")

# ----- Create table -----
duck_execute("""
CREATE OR REPLACE TABLE city_weather (
    city        VARCHAR,
    temp_c      DOUBLE,
    temp_f      DOUBLE,
    wind_ms     DOUBLE,
    precip_mm   DOUBLE,
    wmo_code    INTEGER
)
""")

def esc(s):
    return str(s).replace("'", "''")

for i, entry in enumerate(data):
    name = cities[i][0]
    cur  = entry.get("current") or {}
    t    = cur.get("temperature_2m") or 0.0
    w    = cur.get("wind_speed_10m") or 0.0
    p    = cur.get("precipitation") or 0.0
    code = cur.get("weather_code") or 0
    tf   = round(t * 9 / 5 + 32, 1)
    duck_execute(
        f"INSERT INTO city_weather VALUES "
        f"('{esc(name)}', {t}, {tf}, {w}, {p}, {code})"
    )

# ----- Analysis -----
rows = duck_query_records("""
SELECT
    city,
    temp_c,
    temp_f,
    wind_ms,
    precip_mm,
    CASE
        WHEN wmo_code = 0              THEN 'Clear'
        WHEN wmo_code BETWEEN 1 AND 3  THEN 'Partly cloudy'
        WHEN wmo_code BETWEEN 45 AND 48 THEN 'Fog'
        WHEN wmo_code BETWEEN 51 AND 67 THEN 'Rain/drizzle'
        WHEN wmo_code BETWEEN 71 AND 77 THEN 'Snow'
        WHEN wmo_code BETWEEN 80 AND 82 THEN 'Rain showers'
        WHEN wmo_code BETWEEN 95 AND 99 THEN 'Thunderstorm'
        ELSE 'Other (' || wmo_code || ')'
    END AS conditions
FROM city_weather
ORDER BY temp_c DESC
""")

print(f"\n{'City':<12}  {'°C':>5}  {'°F':>6}  {'m/s':>5}  Conditions")
print("-" * 55)
for r in rows:
    print(
        f"{r['city']:<12}  {r['temp_c']:>5.1f}  "
        f"{r['temp_f']:>6.1f}  {r['wind_ms']:>5.1f}  {r['conditions']}"
    )

# Return the table for the IDE console.
duck_query_records("SELECT * FROM city_weather ORDER BY temp_c DESC")
''';

const _remoteEarthquakesScript = r'''
# HHG: load USGS earthquake feed into DuckDB for SQL analysis.
#
# Fetches the last 24 h of earthquakes worldwide as GeoJSON, inserts
# into DuckDB, then runs several queries:  magnitude distribution,
# depth vs magnitude correlation, top-5 strongest events.
#
# Works on both FFI (native) and WASM (Flutter web) — the USGS feed
# has open CORS headers. Up to 500 events are loaded (the feed
# typically has 200-400 per day).
#
# https://earthquake.usgs.gov/earthquakes/feed/v1.0/geojson.php
requires(["net_http_get_json", "duck_execute", "duck_query_records"])

URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson"

print("Fetching USGS earthquake feed …")
data = net_http_get_json(URL)
features = data.get("features") or []
print(f"Feed contains {len(features)} events")

# Limit to first 500 so the insert stays snappy on WASM.
features = features[:500]

duck_execute("""
CREATE OR REPLACE TABLE earthquakes (
    id      VARCHAR,
    place   VARCHAR,
    mag     DOUBLE,
    depth   DOUBLE,
    lat     DOUBLE,
    lng     DOUBLE,
    time_ms BIGINT
)
""")

def esc(s):
    return str(s).replace("'", "''")

values = []
for f in features:
    props = f.get("properties") or {}
    coords = (f.get("geometry") or {}).get("coordinates") or [0, 0, 0]
    values.append(
        f"('{esc(f.get('id',''))}', "
        f"'{esc(props.get('place','Unknown'))}', "
        f"{props.get('mag') or 0.0}, "
        f"{coords[2]}, "
        f"{coords[1]}, "
        f"{coords[0]}, "
        f"{props.get('time') or 0})"
    )

if values:
    duck_execute("INSERT INTO earthquakes VALUES " + ", ".join(values))

n_loaded = duck_query_records("SELECT count(*) AS n FROM earthquakes")[0]["n"]
print(f"Loaded {n_loaded} earthquakes into DuckDB\n")

# ----- Magnitude distribution -----
buckets = duck_query_records("""
SELECT
    CASE
        WHEN mag < 2   THEN '< 2.0  micro'
        WHEN mag < 3   THEN '2–3    minor'
        WHEN mag < 4   THEN '3–4    light'
        WHEN mag < 5   THEN '4–5    moderate'
        ELSE               '5+     strong'
    END AS category,
    count(*)          AS n,
    round(avg(mag),2) AS avg_mag,
    round(max(mag),1) AS max_mag
FROM earthquakes
GROUP BY category
ORDER BY max_mag
""")

print("Magnitude distribution:")
for r in buckets:
    bar = "#" * int(r["n"] / 5 + 0.5)
    print(f"  {r['category']:<20}  n={r['n']:>4}  avg={r['avg_mag']}  max={r['max_mag']}  {bar}")

# ----- Depth buckets -----
depths = duck_query_records("""
SELECT
    CASE
        WHEN depth <  70 THEN 'shallow (< 70 km)'
        WHEN depth < 300 THEN 'intermediate (70–300 km)'
        ELSE                  'deep (> 300 km)'
    END AS depth_class,
    count(*)          AS n,
    round(avg(mag),2) AS avg_mag
FROM earthquakes
GROUP BY depth_class
ORDER BY avg_mag
""")

print("\nDepth class vs average magnitude:")
for r in depths:
    print(f"  {r['depth_class']:<26}  n={r['n']:>4}  avg_mag={r['avg_mag']}")

# ----- Top 5 -----
top5 = duck_query_records("""
SELECT place, mag, depth
FROM earthquakes
ORDER BY mag DESC
LIMIT 5
""")

print("\nTop 5 strongest:")
for r in top5:
    print(f"  M{r['mag']:4.1f}  depth {r['depth']:>6.1f} km  {r['place']}")

# Return top events for the IDE console.
top5
''';

const _hhgChartsScript = '''
# HHG: interactive fl_chart demo — bar, line, pie, scatter, radar.
# Open the Monty UI panel (toolbar "smart_display" icon) before running.
# Each chart_* call immediately updates the panel; chart_clear resets.
requires(["chart_bar", "chart_line", "chart_pie",
          "chart_scatter", "chart_radar", "chart_clear"])

months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
sales  = [42, 58, 35, 71, 89, 63]

# --- Bar chart ---
chart_bar(
    x=months,
    y=sales,
    title="Monthly Sales",
    ylabel="Units",
    color="#4A90D9",
)
print("Bar chart rendered. Sleeping 3s …")
import time; time.sleep(3)

# --- Line chart (two series) ---
target = [50, 55, 60, 65, 70, 75]
chart_line(
    x=months,
    y=sales,
    title="Sales vs Target",
    ylabel="Units",
    color="#E44D3A",
    series=[{"x": months, "y": target, "label": "Target", "color": "#4CAF50"}],
)
print("Line chart rendered. Sleeping 3s …")
time.sleep(3)

# --- Pie chart ---
chart_pie(
    labels=["Widgets", "Gadgets", "Doohickeys", "Thingamajigs"],
    values=[35, 25, 20, 20],
    title="Product Mix",
)
print("Pie chart rendered. Sleeping 3s …")
time.sleep(3)

# --- Scatter plot ---
import random
random.seed(42)
xs = [random.uniform(0, 10) for _ in range(40)]
ys = [x * 1.5 + random.gauss(0, 1) for x in xs]
chart_scatter(
    x=xs,
    y=ys,
    title="Scatter: y ≈ 1.5x + noise",
    xlabel="x",
    ylabel="y",
    color="#9C27B0",
)
print("Scatter plot rendered. Sleeping 3s …")
time.sleep(3)

# --- Radar chart ---
chart_radar(
    labels=["Speed", "Power", "Range", "Accuracy", "Stealth"],
    values=[80, 65, 90, 75, 55],
    title="Unit Stats",
    color="#FF9800",
)
print("Radar chart rendered. Done.")
''';

// ── Load scripts ─────────────────────────────────────────────────────────────

const _loadWeatherScript = r'''
# HHG: Load current weather + 7-day daily forecast for 10 cities into DuckDB.
# Tables: city_weather (current), city_forecast (daily).
# Run once per session; data persists until Reset Interpreter.
# Then run 22_report_weather.py to visualize.
requires(["net_http_get_json", "duck_execute", "duck_query"])

cities = [
    ("New York",     40.7128,  -74.0060),
    ("London",       51.5074,   -0.1278),
    ("Tokyo",        35.6762,  139.6503),
    ("Sydney",      -33.8688,  151.2093),
    ("Paris",        48.8566,    2.3522),
    ("Dubai",        25.2048,   55.2708),
    ("Singapore",     1.3521,  103.8198),
    ("Chicago",      41.8781,  -87.6298),
    ("Houston",      29.7604,  -95.3698),
    ("Los Angeles",  34.0522, -118.2437),
]

lats = ",".join(str(c[1]) for c in cities)
lngs = ",".join(str(c[2]) for c in cities)
url = (
    "https://api.open-meteo.com/v1/forecast"
    f"?latitude={lats}&longitude={lngs}"
    "&current_weather=true"
    "&daily=temperature_2m_max,temperature_2m_min,wind_speed_10m_max"
    "&timezone=UTC&forecast_days=7"
)

print("Fetching weather from Open-Meteo …")
raw = net_http_get_json(url)
items = raw if isinstance(raw, list) else [raw]

duck_execute("DROP TABLE IF EXISTS city_weather")
duck_execute("""
    CREATE TABLE city_weather (
        city      TEXT,
        lat       DOUBLE,
        lng       DOUBLE,
        temp_c    DOUBLE,
        wind_kph  DOUBLE,
        wind_dir  INT,
        wmo_code  INT
    )
""")

cur_rows = []
for i, info in enumerate(cities):
    name, lat, lng = info
    if i >= len(items):
        continue
    cw = items[i].get("current_weather") or {}
    t = float(cw.get("temperature") or 0)
    w = float(cw.get("windspeed") or 0)
    wd = int(cw.get("winddirection") or 0)
    code = int(cw.get("weathercode") or 0)
    n = name.replace("'", "''")
    cur_rows.append(f"('{n}', {lat}, {lng}, {t}, {w}, {wd}, {code})")

if cur_rows:
    duck_execute(f"INSERT INTO city_weather VALUES {', '.join(cur_rows)}")

duck_execute("DROP TABLE IF EXISTS city_forecast")
duck_execute("""
    CREATE TABLE city_forecast (
        city         TEXT,
        date         TEXT,
        max_temp_c   DOUBLE,
        min_temp_c   DOUBLE,
        wind_max_kph DOUBLE
    )
""")

fc_rows = []
for i, info in enumerate(cities):
    name, lat, lng = info
    if i >= len(items):
        continue
    daily = items[i].get("daily") or {}
    dates = daily.get("time") or []
    max_t = daily.get("temperature_2m_max") or []
    min_t = daily.get("temperature_2m_min") or []
    wind_max = daily.get("wind_speed_10m_max") or []
    n = name.replace("'", "''")
    for j, d in enumerate(dates):
        mx = float(max_t[j]) if j < len(max_t) else 0.0
        mn = float(min_t[j]) if j < len(min_t) else 0.0
        wm = float(wind_max[j]) if j < len(wind_max) else 0.0
        fc_rows.append(f"('{n}', '{d}', {mx}, {mn}, {wm})")

if fc_rows:
    duck_execute(f"INSERT INTO city_forecast VALUES {', '.join(fc_rows)}")

cw_count = duck_query("SELECT COUNT(*) AS n FROM city_weather")
fc_count = duck_query("SELECT COUNT(*) AS n FROM city_forecast")
print(f"city_weather: {cw_count['n'][0]} rows")
print(f"city_forecast: {fc_count['n'][0]} rows (7-day daily × 10 cities)")
print("Done. Run 22_report_weather.py to visualize.")
''';

const _loadAirportsScript = r'''
# HHG: Load METAR weather for major US airports into DuckDB.
# Table: airport_metar (ident, lat, lng, temp_c, dewpoint_c,
#   wind_dir, wind_speed_kt, visibility_sm, flight_category, raw_metar).
# Uses aviationweather.gov public JSON API.
# Then run 23_report_airports.py to visualize.
requires(["net_http_get_json", "duck_execute", "duck_query"])

AIRPORTS = ",".join([
    "KJFK", "KLAX", "KORD", "KDFW", "KATL",
    "KSFO", "KDEN", "KPHX", "KLAS", "KSEA",
    "KMIA", "KBOS", "KEWR", "KIAH", "KDTW",
    "KMSP", "KPHL", "KSTL", "KCLT", "KSLC",
])

url = f"https://aviationweather.gov/api/data/metar?ids={AIRPORTS}&format=json&hours=2"
print("Fetching METARs from aviationweather.gov …")
data = net_http_get_json(url)

duck_execute("DROP TABLE IF EXISTS airport_metar")
duck_execute("""
    CREATE TABLE airport_metar (
        ident           TEXT,
        lat             DOUBLE,
        lng             DOUBLE,
        temp_c          DOUBLE,
        dewpoint_c      DOUBLE,
        wind_dir        INT,
        wind_speed_kt   INT,
        visibility_sm   DOUBLE,
        flight_category TEXT,
        raw_metar       TEXT
    )
""")

rows = []
seen = []
for obs in data:
    ident = obs.get("icaoId") or obs.get("stationId") or ""
    if not ident or ident in seen:
        continue
    seen.append(ident)
    lat = float(obs.get("lat") or 0)
    lng = float(obs.get("lon") or 0)
    temp = float(obs.get("temp") or 0)
    dew = float(obs.get("dewp") or 0)
    wdir = int(obs.get("wdir") or 0)
    wspd = int(obs.get("wspd") or 0)
    visib = float(obs.get("visib") or 10)
    cat = (obs.get("fltcat") or obs.get("flightCategory") or "VFR").replace("'", "''")
    raw = (obs.get("rawOb") or "").replace("'", "''")[:200]
    rows.append(
        f"('{ident}', {lat}, {lng}, {temp}, {dew}, {wdir}, {wspd}, {visib}, '{cat}', '{raw}')"
    )

if rows:
    duck_execute(f"INSERT INTO airport_metar VALUES {', '.join(rows)}")

count = duck_query("SELECT COUNT(*) AS n FROM airport_metar")
print(f"airport_metar: {count['n'][0]} rows")
print("Done. Run 23_report_airports.py to visualize.")
''';

// ── Report scripts ────────────────────────────────────────────────────────────

const _reportWeatherScript = r'''
# HHG: Visualize city_weather + city_forecast from DuckDB.
# Shows: temp bar chart, 7-day forecast line chart, temperature map.
# Run 20_load_weather.py first to populate the tables.
requires(["duck_query", "duck_query_records", "chart_bar", "chart_line",
          "map_add_marker", "map_clear_markers", "map_fit_bounds_to_markers"])

try:
    count = duck_query("SELECT COUNT(*) AS n FROM city_weather")
    n = count["n"][0]
except Exception:
    print("No data — run 20_load_weather.py first.")
    n = 0

if n == 0:
    print("No data — run 20_load_weather.py first.")
else:
    cur = duck_query("SELECT city, temp_c, wind_kph FROM city_weather ORDER BY temp_c DESC")
    chart_bar(
        cur["city"], cur["temp_c"],
        title="Current Temperature by City",
        xlabel="City", ylabel="°C", color="#E53935",
    )

    cities_q = duck_query_records("SELECT DISTINCT city FROM city_forecast ORDER BY city")
    series = []
    for row in cities_q:
        city = row["city"]
        fc = duck_query(
            f"SELECT date, max_temp_c FROM city_forecast WHERE city = '{city}' ORDER BY date"
        )
        series.append({"x": fc["date"], "y": fc["max_temp_c"], "label": city})
    chart_line(
        x=[], y=[],
        title="7-Day Max Temperature Forecast (°C)",
        xlabel="Date", ylabel="°C", color="",
        series=series,
    )

    map_clear_markers()
    locs = duck_query_records("SELECT city, lat, lng, temp_c FROM city_weather")
    for r in locs:
        t = r["temp_c"]
        color = "red" if t > 28 else ("orange" if t > 15 else ("blue" if t < 5 else "green"))
        map_add_marker(
            r["lat"], r["lng"],
            label=f"{r['city']} {t}°C",
            color=color, icon="thermostat",
        )
    map_fit_bounds_to_markers(60)

    print(f"Visualized {n} cities. Hottest: {cur['city'][0]} at {cur['temp_c'][0]}°C.")
''';

const _reportAirportsScript = r'''
# HHG: Visualize airport_metar from DuckDB — map + wind/category charts.
# VFR=green, MVFR=blue, IFR=red, LIFR=purple.
# Run 21_load_airports.py first.
requires(["duck_query", "duck_query_records", "chart_bar",
          "map_fly_to", "map_add_marker", "map_clear_markers", "map_fit_bounds_to_markers"])

try:
    count = duck_query("SELECT COUNT(*) AS n FROM airport_metar")
    n = count["n"][0]
except Exception:
    print("No data — run 21_load_airports.py first.")
    n = 0

if n == 0:
    print("No data — run 21_load_airports.py first.")
else:
    cats = duck_query("""
        SELECT flight_category AS cat, COUNT(*) AS cnt
        FROM airport_metar GROUP BY flight_category ORDER BY cnt DESC
    """)
    chart_bar(
        cats["cat"], cats["cnt"],
        title="Airports by Flight Category",
        xlabel="Category", ylabel="Count", color="#1976D2",
    )

    wind = duck_query(
        "SELECT ident, wind_speed_kt FROM airport_metar ORDER BY wind_speed_kt DESC"
    )
    chart_bar(
        wind["ident"], wind["wind_speed_kt"],
        title="Wind Speed by Airport",
        xlabel="Airport", ylabel="Knots", color="#039BE5",
    )

    map_fly_to(39.5, -98.35, zoom=4, animated=True)
    map_clear_markers()
    airports = duck_query_records(
        "SELECT ident, lat, lng, temp_c, wind_speed_kt, flight_category FROM airport_metar"
    )
    for ap in airports:
        cat = ap["flight_category"]
        color = (
            "green" if cat == "VFR" else
            "blue" if cat == "MVFR" else
            "red" if cat == "IFR" else
            "purple"
        )
        map_add_marker(
            ap["lat"], ap["lng"],
            label=f"{ap['ident']} {cat} {ap['temp_c']}°C {ap['wind_speed_kt']}kt",
            color=color, icon="flight",
        )
    map_fit_bounds_to_markers(40)
    print(f"Mapped {n} airports.")
''';

const _cityExplorerScript = r'''
# HHG: Interactive city explorer — tap a marker to see live weather + facts.
# Drops 10 major US cities, listens for marker_tapped via map_recv,
# and shows a live-weather detail card in the UI panel via el_emit.
requires(["map_fly_to", "map_add_marker", "map_fit_bounds_to_markers",
          "map_recv", "el_emit", "net_http_get_json"])

CITIES = [
    {"name": "New York",     "state": "NY", "lat": 40.7128, "lng": -74.0060,  "pop": "8.3M", "note": "The Big Apple"},
    {"name": "Los Angeles",  "state": "CA", "lat": 34.0522, "lng": -118.2437, "pop": "3.9M", "note": "City of Angels"},
    {"name": "Chicago",      "state": "IL", "lat": 41.8781, "lng": -87.6298,  "pop": "2.7M", "note": "The Windy City"},
    {"name": "Houston",      "state": "TX", "lat": 29.7604, "lng": -95.3698,  "pop": "2.3M", "note": "Space City"},
    {"name": "Phoenix",      "state": "AZ", "lat": 33.4484, "lng": -112.0740, "pop": "1.6M", "note": "Valley of the Sun"},
    {"name": "Philadelphia", "state": "PA", "lat": 39.9526, "lng": -75.1652,  "pop": "1.6M", "note": "City of Brotherly Love"},
    {"name": "Seattle",      "state": "WA", "lat": 47.6062, "lng": -122.3321, "pop": "0.7M", "note": "Emerald City"},
    {"name": "Dallas",       "state": "TX", "lat": 32.7767, "lng": -96.7970,  "pop": "1.3M", "note": "Big D"},
    {"name": "Miami",        "state": "FL", "lat": 25.7617, "lng": -80.1918,  "pop": "0.5M", "note": "Magic City"},
    {"name": "Denver",       "state": "CO", "lat": 39.7392, "lng": -104.9903, "pop": "0.7M", "note": "Mile High City"},
]

def weather_desc(code):
    if code is None: return "—"
    if code == 0:    return "Clear sky"
    if code <= 3:    return "Partly cloudy"
    if code <= 48:   return "Foggy"
    if code <= 67:   return "Rainy"
    if code <= 77:   return "Snowy"
    if code <= 82:   return "Showers"
    return "Stormy"

def fetch_weather(lat, lng):
    url = (
        "https://api.open-meteo.com/v1/forecast"
        f"?latitude={lat}&longitude={lng}"
        "&current=temperature_2m,wind_speed_10m,weather_code"
        "&wind_speed_unit=mph&forecast_days=1"
    )
    try:
        cur = net_http_get_json(url)["current"]
        return cur["temperature_2m"], cur["wind_speed_10m"], cur["weather_code"]
    except Exception:
        return None, None, None

def show_idle():
    el_emit({
        "type": "column",
        "children": [
            {"type": "text", "value": "City Explorer", "size": 18},
            {"type": "text", "value": "Tap any city marker to see\nlive weather and city facts.", "size": 13},
        ],
    })

def show_detail(city):
    temp, wind, code = fetch_weather(city["lat"], city["lng"])
    temp_str = f"{temp:.1f} °C" if temp is not None else "—"
    wind_str = f"{wind:.0f} mph" if wind is not None else "—"
    el_emit({
        "type": "column",
        "children": [
            {"type": "text", "value": f"{city['name']}, {city['state']}", "size": 20},
            {"type": "text", "value": city["note"]},
            {"type": "text", "value": f"Population: {city['pop']}"},
            {"type": "text", "value": f"Weather: {weather_desc(code)}"},
            {"type": "text", "value": f"Temperature: {temp_str}"},
            {"type": "text", "value": f"Wind: {wind_str}"},
        ],
    })
    print(f"Tapped {city['name']}: {temp_str}, {wind_str}, {weather_desc(code)}")

# --- drop all markers ---
marker_map = {}
for c in CITIES:
    mid = map_add_marker(
        c["lat"], c["lng"],
        label=c["name"],
        icon="place",
        color="blue",
        drop_animation=True,
    )
    marker_map[mid] = c

map_fit_bounds_to_markers(60)
show_idle()
print("Tap any city marker. Script runs for 5 minutes.")

# --- event loop ---
while True:
    evt = map_recv(timeout_ms=300000)
    if evt is None:
        print("Timed out — re-run to continue.")
        break
    t = evt["type"]
    if t == "marker_tapped":
        city = marker_map.get(evt["marker_id"])
        if city:
            map_fly_to(city["lat"], city["lng"], zoom=10, animated=True)
            show_detail(city)
    elif t == "map_tapped":
        show_idle()
''';

const _loadWeatherGridScript = '''
# HHG: Fetch a 3-day global weather forecast and store it in DuckDB.
#
# Calling map_load_forecast():
#   - Downloads hourly temp + wind data from Open-Meteo for a 6x8 global grid
#   - Injects it into the live Temperature and Wind map layers immediately
#   - Writes a weather_grid table to the persistent DuckDB database so
#     you can query it from any script (survives app restarts)
#
# After running this script:
#   map_set_weather_layer("temperature", enabled=True)
#   map_set_weather_layer("wind", enabled=True)
# ...to see the real data on the map.
import json

result = map_load_forecast(hours=72)
print(json.dumps(result))

if result.get("ok"):
    pts: int = result["points"]
    hrs: int = result["hours"]
    at: str = result["fetched_at"]
    print(f"Loaded {pts}-point grid, {hrs}h window, fetched at {at}")
    print("weather_grid is now queryable from DuckDB.")
else:
    print("Fetch failed:", result.get("error", "unknown error"))
''';

