# dart_monty_ide

A Flutter IDE for the [dart_monty](https://github.com/runyaga/dart_monty)
sandboxed Python interpreter, with an AI Pilot, a live Monty UI panel
driven by Python via `el_emit` / `el_recv`, and a layered system prompt
that auto-documents whatever extensions are loaded.

**Live web build:** https://runyaga.github.io/dart_monty_ide/

## Docs

- [Monty UI panel & layered prompt](docs/monty_ui.md)
- [Web build & GitHub Pages deployment](docs/web_deploy.md)

## Local dev

```bash
flutter run -d macos    # or -d chrome / -d windows / -d linux
```

The repo expects `dart_monty` and `dart_monty_core` as siblings (see
`pubspec.yaml` `path:` deps).
