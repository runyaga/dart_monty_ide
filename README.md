# dart_monty_ide

A Flutter IDE for the [dart_monty](https://github.com/runyaga/dart_monty)
sandboxed Python interpreter, with an AI Pilot, a live Monty UI panel
driven by Python via `el_emit` / `el_recv`, and a layered system prompt
that auto-documents whatever extensions are loaded.

**Live web build:** https://runyaga.github.io/dart_monty_ide/

## Connecting the AI Pilot

The Pilot panel calls a local [Ollama](https://ollama.com) server at
`http://localhost:11434`. To use it from the live site (or a desktop
build) you need three things on your machine:

### 1. Install Ollama and pull a model

```bash
# https://ollama.com/download
ollama pull gpt-oss:20b
```

The IDE defaults to the model name `gpt-oss:20b`. You can edit it in
the chat panel's settings if you have a different model installed.

### 2. Allow the IDE's origin (CORS)

By default Ollama refuses cross-origin requests, which means the
hosted page (or any non-default origin) gets blocked. Set
`OLLAMA_ORIGINS` before starting the server.

**For the live web build:**

```bash
export OLLAMA_ORIGINS="https://runyaga.github.io,http://localhost:*"
ollama serve
```

**Or to just allow everything (fine for local development):**

```bash
OLLAMA_ORIGINS="*" ollama serve
```

On macOS, if Ollama runs as a menu-bar app, set the env var via
`launchctl` so the app inherits it:

```bash
launchctl setenv OLLAMA_ORIGINS "*"
# Then quit and relaunch the Ollama app.
```

### 3. Open the Pilot

Reload the IDE, open the Pilot panel (chat icon in the toolbar), and
send a message. If you get a CORS error in the browser console,
double-check that `OLLAMA_ORIGINS` includes the origin shown in your
address bar (no trailing slash) and that you restarted Ollama after
exporting the variable.

> **Note about HTTPS → HTTP**: modern browsers (Chrome, Firefox,
> Safari) treat `http://localhost` as a "potentially trustworthy"
> origin, so an HTTPS page reaching localhost is allowed. No tunnel
> or reverse proxy is needed.

For OpenResponses or other providers, see the chat panel's settings
gear.

## Docs

- [Monty UI panel & layered prompt](docs/monty_ui.md)
- [Web build & GitHub Pages deployment](docs/web_deploy.md)

## Local dev

```bash
flutter run -d macos    # or -d chrome / -d windows / -d linux
```

The repo expects `dart_monty` and `dart_monty_core` as siblings (see
`pubspec.yaml` `path:` deps).
