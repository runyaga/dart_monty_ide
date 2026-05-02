import 'package:flutter/material.dart';
import 'package:hhg_svg_flutter/hhg_svg_flutter.dart';
import 'package:jovial_svg/jovial_svg.dart';

/// Auto-show/auto-hide preview panel for SVG documents emitted via
/// `svg_render(...)` from a `dart_monty` script.
///
/// Subscribes to [FlutterSvgHostApi] (a `ChangeNotifier`) and re-renders
/// whenever the latest SVG changes. Renders via `jovial_svg`'s
/// [ScalableImageWidget], which works on both Flutter native and Flutter
/// web.
///
/// Collapses to zero height when no SVG has been received yet, so it
/// doesn't take up real estate before the user runs a script that
/// emits one.
class SvgPreviewPanel extends StatelessWidget {
  /// Creates a [SvgPreviewPanel].
  const SvgPreviewPanel({required this.hostApi, super.key});

  /// The host api whose [FlutterSvgHostApi.latestImage] this panel
  /// renders. Listened to via `AnimatedBuilder`.
  final FlutterSvgHostApi hostApi;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hostApi,
      builder: (context, _) {
        final si = hostApi.latestImage;
        if (si == null && hostApi.lastError == null) {
          return const SizedBox.shrink();
        }
        final textTheme = Theme.of(context).textTheme;

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          padding: const EdgeInsets.all(8),
          height: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.image_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    hostApi.latestSvg != null
                        ? 'svg_render output  '
                            '(${hostApi.latestSvg!.length} bytes)'
                        : 'svg_render output',
                    style: textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ColoredBox(
                  color: Colors.white,
                  child: hostApi.lastError != null
                      ? _ErrorView(error: hostApi.lastError!)
                      : ScalableImageWidget(si: si!),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Center(
      child: Text(
        'SVG parse error:\n$error',
        style: const TextStyle(
          color: Color(0xFFB71C1C),
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        textAlign: TextAlign.center,
      ),
    ),
  );
}
