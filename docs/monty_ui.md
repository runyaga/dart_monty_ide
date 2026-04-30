# Monty UI Panel

The **Monty UI** panel lets a Monty Python script drive a live Flutter
widget tree from inside the IDE — no Dart, no callbacks, no module
imports. The script emits a JSON-shaped tree and pauses; the panel
renders it; user events resume the script.

Open the panel with the `smart_display` icon in the toolbar.

## The pattern

The bridge is `EventLoopExtension` from `dart_monty`. Two host
functions:

| Function | Direction | Description |
|----------|-----------|-------------|
| `el_emit(tree)` | Python → Dart | Push a widget tree (non-blocking). |
| `el_recv()`     | Dart → Python | Pause until the host dispatches an event; returns the event dict. |

The canonical loop:

```python
count = 0

while True:
    el_emit({
        "type": "column",
        "children": [
            {"type": "text", "value": f"Count: {count}"},
            {"type": "button", "id": "inc", "label": "+1"},
        ],
    })
    evt = el_recv()
    if evt["type"] == "quit":
        break
    if evt["target"] == "inc":
        count = count + 1
```

Always handle `evt["type"] == "quit"` so the panel's stop button
ends the loop cleanly. The runtime also unblocks `el_recv` if the
script is killed via the IDE's stop, but explicit handling is nicer.

## Widget vocabulary

The renderer lives in `lib/src/ui/monty_ui_panel.dart`. Each node is a
dict with a `type` key plus its own props.

### Leaves

| Type         | Required        | Optional   | Emits on user action |
|--------------|-----------------|------------|----------------------|
| `text`       | `value`         | `size`     | — |
| `button`     | `id`, `label`   | —          | `{"type": "click",  "target": id}` |
| `slider`     | `id`, `min`, `max`, `value` | `label` | `{"type": "change", "target": id, "value": v}` |
| `checkbox`   | `id`, `value`   | `label`    | `{"type": "change", "target": id, "value": v}` |
| `text_field` | `id`, `value`   | `hint`     | `{"type": "submit", "target": id, "value": v}` (on Enter) |

The panel header's close button emits `{"type": "quit"}`.

### Containers

| Type     | Children                |
|----------|-------------------------|
| `column` | vertical list of nodes  |
| `row`    | horizontal list of nodes |

Containers nest freely.

### Notes / current limits

- `text_field` recreates its `TextEditingController` on each emit, so
  high-frequency re-renders (e.g. while a user is mid-typing **and** a
  slider in the same tree is being dragged) can drop in-progress text.
  Avoid mixing fast-changing widgets with text input until we add
  state-keyed controllers.
- The renderer is synchronous and rebuilds the entire tree on every
  emit. This is fine up to a few hundred nodes; beyond that we'll need
  keyed diffing.
- Sliders dispatch a `change` event on every drag tick.

### `type_check` is safe on event-loop scripts

The toolbar's **Type Check** button (and the assistant's `type_check`
tool) are pure static analysis via `Monty.typeCheck` — no runtime is
spun up and no code is executed. Safe to call on a script that loops
forever on `el_recv`.

To make calls like `el_emit`, `prompt_extend`, `flutter_set_prop`
resolve, the IDE synthesizes a Python preamble at type-check time.
`MontyIdeController.buildHostStubs(extensions)` walks every registered
`MontyExtension` and emits one `def <name>(...) -> ...: ...` line per
host function, mapping `HostParamType` to Python types:

| HostParamType | Python  |
|---------------|---------|
| `string`      | `str`   |
| `integer`     | `int`   |
| `number`      | `float` |
| `boolean`     | `bool`  |
| `list`        | `list`  |
| `map`         | `dict`  |
| `any`         | `object`|

The preamble is passed to `Monty.typeCheck(code, prefixCode: prefix)`
so the type checker sees the stubs but they don't affect runtime.

Return types are not currently expressed in `HostFunctionSchema`, so
the preamble defaults to `-> object` and overrides a small list of
known returns (currently `el_recv -> dict`). When a function's return
type matters for downstream type checks, add it to the
`returnOverrides` map in `buildHostStubs`. (A cleaner long-term fix is
a return-type field on `HostFunctionSchema` upstream.)

### `run_python` blocks on event loops

