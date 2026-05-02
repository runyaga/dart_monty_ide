# Holy Hand Grenades — `dart_monty` extension ecosystem v1 plan

**Status:** draft for review
**Audience:** dart_monty maintainers, prospective extension authors, host-app developers, soliplex
**Authors:** runyaga (with Claude)

---

## Narrative

`dart_monty` embeds a sandboxed Python interpreter (Pydantic's Monty,
written in Rust) inside Dart and Flutter apps. The pitch is simple: LLMs
write excellent Python; let them script your app in Python you can
sandbox, type-check, and resource-limit, instead of inventing your own
DSL or shipping unrestricted `eval`.

Today, every consumer of `dart_monty` hardcodes its list of *extensions*
— Dart classes that expose Dart functions to Python — at build time.
The Monty IDE wires `flutter`, `eventloop`, `prompt`, and `llm`
extensions in `main.dart`. Soliplex will eventually wire its own. There
is no path for a third party to write a `dataframe` extension and have
anyone else use it without rebuilding everything.

This plan changes that. It establishes:

- a short set of **conventions** every extension package follows;
- a new **adapter package, `dart_monty_hhg`**, that supplies the
  type-check and capability-check mechanism *without* modifying
  `dart_monty` itself;
- a one-line **capability check** that scripts put at the top to fail
  fast when a host doesn't have what they need;
- three pillar **extension packages** (dataframes, SQL, SVG rendering)
  that prove the conventions work and give the community something to
  copy.

The ecosystem brand is **Holy Hand Grenades**. The package prefix is
**`hhg_*`**. It's a Monty Python reference, on-theme, and the lore
("…and Saint Attila raised the holy hand grenade up on high…") writes
itself for the docs.

The success metric is *not* "soliplex uses `dart_monty`." Soliplex is
one downstream consumer, a month away, and testing through its plumbing
is expensive. The success metric is **"third parties write extensions
without us."** Three pillar packages in roughly a month is the target —
enough to pressure-test the contract under real load, far enough away
from soliplex's specifics that the broader Dart community can use the
result.

Three scope decisions are already made:

1. **`dart_monty` is untouched in v1.** All HHG mechanism — type-check
   gating, capability checks, prefix-code generation, return-type
   metadata — lives in a new `dart_monty_hhg` adapter package that
   depends on `dart_monty`. If we hit something genuinely impossible to
   implement externally, we revisit. Until then the core stays clean
   and HHG iterates without gating dart_monty's release cadence.
2. **Type-checking is opt-in.** `Hhg.run(runtime, code, strict: true)`
   gates execution on `Monty.typeCheck` passing. Default is permissive;
   untyped Python remains valid Python. Forcing every script through
   type-check would conflict with the prototype-friendly culture the
   IDE already has.
3. **The capability check is a name-existence check, not a version
   check.** `requires(["name1", "name2"])` confirms the named host
   functions are registered. Package-version assertion (the mobile-
   fleet scenario) is **out of v1** — the mechanism is sketched in the
   Future Work appendix and is purely additive when we need it. v1
   relies on append-only naming + the fact that pillars are brand
   new (no breaking changes to protect against yet).

Beyond those: append-only function names; flat global namespace
(Monty has no module system); a three-layer pattern for UI-dependent
extensions so the same extension can plug into a Flutter app, a
headless test, or a CLI by swapping host implementations.

The rest of this document is: user stories first, then the
implementation specification.

---

## User stories

### As an extension author…

- I can publish a `hhg_<thing>` package on pub.dev that exposes a
  `MontyExtension` subclass and have any `dart_monty` host pick it up by
  adding a single dependency.
- I declare my function signatures (params + return types) **once**, and
  that single declaration drives runtime validation, static analysis,
  JSON-Schema export for tool catalogs, and LLM tool-exposure surfaces.
- If my extension produces visual output, I split across three packages
  (pure-Dart extension, abstract host API, reference Flutter renderer)
  so non-Flutter consumers can plug in their own renderer.
- I can ship breaking changes by adding a new function with a `_v2`
  suffix. The old name keeps working forever; consumers migrate by
  changing one identifier.
- I can rely on the contract holding across both FFI and WASM backends,
  because every pillar already ships on both and CI tests both.
- I follow one written rules document
  (`dart_monty/docs/extensions/conventions.md`) and that's enough to
  publish a compliant package.

### As a script author…

- I add `requires(["df_filter", "duck_query"])` at the top of my script
  and get a clear error **before anything runs** if the host is missing
  any of those functions by name.
- When I run via `Hhg.run(..., strict: true)`, my script's
  host-function calls are type-checked statically — wrong arg types
  fail with line- and column-precise errors, not runtime exceptions
  buried mid-execution.
- When I prototype quickly I use the permissive default and get
  today's behaviour.
- I rely on append-only naming: a script that worked last year still
  works today, even if the extension authored a `df_filter_v2` since.
- I read schemas from `runtime.exposedSchemas` (or the catalog `.md`
  per package) to discover what's available.

**Known v1 limitation:** version-level mismatches (script written
against `hhg_dataframe@2`, runtime has `@1`) are *not* caught by
`requires(...)` — it only checks names. The mobile-fleet
forward-incompat scenario is documented in Future Work. v1 ships
without it because no breaking changes have happened yet (the pillars
are brand new). Versioning becomes Phase 2, after the trio lands and
we have real composition data.

### As a host-app developer (IDE, soliplex-frontend, a custom Flutter app)…

- I add `dart_monty_hhg` and the desired `hhg_*` pillar packages to my
  pubspec, instantiate the extensions in my factory, and they're
  available to my Python scripts with no further plumbing.
- For UI-dependent extensions, I implement the abstract `*HostApi`
  interface to bind the extension's output to my actual rendering
  surface (Flutter widgets, browser DOM, terminal, file dump).
- I can curate which functions my users see by composing extensions
  across multiple `hhg_*` packages, without forking any of them.
- I call `Hhg.run(runtime, code, strict: true)` instead of
  `runtime.execute(code)` when I want type-check enforcement; otherwise
  I keep using `runtime.execute(...)` directly.
- The IDE's existing Type Check button continues to work unchanged —
  it stays a manual affordance, separate from `strict`.

