import 'package:re_editor/re_editor.dart';

/// A [CodeChunkAnalyzer] that supports both bracket-based folding (via [DefaultCodeChunkAnalyzer])
/// and indentation-based folding for Python.
class PythonCodeChunkAnalyzer implements CodeChunkAnalyzer {
  /// Creates a [PythonCodeChunkAnalyzer].
  const PythonCodeChunkAnalyzer();

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    // 1. Get standard bracket-based chunks
    final chunks = const DefaultCodeChunkAnalyzer().run(codeLines);

    // 2. Add indentation-based chunks
    final indentations = <int>[];
    for (int i = 0; i < codeLines.length; i++) {
      final text = codeLines[i].text;
      if (text.trim().isEmpty) {
        indentations.add(-1); // Mark empty lines
        continue;
      }
      int indent = 0;
      for (final char in text.codeUnits) {
        if (char == ' '.codeUnits.first) {
          indent++;
        } else if (char == '\t'.codeUnits.first) {
          indent += 4; // Assume 4 spaces per tab
        } else {
          break;
        }
      }
      indentations.add(indent);
    }

    for (int i = 0; i < codeLines.length - 1; i++) {
      if (indentations[i] == -1) continue;

      // Find next non-empty line
      int nextNonEmpty = i + 1;
      while (nextNonEmpty < codeLines.length &&
          indentations[nextNonEmpty] == -1) {
        nextNonEmpty++;
      }

      if (nextNonEmpty < codeLines.length &&
          indentations[nextNonEmpty] > indentations[i]) {
        // Potential start of a block
        // Find where it ends: when indentation returns to <= indentations[i]
        int end = nextNonEmpty;
        for (int j = nextNonEmpty + 1; j < codeLines.length; j++) {
          if (indentations[j] == -1) continue;
          if (indentations[j] <= indentations[i]) {
            break;
          }
          end = j;
        }

        if (end > i) {
          // Check if we already have a chunk at this index
          if (chunks.where((e) => e.index == i).isEmpty) {
            chunks.add(CodeChunk(i, end));
          }
        }
      }
    }

    // Sort and return
    chunks.sort((a, b) => a.index.compareTo(b.index));
    return chunks;
  }
}
