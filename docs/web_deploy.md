# Web build & GitHub Pages deployment

`dart_monty_ide` ships a Flutter web build that runs entirely in the
browser. The Monty interpreter executes via the WebAssembly bundle
shipped in `dart_monty_core/lib/assets/`, and the workspace VFS
falls back to an in-memory implementation (see `MemoryMontyVfs` in
`lib/main.dart`) so files live for the session and disappear on
reload.

## Live site

After the first push to `main`, the app is published at:

```
https://runyaga.github.io/dart_monty_ide/
```

(Replace the GitHub username if you fork.)

## How it builds in CI

The workflow at `.github/workflows/pages.yml` runs on every push to
`main`:

1. Checks out `dart_monty_ide`, `dart_monty`, and `dart_monty_core`
   as siblings (the IDE's `pubspec.yaml` references them via
   `path: ../dart_monty` and `path: ../dart_monty_core`).
2. Installs Flutter (pinned to 3.41.6, stable channel).
3. Runs `flutter build web --release --base-href /dart_monty_ide/`.
4. Uploads `build/web/` as a Pages artifact and deploys via
   `actions/deploy-pages@v4`.

No Rust toolchain step is needed — the WebAssembly artifacts are
committed to `dart_monty_core/lib/assets/`.

## One-time GitHub setup

In the repository **Settings → Pages**:

- **Source**: **GitHub Actions** (not "Deploy from a branch").

That's it. After the first successful workflow run, GitHub publishes
the deployed-pages environment URL.

## Local web dev

```bash
flutter run -d chrome
```

Hot reload works the same as desktop. The browser console will warn
about WASM dry-run mode — harmless for now.

## Connecting the AI Pilot to your local Ollama

The Pilot panel calls `http://localhost:11434` (the default Ollama
endpoint). When the IDE itself is served from `https://runyaga.github.io`,
two browser policies come into play:

- **Mixed content**: An HTTPS page is normally blocked from talking
  to plain HTTP. *Localhost is exempt* — modern Chrome, Firefox, and
  Safari treat `http://localhost` and `http://127.0.0.1` as
  "potentially trustworthy" and let the request through. No extra work.
- **CORS**: Ollama refuses cross-origin requests by default. You must
  tell `ollama serve` which origins are allowed.

### One-time Ollama setup

Set `OLLAMA_ORIGINS` before starting the server. On macOS/Linux:

```bash
export OLLAMA_ORIGINS="https://runyaga.github.io,http://localhost:*"
ollama serve
```

Or for any origin (less restrictive, fine for local dev):

```bash
OLLAMA_ORIGINS="*" ollama serve
```

Then make sure the model the IDE expects is pulled:

```bash
ollama pull gpt-oss:20b
```

### Verifying

1. Visit `https://runyaga.github.io/dart_monty_ide/`.
2. Open the AI Pilot panel.
3. Send a message. The browser's network tab should show a successful
   `POST http://localhost:11434/api/chat` (status 200) — not a CORS
   error.

If you see a CORS error, double-check that `OLLAMA_ORIGINS` includes
the origin shown in the browser's address bar (no trailing slash) and
that you restarted `ollama serve` after exporting the variable.

## What does *not* work on web

- **`LocalMontyVfs`** — desktop only. The web build silently uses
  `MemoryMontyVfs`; files written via `write_file` or the editor are
  in-memory only and disappear on tab close.
- **`getApplicationDocumentsDirectory()`** is gated by `kIsWeb` in
  `lib/main.dart`, so this is just informational.
- **OpenResponses provider** — works the same as desktop if its
  endpoint is reachable from the browser (with CORS configured).

## Roadmap

- IndexedDB-backed VFS so web users keep their workspace across reloads.
- Conditionally hide the Pilot panel when no LLM endpoint is reachable.
- A "demo mode" landing screen that doesn't require Ollama.