### As the `dart_monty` maintainer…

- **I do nothing for v1.** `dart_monty` accrues no new API surface.
  All HHG mechanism lives in `dart_monty_hhg`, which depends on
  `dart_monty`. If HHG patterns prove themselves, I can promote the
  proven mechanism into `dart_monty` later (pure upstreaming, no
  redesign). Promoting is easy; un-promoting is painful.
- The existing IDE-side `buildHostStubs` shim stays in the IDE for
  non-HHG extensions; HHG-aware code paths use `dart_monty_hhg`'s
  richer prefix-code generator (which understands the new
  return-type metadata).
- I trust the existing `Monty.typeCheck(prefixCode: ...)` API in
  `dart_monty_core`. My job in v1 is to *not* break it.

### As an AI / LLM Pilot consuming `dart_monty`…

- I introspect the runtime via `runtime.exposedSchemas` and get accurate
  parameter and return types per host function — including for
  community-published `hhg_*` extensions I've never seen before.
- I call `requires(...)` myself to confirm the host has the functions
  I'm planning to use before generating code.
- I can rely on the catalog `.md` shipped with every `hhg_*` package
  for human-readable function documentation.

### As a developer evaluating the HHG ecosystem (the v1 demo experience)

This is the experience the end-to-end demo (`examples/data_pillars.py`)
is built to deliver, on **both** backends.

- I open `dart_monty_ide`, click `examples/data_pillars.py`, hit Run.
- Within ~2 seconds I see, in the Monty UI panel, an SVG bar chart
  showing aggregated sales by region rendered from a real CSV. The
  console shows: "Loaded 50,000 rows", "Filtered 12,400 to West
  region", "Grouped into 8 categories", "Rendered chart".
- The script itself is **30-ish lines of Python** that compose three
  HHG packages — DuckDB SQL pulls and aggregates, dataframe verbs
  reshape, an SVG generator emits a chart spec the host renders.
- I switch to the **Flutter web build** (the same IDE, served from
  `flutter run -d chrome`), open the same script, hit Run. **Same
  chart, same numbers, same script source — no edits.** That's the
  proof the contract works identically across FFI and WASM.
- I read the script and understand it: imports nothing exotic
  (`requires([...])` at the top names the host functions it depends
  on), a SQL string, a couple of dataframe calls, an SVG-string
  template, `svg_render(...)` at the end. No black boxes; every
  primitive comes from the catalog.
- I open the catalog `.md` files for each `hhg_*` package and find
  every function the demo uses, with parameters, types, and a
  description.

The demo's job is to make the ecosystem **legible at a glance** to a
Dart developer who has never seen `dart_monty` before, while
demonstrating that the contract holds across both backends in a
single script with no special-casing.

Anti-goals for the demo:

- Not a beautiful chart. ASCII-quality SVG is fine; this is not a
  fl_chart competitor demo.
- Not a benchmark. We don't quote QPS; we quote "it ran in seconds."
- Not a feature tour. One coherent task end-to-end beats three
  unrelated vignettes.

### As a future downstream (soliplex or another)…

- I depend on `dart_monty` and a curated set of `hhg_*` packages. My
  host app implements whatever `*HostApi` interfaces my use case needs
  (e.g., AGUI surface projection writes its own `AguiSurfaceHostApi`
  impl when the time comes).
- The contract `dart_monty` ships does not assume my plumbing. AGUI is
  just another extension that happens to follow the rules.

---

## Implementation specification

This section is the engineering work to deliver the user stories above.
Stages are separable. S1 and S2 are prerequisites for the pillar work;
S3, S4, S5 are independent and can run in parallel.

### Backdrop: how `MontyExtension` works today

A `MontyExtension` (`dart_monty/lib/src/extension/extension.dart`)
declares:

- `String get namespace` — prefix for all functions (e.g. `'tmpl'`).
- `List<HostFunction> get functions` — the actual host functions.
- Optional: `osContribution`, `childPolicy`, `priority`,
  `supportedBackends`, `onAttach`, `onDispose`, `systemPromptContext`.

A `HostFunction` (`dart_monty/lib/src/host/function.dart`) is a schema
+ handler pair:

```dart
HostFunction(
  schema: HostFunctionSchema(
    name: 'df_filter',
    description: 'Filter rows by a predicate dict.',
    params: [
      HostParam(name: 'df', type: HostParamType.map),
      HostParam(name: 'predicate', type: HostParamType.map),
    ],
  ),
  handler: (args, ctx) async => /* … */,
)
```

The runtime sees a flat global namespace — Monty has no dot attribute
access on host objects, so `df_filter` is the only valid form.

### Backdrop: Monty interpreter constraints (load-bearing)

These shape every design decision in this plan. Sources:
`dart_monty_ide/MONTY_RESTRICTIONS.md` and
`dart_monty/docs/tutorials/llm-prompt-rules.md`.

- **No user-defined modules / no `import` of arbitrary modules.** Stdlib
  only: `json`, `math`, `re`, `pathlib`, `datetime`, `collections`,
  `sys`, `typing`, `asyncio`, sandboxed `os`. There is no module system
  to hook for dependency declarations.
- **No user-defined classes.** Dicts and functions only.
- **No dot attribute access on host objects.** `flutter.set_color()` is
  not allowed; must be `flutter_set_color()`.
- **Single global namespace.** All host functions are flat globals.
  Naming discipline is a hard requirement, not a style preference.
- **No `async`/`await` from user code, no generators, no walrus, no
  `eval`/`exec`.**

### Backdrop: `Monty.typeCheck` is shipped

`dart_monty_core` exposes
`Monty.typeCheck(code, {prefixCode, scriptName})` — the upstream
`monty-type-checking` crate, returning `List<MontyTypingError>` with
code/path/line/column. The `prefixCode` parameter lets the analyser see
declarations not in the user's source. That is the load-bearing
capability v1 builds on.

### Backdrop: the IDE's existing type-check shim

`dart_monty_ide/lib/src/controller/monty_ide_controller.dart` already
has a working version (`buildHostStubs`) that walks registered
extensions and emits one Python stub per host function:

```python
# Auto-generated host-function stubs for Monty.typeCheck — do not edit.
def df_filter(df: dict, predicate: dict) -> object: raise NotImplementedError
def el_recv() -> dict: raise NotImplementedError
# …
```

