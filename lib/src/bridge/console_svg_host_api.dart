import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:hhg_svg/hhg_svg.dart';

/// `SvgHostApi` impl for the IDE.
///
/// On native: writes the rendered SVG to a fixed temp file
/// (`<systemTemp>/dart_monty_ide_render.svg`) and prints the path
/// to the IDE console along with an `open "<path>"` shortcut, so the
/// user can preview in their default SVG viewer / browser without
/// the IDE needing an in-app renderer.
///
/// On web: filesystem isn't available, so we fall back to a one-line
/// console preview (size + first 60 chars).
///
/// In both cases the host api is a [ChangeNotifier] exposing
/// [latestSvg] / [latestPath], so a future in-app preview widget
/// (e.g. one mounting `ScalableImageWidget` from `jovial_svg`) can
/// subscribe and paint without any change to the script-side
/// contract.
class ConsoleSvgHostApi extends ChangeNotifier implements SvgHostApi {
  /// Creates a [ConsoleSvgHostApi].
  ///
  /// `appendOutput` receives the per-render console line(s).
  /// [outputPath] overrides the on-disk write target. Defaults to
  /// `<systemTemp>/dart_monty_ide_render.svg` on native; ignored on
  /// web.
  ConsoleSvgHostApi(this._appendOutput, {String? outputPath})
    : _outputPath = outputPath;

  final void Function(String line) _appendOutput;
  final String? _outputPath;

  /// Most recently rendered SVG document, or `null` if none yet.
  String? get latestSvg => _latest;
  String? _latest;

  /// Path to the on-disk file the last render was written to, or
  /// `null` (web, or the very first render hasn't happened yet).
  String? get latestPath => _latestPath;
  String? _latestPath;

  @override
  Future<void> render(String svg) async {
    _latest = svg;
    if (kIsWeb) {
      _writeConsolePreviewOnly(svg);
    } else {
      await _writeToFile(svg);
    }
    notifyListeners();
  }

  Future<void> _writeToFile(String svg) async {
    final path =
        _outputPath ?? '${Directory.systemTemp.path}/dart_monty_ide_render.svg';
    try {
      await File(path).writeAsString(svg);
      _latestPath = path;
      _appendOutput('🖼️  svg_render: ${svg.length} bytes → $path');
      _appendOutput('   open "$path"');
    } on Object catch (e) {
      _writeConsolePreviewOnly(svg);
      _appendOutput('   (file write failed: $e)');
    }
  }

  void _writeConsolePreviewOnly(String svg) {
    final preview = svg.length <= 60
        ? svg.replaceAll('\n', ' ')
        : '${svg.substring(0, 60).replaceAll('\n', ' ')}…';
    _appendOutput(
      '🖼️  svg_render: ${svg.length} bytes  $preview',
    );
  }
}
