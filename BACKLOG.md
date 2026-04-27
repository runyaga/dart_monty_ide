# Project Backlog

## High Priority
- [ ] **re-editor Auto-completion Fix**: Currently, typing a closing character (e.g., `")"`) when auto-completion has already inserted it results in double characters (e.g., `print("")")`). We need to implement a "skip-over" logic or wait for an upstream fix in `re_editor`.
- [ ] **Variable Inspector**: Implement a panel to view current Python globals and their values.

## Medium Priority
- [ ] **Live Print Streaming**: Move from batch output to real-time `stdout` streaming.
- [ ] **Multi-Tab Support**: Allow having multiple files open in the editor simultaneously.

## Nice to Have
- [ ] **Persistence**: Save and restore entire interpreter snapshots.
- [ ] **REPL Mode**: Support for a true REPL (Incremental feed) if added to `dart_monty`.