Two encoded pieces of wisdom worth preserving when we lift it:

1. **`raise NotImplementedError`** in the body, not `pass` / `...`.
   `pass`/`...` are inferred as returning `None`, which conflicts with
   non-None return annotations. `raise` types as `Never`, satisfying any
   annotation.
2. **An override table** maps known function names to sharper return
   types (`el_recv → dict`). Existing comment: *"When `dart_monty`
   grows a return-type field we can drop the overrides."* That field is
   exactly what S1.a adds.

The shim is wired into:
- `MontyIdeController.typeCheck` (the Type Check button, controller line ~229)
- `IdeToolHandler.typeCheck` (the assistant's tool path, handler line ~30)

Both call sites migrate to the lifted utility once it exists.

### Conventions (S0)

These rules are non-negotiable for any package claiming the `hhg_*`
prefix. They become `dart_monty/docs/extensions/conventions.md`.

#### Naming

- Package name: `hhg_<extension>` on pub.dev.
- One namespace prefix per package, used as the function-name prefix
  (`hhg_dataframe` → `df_*`, `hhg_duckdb` → `duck_*`, `hhg_svg` → `svg_*`).
- Function names are flat globals (Monty constraint, not convention).
- **Append-only.** Once a function name is published, it never changes
  meaning. No renames. No silent signature changes.
- Breaking changes ship as **`<name>_v2`**. Both versions remain callable
  from the same runtime; old scripts keep working.
- Spec dicts emitted by extensions (SVG element shapes, future chart
  specs, etc.) are also append-only — adding a key is fine; removing or
  re-typing is breaking and must ship as a `_v2`.

#### Three-layer rule for UI-dependent extensions

Pure-data extensions are a single pub package. UI-dependent extensions
split into three:

```
hhg_<thing>             (pure Dart)   — extension, schema + spec assembly
hhg_<thing>_host_api    (abstract)    — interface the host implements
hhg_<thing>_<impl>      (Flutter, …)  — reference renderer
```

The pure-Dart extension never imports `flutter`, `dart:ui`, or platform
channels. Every host (IDE, soliplex-frontend, CLI, headless tests)
implements the abstract host API; multiple impls per host API are
allowed and encouraged.

#### Versioning (v1)

The v1 versioning story is **append-only naming**, full stop. No
package-version assertions, no version-spec syntax, no per-extension
`version` field. Everything below is convention enforced by maintainer
discipline plus a small CI guard. Package-level versioning is
**Phase 2**, deferred until the trio lands and we've validated
composition — the design sketch lives in the *Future work — package
versioning (Phase 2)* appendix.

The reasoning for deferring is concrete: pillars are brand new in v1,
no breaking changes have happened yet, and we'd rather observe how the
trio composes in real scripts before deciding the shape of the
versioning mechanism. Versioning is purely additive when we add it
later; nothing in v1 forecloses on the appendix's design.

##### Append-only as the rule

- Once a function name is published, it never changes meaning.
- No renames, no silent signature changes.
- Breaking changes ship as `<name>_v2`. Both the original and the v2
  remain callable from the same runtime; old scripts keep working.
- Spec dicts emitted by extensions (SVG element shapes, future chart
  specs) are also append-only — adding a key is fine; removing or
  re-typing is breaking and must ship as a `_v2`.

##### Runtime-level enforcement (already in `dart_monty`)

`ExtensionCoordinator._checkFunctionCollisions` (in
`dart_monty/lib/src/extension/coordinator.dart`, line ~627) already
enforces three rules at extension-registration time, before any script
runs:

1. **Every function name must start with `<namespace>_`.** A function
   declared in extension `df` whose name doesn't start with `df_`
   throws `ArgumentError` at register-time.
2. **No duplicate function names within a single extension.**
   `ArgumentError`.
3. **No function name collisions across extensions in the same
   coordinator.** A second extension trying to register a name another
   extension already registered throws `StateError`.

Plus, the coordinator validates the namespace itself
(`_validateNamespace`, line ~603): must match `^[a-z][a-z0-9_]*$`, max
32 chars, not in `{'introspection', 'extra'}`, and unique within the
coordinator.

These guards mean two competing `hhg_*` packages can never silently
hijack each other's identifiers. The host operator gets a load-time
error if their dependency set is incoherent; they don't get
"`df_filter` sometimes does the wrong thing." That's the foundation
append-only sits on.

##### Breaking vs non-breaking changes — taxonomy

| Change | Type | Action required |
|---|---|---|
| Add a new function | Non-breaking | Minor package bump. |
| Add a new optional param (with default) to existing function | Non-breaking *for callers that don't use it*. See gap below. | Minor package bump. |
| Add a new **required** param | Breaking | Ship as `<name>_v2`. Original keeps current signature. |
| Remove a param | Breaking | Ship as `<name>_v2`. |
| Rename a param | Breaking *for kwargs callers* | Ship as `<name>_v2`. |
| Change a param's type | Breaking | Ship as `<name>_v2`. |
| Change return type | Breaking under `strict: true` | Ship as `<name>_v2`. |
| Change a function's semantics without changing the signature | Semantically breaking, statically undetectable | Ship as `<name>_v2`. Document the original as deprecated in description. |
| Change description text | Non-breaking | Patch package bump. |
| Remove a function | **Disallowed** | Major package bump at minimum, and even then we strongly discourage it. Old scripts that didn't update break. |
| Change `MontyExtension.namespace` | **Disallowed** | Effectively renames every function. Equivalent to removing all of them. |

##### Maintainer playbook: shipping a `<name>_v2`

Concrete worked example. `hhg_dataframe` v1.0 ships:

```dart
HostFunctionSchema(
  name: 'df_filter',
  description: 'Filter rows by predicate.',
  params: [
    HostParam(name: 'df',        type: HostParamType.map),
    HostParam(name: 'predicate', type: HostParamType.map),
  ],
  returnType: 'dict',
)
```

The maintainer realises `predicate` should be a list-of-conditions, not
a dict. v2.0 of the package keeps the original *and* adds a v2 form:

```dart
@override
List<HostFunction> get functions => [
  // v1 — still here, signature unchanged. Existing scripts keep working.
  HostFunction(
    schema: HostFunctionSchema(
      name: 'df_filter',
      description:
        'Filter rows by predicate dict. Deprecated: prefer df_filter_v2 for richer predicates.',
      params: [
        HostParam(name: 'df',        type: HostParamType.map),
        HostParam(name: 'predicate', type: HostParamType.map),
      ],
      returnType: 'dict',
    ),
    handler: _filterV1,
  ),

  // v2 — new name, new signature, new handler.
  HostFunction(
    schema: HostFunctionSchema(
      name: 'df_filter_v2',
      description: 'Filter rows by a list of conditions.',
      params: [
        HostParam(name: 'df',         type: HostParamType.map),
        HostParam(name: 'conditions', type: HostParamType.list),
      ],
      returnType: 'dict',
    ),
    handler: _filterV2,
  ),
];
```

Both functions are registered. Both stubs land in the prefix code:

```python
def df_filter(df: dict, predicate: dict) -> dict: raise NotImplementedError
def df_filter_v2(df: dict, conditions: list) -> dict: raise NotImplementedError
```

Old scripts (`df_filter(df, {"col": "x"})`) keep working. New scripts
(`df_filter_v2(df, [{"col": "x", "op": "=="}])`) opt in by name.
Neither calls the other; they're separate functions with separate
handlers and (potentially) separate validation logic.

The *next* major version, v3, **still** keeps `df_filter`. Removing it
is reserved for a documented end-of-life cycle that the maintainer
publicly announces and that the catalog reflects.

##### CI guard for append-only discipline

A small CI check we recommend each `hhg_*` package adopts: take the
output of S7's catalog generator (the JSON catalog), commit it to the
repo as `catalog.golden.json`, and have CI fail if the new catalog
removes any function name that was present in the previous version's
catalog. Pure mechanical guard. Catches the "a contributor renamed
`df_filter` to `df_where` thinking it was a polish PR" scenario before
publish.

Same guard can flag *signature changes* on existing function names —
type changes, removed params, renamed params. CI fails, contributor
ships as `_v2` instead.

#### Static checking

- Every host function declares a return type, supplied via the
  `HhgFunction(...)` builder in `dart_monty_hhg` (sidecar metadata —
  no change to `HostFunctionSchema` in `dart_monty`).
- Host apps may run scripts via `Hhg.run(runtime, code, strict: true)`,
  which gates execution on `Monty.typeCheck` against auto-generated
  host-function stubs (return-type-aware).
- Extensions MUST treat `strict: true` as a supported mode and ship
  type annotations on params and return types that survive
  type-checking.
- The IDE's existing Type Check button continues to work unchanged —
  it stays a manual affordance, separate from `strict`.

#### Backend support and the FFI-first / WASM-gate policy

- Default: extension claims both `ffi` and `wasm` via
  `MontyExtension.supportedBackends`.
- Per-`HostFunction` `ffiHandler` / `wasmHandler` slots can be used for
  asymmetric implementations.
- An extension that only works on one backend declares so explicitly.

**Definition of done** for every pillar package and for the
end-to-end demo (S6):

> Both backends work. FFI lands first; WASM follows; neither
> alone counts as complete.

The development methodology is **FFI-first, WASM-second**:

1. **Author against FFI.** Native dev loop is the fastest debugging
   surface — `dart test`, native print streams, FFI stack traces,
   IDE breakpoints. Get all tests green on FFI before touching WASM.
2. **Then port to WASM.** Run the same tests under headless Chrome
   (or the existing `dart_monty_core` WASM test harness). Resolve
   web-specific issues (asset bundling, COI mode, browser console
   errors, JS interop quirks).
3. **Both green = stage complete.** Pub.dev publish is gated on the
   WASM job being green. CI runs both as a matrix on every PR.

This applies to:

- S1 (`dart_monty_hhg` adapter — pure Dart, should "just work" on
  both, but tests on both)
- S3 (`hhg_dataframe`)
- S4 (`hhg_duckdb` — spatial smoke test on both, see Pillar 2 caveats)
- S5 (`hhg_svg` + `hhg_svg_flutter`)
- S6 (the end-to-end demo script must run identically in `dart run`
  *and* in the IDE's Flutter web build)

#### Statelessness

- Extension instances must tolerate being thrown away and rebuilt.
  `dart_monty_ide` re-runs the factory on every Reset Interpreter.
  Durable state lives outside the extension (existing pattern:
  `WidgetRegistry` in the IDE).

### v1 pillars

| # | Package | Wraps | Layer | Backends |
|---|---|---|---|---|
| 1 | `hhg_dataframe` | dartframe (subset) | Single | ffi + wasm |
| 2 | `hhg_duckdb` | dart_duckdb (+ spatial) | Single | ffi + wasm |
| 3 | `hhg_svg` + `hhg_svg_flutter` | jovial_svg | Three-layer | ffi + wasm |

#### Pillar 1 — `hhg_dataframe`

- Namespace: `df_`.
- Wraps a curated subset of [dartframe](https://pub.dev/packages/dartframe)
  to avoid pulling its full transitive dep set (mysql, postgres, sqlite3,
  http, excel, HDF5).
- Surface (~6–8 verbs): `df_load_csv`, `df_select`, `df_filter`,
  `df_groupby`, `df_join`, `df_to_records`, `df_describe`. Final list
  during S3.
- Pressure-tests: large list/dict marshalling, nested types, schema
  correctness for collections-of-collections.

#### Pillar 2 — `hhg_duckdb`

- Namespace: `duck_`.
- Wraps [dart_duckdb](https://pub.dev/packages/dart_duckdb).
- Includes spatial extension. Verified: FFI smoke test passed
  (`INSTALL spatial; LOAD spatial; ST_AsText(ST_Point(1,2))` → `POINT (1 2)`);
  WASM supported as of `duckdb-wasm` v1.29.0, which `dart_duckdb` 1.4.4
  already pins (`@duckdb/duckdb-wasm@1.29.1-dev222.0`).
- Surface (~5–7 verbs): `duck_open`, `duck_close`, `duck_query` (rows as
  list-of-dict), `duck_query_records` (columnar dict-of-list for cheap
  dataframe hand-off), `duck_install_extension`, `duck_load_extension`.
  Final list during S4.
- Pressure-tests: FFI handle lifecycle across `MontyExtension`
  re-creation, per-backend asymmetry, large result-set marshalling.
- **CI gate**: a smoke test running the same SQL on both backends every
  release. Known WASM rough edges (`duckdb/duckdb-wasm` issues #2199,
  #2216, #2041, #1916, #2005) are not in scope but motivate the gate.
- **macOS pure-Dart caveat** (carries forward to docs): `dart_duckdb`
  1.4.4 does not bundle libduckdb on macOS for pure-Dart consumers; it
  relies on the Flutter plugin layer to inject via
  `DynamicLibrary.process()`. Pure-Dart consumers must call
  `open.overrideFor(OperatingSystem.macOS, '/path/to/libduckdb.dylib')`.
  Inside Flutter (the actual `dart_monty_ide` and soliplex-frontend use
  cases) this is automatic. Document, don't fix.

#### Pillar 3 — `hhg_svg` + `hhg_svg_flutter`

- Namespace: `svg_`.
- Three packages:
  - `hhg_svg` (pure Dart): SVG-string generation primitives + validation.
    Surface (~4–6 verbs): `svg_render(svg_string)`,
    `svg_template(template, data)`, `svg_path`, helpers for line / bar /
    scatter primitives. Final list during S5.
  - `hhg_svg_host_api` (abstract): `SvgHostApi.display(String svg)` and
    related. Lives inside `hhg_svg` for v1; split if a real consumer
    asks for it.
  - `hhg_svg_flutter` (Flutter): reference renderer using
    [jovial_svg](https://pub.dev/packages/jovial_svg) (BSD-3, web +
    native, 258k weekly downloads). Wired into `dart_monty_ide` as the
    IDE's SVG renderer.
- Why `jovial_svg` over `pure_svg`: `jovial_svg` supports web; `pure_svg`
  does not (no web in its supported platforms list as of v0.0.6).
- Why no chart pillar: no maintained pure-Dart SVG charter exists. The
  `hhg_svg` primitive lets a community `hhg_chart` package layer cleanly
  on top later — exactly the ecosystem behaviour we want.
- Pressure-tests: the **three-layer rule**. AGUI surface projection will
  follow the same shape, so getting it right in v1 matters.

### Repository layout and what goes where

All v1 work lives in a new private monorepo,
**`github.com/runyaga/dart_monty_labs`**, structured as Dart top-level
packages. `dart_monty` itself is **untouched in v1.**

```
dart_monty_labs/                          (private monorepo)
├── docs/
│   └── HHG_V1_PLAN.md                    (this document)
├── packages/
│   ├── dart_monty_hhg/                   (the adapter — all mechanism lives here)
│   │   ├── lib/
│   │   │   ├── hhg.dart                  (Hhg.run, HhgTypeCheckError)
│   │   │   ├── prefix_code.dart          (extensionsToPrefixCode)
│   │   │   ├── hhg_function.dart         (HhgFunction builder + sidecar)
│   │   │   └── requires_extension.dart   (requires([...]) host fn)
│   │   └── pubspec.yaml                  (depends on dart_monty)
│   ├── hhg_dataframe/                    (pillar 1)
│   ├── hhg_duckdb/                       (pillar 2)
│   ├── hhg_svg/                          (pillar 3 — pure Dart)
│   └── hhg_svg_flutter/                   (pillar 3 — Flutter renderer)
└── melos.yaml                            (workspace tooling)
```

**Why monorepo, not one repo per package:** the contract is still
moving. While we're iterating on `dart_monty_hhg` and the pillars
together, atomic cross-package changes in single PRs are worth more
than pub.dev-shaped repo separation. Once the contract stabilises
(post-trio, when versioning Phase 2 is also in flight), each pillar
can split into its own public repo for community PRs.

**What stays in `dart_monty_ide`:**
- The IDE itself (Flutter app, no changes to its core).
- A small migration: two call sites in
  `MontyIdeController.typeCheck` and `IdeToolHandler.typeCheck` switch
  from the local `buildHostStubs` shim to `dart_monty_hhg`'s
  `extensionsToPrefixCode`. Plus a pubspec dep on `dart_monty_hhg`
  + the three pillars.

**What stays in `dart_monty`:**
- Nothing changes. No new fields, no new flags, no new functions.
  The runtime API is exactly what it is today. If HHG patterns prove
  themselves in v1, we promote pieces into `dart_monty` later as
  pure upstreaming.

### Stage breakdown

#### S0 — Conventions doc

Move the conventions section above into
`dart_monty_labs/docs/conventions.md` (and link to it from the
`dart_monty_hhg` README). Lives in `dart_monty_labs` for v1; if
HHG patterns get promoted into `dart_monty`, this doc moves into
`dart_monty/docs/extensions/conventions.md` at that point. No code.

#### S1 — `dart_monty_hhg` adapter package

A new package in `dart_monty_labs/packages/dart_monty_hhg/`. Depends on
`dart_monty`. **Zero changes to `dart_monty` itself.**

**S1.a — `HhgFunction` builder with sidecar return-type metadata**

- A builder fn / class that wraps `HostFunction` and carries a
  free-form Python annotation string (`'object'`, `'dict'`,
  `'list[str]'`, etc.) for the return type. Stored in a sidecar map
  the prefix-code generator reads.

  ```dart
  HhgFunction(
    name: 'df_filter',
    params: [...],
    returnType: 'dict',
    handler: ...,
  )
  ```

  The builder emits a vanilla `HostFunction` (so `dart_monty`'s
  coordinator registers it normally) plus an entry in
  `Map<String, String> _hhgReturnTypes`. The map is exposed via
  `Hhg.returnTypeOf(name)` and consumed by the prefix-code generator.

- Free-form `String` over enum. Allows `'dict[str, int]'` and similar
  Python types the typechecker understands.

- A small CI lint in each `hhg_*` package: every host function that
  ships in the package is built via `HhgFunction(...)`, never via
  raw `HostFunction(...)`. Keeps the sidecar populated.

**S1.b — `extensionsToPrefixCode` utility**

- Pure Dart static fn in `dart_monty_hhg`:

  ```dart
  String extensionsToPrefixCode(List<MontyExtension> extensions);
  ```

  Walks each extension's `functions`, emits one Python stub per host
  function. Reads return types from `Hhg.returnTypeOf(name)`; falls
  back to `'object'` if not declared. Header: `# Auto-generated
  host-function stubs for Monty.typeCheck — do not edit.` Body:
  `raise NotImplementedError` (not `pass`/`...`).

- Mapping table (lifted verbatim from the IDE's existing
  `buildHostStubs`):

  | `HostParamType` | Python annotation |
  |---|---|
  | `string`  | `str`    |
  | `integer` | `int`    |
  | `number`  | `float`  |
  | `boolean` | `bool`   |
  | `list`    | `list`   |
  | `map`     | `dict`   |
  | `any`     | `object` |

- Migrate both call sites in `dart_monty_ide`:
  - `MontyIdeController.typeCheck` (line ~229)
  - `IdeToolHandler.typeCheck` (line ~30)

  Both switch to `Hhg.prefixCode(runtime.coordinator.extensions)` (or
  similar). Drop the local `buildHostStubs` and the `el_recv → dict`
  override table — both become redundant once the IDE's own
  extensions are migrated to declare return types via the sidecar.

**S1.c — `Hhg.run(...)` wrapper + `HhgTypeCheckError`**

- A static helper:

  ```dart
  class Hhg {
    static Future<MontyResult> run(
      MontyRuntime runtime,
      String code, {
      bool strict = false,
    }) async {
      if (strict) {
        final prefix = extensionsToPrefixCode(
          runtime.coordinator?.extensions ?? const [],
        );
        final errors = await Monty.typeCheck(code, prefixCode: prefix);
        if (errors.isNotEmpty) throw HhgTypeCheckError(errors);
      }
      return runtime.execute(code).result;
    }
  }
  ```

  Hosts that don't want enforcement keep using
  `runtime.execute(...)` directly — `dart_monty` is unchanged.

- `HhgTypeCheckError extends Error` (or `Exception`), exposes
  `List<MontyTypingError> errors`.

- Tests:
  - `strict: false` (default) runs untyped code as today.
  - `strict: true` with valid annotated code runs.
  - `strict: true` with type errors throws `HhgTypeCheckError` before
    any host function fires.

#### S2 — `requires()` host function in `dart_monty_hhg`

- Lives in `dart_monty_hhg` as `RequiresExtension extends MontyExtension`.
  Hosts opt in by registering it alongside other extensions. (Not added
  to `dart_monty`'s introspection module.)
- Schema:

  ```dart
  HhgFunction(
    name: 'requires',
    description:
      'Assert that the named host functions are available in this runtime. '
      'Raises RuntimeError listing any missing names.',
    params: [
      HostParam(name: 'names', type: HostParamType.list),
    ],
    returnType: 'None',
    handler: (args, ctx) async {
      final names = (args['names'] as List).cast<String>();
      final available = ctx.bridge.schemas.map((s) => s.name).toSet();
      final missing = names.where((n) => !available.contains(n)).toList();
      if (missing.isNotEmpty) {
        throw StateError(
          'requires(): missing host function(s): ${missing.join(", ")}. '
          'Install the extension that provides them or remove the requirement.',
        );
      }
      return null;
    },
    isInfra: true,
  )
  ```

- Python usage:

  ```python
  requires(["df_filter", "df_groupby", "duck_query", "svg_render"])
  ```

- `isInfra: true` bypasses any user-installed interceptor. A capability
  check is infrastructure, not user-facing tool dispatch.
- **`requires()` checks function names only.** Package-version
  assertion (the mobile-fleet forward-incompat scenario) is Phase 2.
  See *Future work — package versioning (Phase 2)*.

#### S3 — `hhg_dataframe` package

- New package in `dart_monty_labs/packages/hhg_dataframe/`.
- Wraps a curated subset of dartframe — avoid pulling its kitchen-sink
  transitive deps into every consumer.
- Single class: `DataFrameExtension extends MontyExtension`.
- ~6–8 host functions, all built via `HhgFunction(...)` so return
  types populate the prefix-code sidecar.
- **Backend gating**: FFI-first development, then WASM. Both green
  (CI matrix) is the exit criterion. dartframe is pure Dart, so the
  WASM port should be straightforward; surprises here are the early
  signal that the contract has holes.
- Doc: README + a tiny example script + auto-generated catalog.
- Exit criteria: `hhg_dataframe` builds, both CI jobs pass,
  `dart_monty_ide` consumes it via a path dep, and a hand-written
  test script using `df_*` verbs runs identically on FFI and WASM.

#### S4 — `hhg_duckdb` package

- Same shape as S3.
- First execute opens an in-memory DB and runs `INSTALL spatial; LOAD spatial;`
  once per session.
- **Backend gating**: FFI-first; FFI smoke test for spatial already
  validated (`ST_AsText(ST_Point(1,2))` → `POINT (1 2)` in
  `dart_duckdb` 1.4.4). WASM follows; duckdb-wasm 1.29 supports
  spatial per release notes. Known WASM rough edges (GeoParquet
  read, COI mode loading) are out of scope but motivate the smoke
  test in CI on both backends.
- README carries the macOS pure-Dart libduckdb caveat verbatim.
- Exit criteria: same SQL — including a non-trivial spatial query —
  runs identically on FFI and WASM in CI.

#### S5 — `hhg_svg` + `hhg_svg_flutter`

- `hhg_svg` (pure Dart): extension + abstract `SvgHostApi`.
- `hhg_svg_flutter` (Flutter): implements `SvgHostApi` using
  `jovial_svg`. Adds a widget the IDE can mount in its existing Monty
  UI panel, or a new SVG panel — TBD during S5.
- `dart_monty_ide` wires `hhg_svg_flutter` as its `SvgHostApi` impl.
- **Backend gating**: FFI-first; jovial_svg supports web + native
  per pub.dev. WASM port for the renderer is the validation that the
  three-layer rule holds across backends (an `SvgHostApi` impl
  written once works in both Flutter native and Flutter web).
- Exit criteria: a Python script does `svg_render(<simple svg>)` and
  the IDE renders the *same* output in `flutter run` and
  `flutter run -d chrome`.

#### S6 — End-to-end demo script

Lives in `dart_monty_ide/examples/data_pillars.py`:

```python
requires(["duck_query", "duck_load_extension", "df_groupby", "svg_render"])

duck_load_extension("spatial")
rows = duck_query("""
  SELECT region, sum(sales) AS total
  FROM read_csv_auto('sales.csv')
  GROUP BY region
""")

# Hand off to dataframe for shaping
agg = df_groupby(rows, by="region", agg={"total": "sum"})

# Render as a hand-rolled SVG bar chart (string templating, no chart engine)
svg = build_svg_bar_chart(agg)  # pure Python in the script
svg_render(svg)
```

Final form during S6. Lands in seeded examples.

**Backend gating for S6**: the demo is the headline cross-backend
test. FFI must run cleanly first (faster debugging turnaround for
shaping the SQL, dataframe verbs, and SVG layout). Then the *same
script source* must produce the *same chart* in `flutter run -d chrome`.
Neither alone is "demo done." A small CI workflow runs the demo
under both backends with the same input CSV and diffs the resulting
SVG strings (or a stable hash) — drift between backends fails CI.

This is the moment the contract is proven: identical Python, three
HHG packages composed, two backends, one output. The user story
"As a developer evaluating the HHG ecosystem" describes what this
delivers from the outside.

#### S7 — Catalog generation

- Per-package `tool/generate_catalog.dart`: walks `extension.functions`,
  emits `catalog.json` + `catalog.md`.
- Each entry: `name`, `description`, `params`, `returnType`, `version`.
  Same source-of-truth as runtime introspection.
- Run as a release step. Substrate for: docs site, LLM tool exposure,
  future "what's installed" UI.

#### S8 — `HhgBundle` for IDE-operator composition

A small helper in `dart_monty_hhg`:

```dart
class HhgBundle extends MontyExtension {
  HhgBundle({
    required this.namespace,
    required List<HostFunction> functions,
    this.systemPromptContext,
  });
  @override final String namespace;
  @override final List<HostFunction> functions;
  @override final String? systemPromptContext;
}
```

Lets a host curate functions across multiple `hhg_*` packages without
subclassing.

### Deferred (Phase 2 / v1.5 / community)

- **Package versioning (Phase 2).** `MontyExtension.version` getter,
  `requires_pkg(name, spec)`, version-spec parser. Detailed design
  in the *Future work — package versioning* appendix. Triggered when
  the trio lands and we have real composition data.
- `hhg_geoengine` — procedural-geo surface duckdb-spatial doesn't cover
  (geocoding, UTM/MGRS, geodetic adjustments, astronomy).
- `hhg_chart` — chart engine layered on `hhg_svg`.
- `hhg_ascii_chart` — wraps `ascii_chart` for terminal-style output.
- AGUI extension — designed once the contract is proven; producer-only
  at first; consumer side via existing `EventLoopExtension`. Soliplex
  writes the host impl when it's ready.
- MCP-proxy extensions, per-script bundles via `SandboxExtension`.

---

## Open questions / decisions to validate with reviewer

1. **`returnType` storage — sidecar map vs. wrapping HostFunction.**
   The `HhgFunction` builder emits a vanilla `HostFunction` and a
   sidecar entry. Alternative: subclass `HostFunction` (`HhgFunctionImpl
   extends HostFunction`) and carry the return type as a field on the
   subclass. Recommendation: sidecar — keeps the dispatch path
   identical, avoids any temptation to teach `dart_monty` about HHG.

2. **Where does `SvgHostApi` live?**
   - Inside `hhg_svg` — simpler, one fewer package.
   - In `hhg_svg_host_api` (separate micro-package) — cleaner dep graph.
   Recommendation: inside `hhg_svg` for v1; split if a real consumer
   asks for it.

3. **Do we ship `hhg_svg_pure` (non-Flutter, `pure_svg`-backed)?**
   v1: skip. `pure_svg` has no web. Re-evaluate when there's a real
   non-Flutter consumer.

4. **`HhgTypeCheckError` semantics.** Subclass of `Error` (programmer
   error, you should have type-checked your code) or `Exception`
   (a recoverable runtime condition the host might want to catch and
   render UX for)? Recommendation: `Exception` — hosts will catch and
   surface it to users, that's a normal control flow.

5. **macOS pure-Dart libduckdb.** Doc only, no code. But: should
   `dart_duckdb` upstream this (bundle libduckdb on macOS for
   pure-Dart consumers)? Out of scope for this plan; flag for later.

6. **Promotion path.** When does proven HHG mechanism move from
   `dart_monty_hhg` into `dart_monty`? Triggers worth agreeing on:
   (a) when a non-HHG consumer (Soliplex, MCP-proxy ext, anyone) asks
   for the same mechanism; (b) when a major version of `dart_monty`
   ships and we want to clean up; (c) never — `dart_monty_hhg` stays
   the canonical adapter. Recommendation: revisit when the trio lands;
   the answer should be informed by what real composition looks like.

---

## Risks

- **Schedule.** Three pillars + the `dart_monty_hhg` adapter + the
  conventions doc + an end-to-end demo + cross-backend (FFI + WASM)
  validation on every pillar in roughly a month is tight. Honest
  fallback: ship S0–S2 + dataframe + duckdb in v1; SVG slips to v1.1
  if it has to. Three-layer validation lands when SVG lands; AGUI
  consequently waits longer. Acceptable.

- **Cross-backend integration cost.** The FFI-first / WASM-second
  policy doubles per-pillar integration work for the WASM cycle —
  COI-mode loading, asset bundling, browser-console debugging, JS
  interop quirks. Mitigation: budget WASM as a discrete pass per
  pillar (estimate ~30–50% of FFI's effort for the same pillar), run
  WASM CI from day one of each pillar so issues surface early rather
  than at "ship" time, and lean on `dart_monty_core`'s existing WASM
  test harness as a reference rather than reinventing it.

- **No package-version protection in v1.** A device fetching a script
  written against newer extension versions will fail with confusing
  runtime errors (missing kwargs, NameErrors on `_v2` functions) rather
  than a clean "update the app" message. Mitigation for the immediate
  term: pillars are brand new, no breaking changes have happened yet,
  scripts and runtimes ship together. Long-term mitigation: Phase 2,
  designed in the appendix, triggered when the trio lands. Consciously
  accepting this gap for v1 to keep scope tight.

- **`dart_duckdb` macOS pure-Dart caveat** could trip up early-adopter
  CLI consumers. Mitigation: prominent doc, a `tool/check_duckdb.dart`
  helper.

- **`dartframe`'s transitive deps.** Pulling its full surface gives
  consumers mysql / postgres / sqlite3 / http for free, like it or not.
  Mitigation: `hhg_dataframe` wraps a curated subset; we audit the
  resulting transitive set before publishing.

- **Append-only discipline.** Once a function name is published it's
  frozen. Mitigation: documented hard rule + code review checklist;
  pre-publish review of the surface; CI check (`catalog.golden.json`)
  that no published name has changed signature in version bumps.

- **No pure-Dart chart library exists.** Demo polish is weaker without
  charts. Mitigation: `hhg_svg` lets a script hand-roll an SVG chart in
  a few dozen lines. Good enough for the v1 demo. Real charts arrive
  via community contribution.

- **`Monty.typeCheck` accuracy under pillar surfaces.** The typechecker
  has been validated on simple host functions (the IDE's existing
  extensions). Real pillars have richer types (nested dicts, optional
  params, large schemas). We should test the typechecker against each
  pillar's surface during S3 / S4 / S5 and surface any gaps for
  upstream fixes.

- **HhgFunction sidecar drift.** If an extension author registers a
  raw `HostFunction` instead of using `HhgFunction(...)`, the return
  type defaults to `'object'` and prefix-code generation loses
  fidelity. Mitigation: per-package CI lint asserting all
  `extension.functions` originated from `HhgFunction(...)`.

---

## What lands first if review goes well

- **`dart_monty_labs` repo skeleton** with `melos.yaml` + the package
  directories + this document committed under `docs/`.
- **S0**: conventions doc polished, committed at
  `dart_monty_labs/docs/conventions.md`.
- **S1.a**: `dart_monty_hhg` package skeleton + `HhgFunction(...)`
  builder with sidecar return-type metadata + tests.
- **S1.b**: `extensionsToPrefixCode` utility in `dart_monty_hhg`. The
  two IDE call sites (`MontyIdeController.typeCheck`,
  `IdeToolHandler.typeCheck`) migrate to use it. Local
  `buildHostStubs` and `el_recv → dict` override table both removed.
  IDE's own extensions migrate to declare return types via
  `HhgFunction(...)`.
- **S1.c**: `Hhg.run(runtime, code, strict: bool)` + `HhgTypeCheckError`,
  tests covering all four cases.
- **S2**: `RequiresExtension` in `dart_monty_hhg` with `requires([...])`
  host function. IDE registers it in its factory.

That's the foundation. After it lands, S3 / S4 / S5 are parallel work.
**`dart_monty` itself receives zero changes during all of v1.**

---

## Future work — package versioning (Phase 2)

Triggered when the hhg_trio lands and we have real composition data.
Designed here so it's clear nothing in v1 forecloses on it.

### The problem this solves

Mobile/MDM scenario: a device offline for weeks comes online, fetches
a script from a server, the script was authored against
`hhg_dataframe@2.1` but the device's app build still ships
`hhg_dataframe@1.0.3`. v1's `requires([...])` checks names — both v1
and v2 of `hhg_dataframe` register `df_filter` (append-only). The
script fails mid-execution with a confusing error. Phase 2 catches
this at the top of the script with a clear "update the app" message.

### Mechanism (purely additive to v1)

Three pieces, all in `dart_monty_hhg` (or promoted to `dart_monty`
once we agree HHG patterns belong there):

1. **`HasVersion` mixin** that any `MontyExtension` can implement:

   ```dart
   mixin HasVersion {
     String get version; // semver: '1.0.3', '2.0.0', etc.
   }
   ```

   Pillar packages add `with HasVersion` to their `MontyExtension`
   subclass and return their `pubspec.yaml` version. A small CI lint
   in each package diffs the value against `pubspec.yaml` to catch
   drift.

2. **`requires_pkg(name, spec)` host function** in
   `dart_monty_hhg`'s `RequiresExtension`. Reads the version from the
   matching extension via `is HasVersion` cast. Supports a minimal
   spec syntax — `>=X.Y.Z` only — for v2 of the design; PEP 508 if
   needed later.

   ```python
   requires_pkg("hhg_dataframe", ">=2.0")
   requires_pkg("hhg_duckdb",    ">=1.4")
   ```

   Raises Python `RuntimeError` with a structured message naming the
   package, the required spec, and the installed version. Host
   translates the message into UX-appropriate wording ("Update *App
   Name* to use this feature").

3. **`installed_packages()` introspection** that returns a dict of
   `{name: version}` for any extension with `HasVersion`. Lets the
   LLM Pilot (and anyone else) inspect what's available without
   parsing the script.

### Forward-compat properties to validate before building

- Adding `HasVersion` is opt-in. Existing extensions don't need to
  change. Treated as "unknown version, skip the check."
- `requires_pkg` is purely additive — scripts that don't call it
  don't pay anything.
- The mechanism doesn't depend on AST extraction, build-time
  manifests, or PEP 508 parsers — those layer on later if needed.

### What we'd validate during the trio's composition phase

- How often do scripts compose functions across multiple `hhg_*`
  packages? (If never, package-level granularity may not be the right
  unit.)
- Do scripts hit version-mismatch issues even within a single package
  during v1? (If yes, escalate Phase 2; if no, we have time.)
- What does the IDE's failure UX want from a structured error? (A
  package name + version + suggested action covers most cases; richer
  payloads might emerge from real demos.)

### What we'd defer past Phase 2

- Static AST extraction of a `__requires__` constant for server-side
  pre-delivery gating. Useful for soliplex eventually; not needed
  while the device-side gate is the canonical path.
- PEP 508 caret/tilde/multi-clause syntax. Can be added when the
  simple `>=` proves insufficient.
- Build-time manifest generation from `pubspec.lock`. Self-declared
  `version` getter + CI lint covers v2 needs.
- Per-function version pinning (`requires(["df_filter@1"])`).
  Append-only naming + per-package version covers the typical case.
