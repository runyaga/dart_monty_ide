import 'package:dart_monty_ide/src/bridge/console_svg_host_api.dart';
import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

/// Auto-show/auto-hide preview panel for SVG documents emitted via
/// `svg_render(...)` from a `dart_monty` script.
///
/// Subscribes to [ConsoleSvgHostApi] (which is a `ChangeNotifier`) and
/// re-renders whenever the latest SVG changes. Renders via
/// `jovial_svg`'s `ScalableImageWidget`, which works on both Flutter
/// native and Flutter web.
///
/// Collapses to zero height when no SVG has been received yet, so it
/// doesn't take up real estate before the user runs a script that
/// emits one.
class SvgPreviewPanel extends StatelessWidget {
  /// Creates a [SvgPreviewPanel].
  const SvgPreviewPanel({required this.hostApi, super.key});

  /// The host api whose [ConsoleSvgHostApi.latestSvg] this panel
  /// renders. Listened to via `AnimatedBuilder`.
  final ConsoleSvgHostApi hostApi;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hostApi,
      builder: (context, _) {
        final svg = hostApi.latestSvg;
        if (svg == null) return const SizedBox.shrink();
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
                    'svg_render output  '
                    '(${svg.length} bytes)',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const Spacer(),
                  if (hostApi.latestPath != null)
                    SelectableText(
                      hostApi.latestPath!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ColoredBox(
                  color: Colors.white,
                  child: ScalableImageWidget(
                    si: ScalableImage.fromSvgString(svg),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
