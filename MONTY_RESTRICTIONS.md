# Monty Interpreter Restrictions

This document tracks known limitations and behaviors of the Monty Python interpreter (Rust-backed) used in this IDE.

## Language Limitations
- **No User-Defined Classes**: The `class` keyword is not supported. Use dictionaries and functions for data modeling.
- **No Modules/Packages**: Python modules (e.g. `import os`) are not supported. All "libraries" must be provided as host functions.
- **No Module Attributes on Host Objects**: Host objects are exposed as global functions. You cannot call `flutter.set_color()`; you must call `flutter_set_color()` or a similar global name.
- **No `async/await`**: The interpreter is synchronous.
- **No Generators**: `yield` and `yield from` are not supported.
- **Single Global Scope**: In stateful sessions, variables and functions defined in one execution block persist to all subsequent blocks.

## Bridge & Host Function Behavior
- **Return Values**: Host functions return results to Python.
- **Shadowing**: Caution must be taken to ensure global names (like host functions) are not shadowed by variables in user scripts (e.g. via list comprehensions or assignments).
- **Python 3 `print`**: `print` is a function. Use `print(value)`, not `print value`.
- **F-Strings**: Supported, using `{}` for interpolation.
- **List Comprehensions**: Supported, but verify variable leakage to global scope (REPL behavior).