`run_python` (the assistant's verification tool) calls
`MontyIdeController.execute()` and awaits the script's result.
For a `while True: el_emit/el_recv` loop, the result Future never
resolves and the assistant turn hangs. Until we add a timeout or
teach the assistant to skip `run_python` for event-loop scripts, tell
the AI Pilot in your prompt: *"This is a Monty UI script — do not call
`run_python`; use `write_file` only."*

## Layered system prompt

The AI Pilot's system prompt is composed at runtime by
[`buildSystemPrompt`](../lib/src/assistant/system_prompt_builder.dart)
from four layers:

1. **`defaultAssistantPrompt`** — static rules in
   `lib/src/assistant/default_prompt.dart` (typing rules, tool sequence,
   Monty UI Mode reference).
2. **`## RUNTIME EXTENSIONS`** — every registered `MontyExtension`
   may expose a `systemPromptContext`. `buildSystemPrompt` walks
   `controller.extensions` and appends each non-empty value as a
   bullet. New extensions automatically teach the assistant about
   themselves.
3. **`## RUNTIME API`** — auto-generated from each extension's
   `functions` list via `buildHostApiDocs(extensions)`. One Python-
   shaped signature line per host function with the description as a
   trailing `# comment`. **Single source of truth** for the API: when
   you add a new `HostFunction` it appears here without touching
   `default_prompt.dart`.
4. **`## CURRENT SCRIPT`** — fragments the running script registered
   via `prompt_extend(text)`.

`buildSystemPrompt` is a pure function — easy to inspect, easy to
unit-test. `_buildSystemPrompt` in `monty_ide.dart` is a thin wrapper
that supplies the live extension list and fragment list. The
composition is rebuilt before each assistant turn, so changes take
effect on the next message without restarting.

### `prompt_show()` — Python-side introspection

Scripts can read the currently-synthesized prompt by calling
`prompt_show()` (returns `str`). Useful for debugging what the LLM
will actually see. Wired in `main.dart` via
`promptExtension.snapshotBuilder = () => buildSystemPrompt(...)`.

## `prompt_extend(text)` — per-script briefs

Scripts can register additional context for the assistant by calling
the host function `prompt_extend(text)`. Each call appends a
fragment that appears under a `## CURRENT SCRIPT` heading in the
assistant's system prompt.

```python
prompt_extend(
    "Script: Temperature converter using a Celsius slider (-50..150) "
    "and freeze/body/boil preset buttons. Show °C/°F/K. "
    "Help me iterate on logic, not layout."
)

# ...rest of the script
```

### When fragments fire

The host function is non-blocking and registers immediately, so calling
it at the top of the file means the fragment is captured before the
script enters any blocking `el_recv` loop. By the time the user opens
the chat, the assistant sees the brief.

### Lifecycle

| Event                                        | Effect on fragments |
|----------------------------------------------|---------------------|
| User clicks **Run** (either editor buffer)   | Cleared, then refilled by the script. |
| Assistant runs `run_python` (verification)   | Not cleared — assistant's tool runs accumulate. |
| `clearState()` / Reset Interpreter           | Not cleared (next Run will). |

The "clear on user Run, accumulate on assistant Run" split keeps
things predictable: the user-declared brief survives the assistant's
internal probes, but is wiped when the user starts a fresh script.

### Implementation

| File | Purpose |
|------|---------|
| `lib/src/bridge/prompt_extension.dart` | The `MontyPromptExtension` host function + fragment list. |
| `lib/src/assistant/assistant_controller.dart` | Accepts `systemPromptBuilder`; rebuilds system prompt per turn. |
| `lib/src/ui/monty_ide.dart` (`_buildSystemPrompt`) | Composes default + extensions + script fragments. |
| `lib/src/ui/monty_ide.dart` (`_handleRun`) | Calls `promptExtension.clear()` before each user Run. |

## Examples shipped with the IDE

Seeded into `monty_workspace/examples/` on first launch:

- `04_gui_counter.py` — counter with +/-/reset buttons and a slider.
- `05_gui_temp.py` — temperature converter; demonstrates
  `prompt_extend(...)` at the top.

## Roadmap

- Widget polish: `image`, `dropdown`, `progress`, `dialog`, dividers, padding.
- State-keyed `text_field` controllers (preserve cursor across rebuilds).
- Periodic ticks (Dart-side timer that auto-dispatches `tick` events) for animations.
- Keyed diffing for large lists.
- Bridge into `MontyFlutterExtension` so scripts can mix `el_emit` UI
  with property-bag pokes on existing IDE widgets.
