import 'package:dart_monty/dart_monty_bridge.dart';

/// Synthesizes the AI Pilot's system prompt by layering:
///   1. [basePrompt] — the static rules / Monty UI Mode docs.
///   2. `## RUNTIME EXTENSIONS` — each extension's `systemPromptContext`.
///   3. `## RUNTIME API` — auto-generated host-function signatures with
///      descriptions, walked from each extension's `functions`.
///   4. `## CURRENT SCRIPT` — fragments the running script registered
///      via `prompt_extend(text)`.
///
/// Pure function with no Flutter dependency — easy to inspect and unit test.
String buildSystemPrompt({
  required String basePrompt,
  required List<MontyExtension>? extensions,
  required List<String> scriptFragments,
}) {
  final buf = StringBuffer(basePrompt.trimRight());
  final exts = extensions ?? const <MontyExtension>[];

  final extFragments = <String>[
    for (final e in exts)
      if (e.systemPromptContext case final ctx? when ctx.trim().isNotEmpty)
        ctx.trim(),
  ];
  if (extFragments.isNotEmpty) {
    buf.writeln('\n\n## RUNTIME EXTENSIONS');
    for (final f in extFragments) {
      buf.writeln('- $f');
    }
  }

  final apiDocs = buildHostApiDocs(exts);
  if (apiDocs.isNotEmpty) {
    buf
      ..writeln('\n## RUNTIME API (host functions)')
      ..write(apiDocs);
  }

  if (scriptFragments.isNotEmpty) {
    buf.writeln('\n## CURRENT SCRIPT');
    scriptFragments.forEach(buf.writeln);
  }

  return buf.toString();
}

/// Renders one Python-shaped signature line per host function exposed by
/// [extensions], with the description as a trailing `#` comment. Suitable
/// for embedding in an LLM system prompt as a single source of truth for
/// the available API.
String buildHostApiDocs(List<MontyExtension> extensions) {
  if (extensions.isEmpty) return '';
  String pyParamType(HostParamType t) => switch (t) {
    HostParamType.string => 'str',
    HostParamType.integer => 'int',
    HostParamType.number => 'float',
    HostParamType.boolean => 'bool',
    HostParamType.list => 'list',
    HostParamType.map => 'dict',
    HostParamType.any => 'object',
  };
  const returnOverrides = {'el_recv': 'dict'};
  final buf = StringBuffer();
  for (final ext in extensions) {
    for (final fn in ext.functions) {
      final name = fn.schema.name;
      final params = fn.schema.params
          .map((p) => '${p.name}: ${pyParamType(p.type)}')
          .join(', ');
      final ret = returnOverrides[name] ?? 'object';
      final desc = (fn.schema.description ?? '').replaceAll('\n', ' ').trim();
      if (desc.isEmpty) {
        buf.writeln('def $name($params) -> $ret');
      } else {
        buf.writeln('def $name($params) -> $ret  # $desc');
      }
    }
  }

  return buf.toString();
}
