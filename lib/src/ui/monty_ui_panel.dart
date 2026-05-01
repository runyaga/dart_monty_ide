import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/src/bridge/console_svg_host_api.dart';
import 'package:dart_monty_ide/src/ui/svg_preview_panel.dart';
import 'package:flutter/material.dart';

/// A panel that renders a Flutter widget tree emitted by Python via
/// `el_emit(...)` and forwards user events back via
/// `EventLoopExtension.dispatch`. When a [svgHostApi] is supplied, also
/// shows the latest `svg_render(...)` output above the tree.
class MontyUiPanel extends StatefulWidget {
  const MontyUiPanel({
    required this.eventLoop,
    required this.onClose,
    this.svgHostApi,
    super.key,
  });

  final EventLoopExtension eventLoop;
  final VoidCallback onClose;

  /// Optional SVG host api. When non-null, the panel mounts an
  /// [SvgPreviewPanel] above the el_emit tree.
  final ConsoleSvgHostApi? svgHostApi;

  @override
  State<MontyUiPanel> createState() => _MontyUiPanelState();
}

class _MontyUiPanelState extends State<MontyUiPanel> {
  Map<String, Object?>? _tree;
  void Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _attach(widget.eventLoop);
  }

  @override
  void didUpdateWidget(covariant MontyUiPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.eventLoop, widget.eventLoop)) {
      // Reset Interpreter swapped in a fresh EventLoopExtension; re-subscribe
      // and clear the stale tree so the panel goes empty.
      _unsubscribe?.call();
      _attach(widget.eventLoop);
    }
  }

  void _attach(EventLoopExtension ext) {
    _tree = ext.lastEmitted;
    _unsubscribe = ext.lastEmittedSignal.subscribe((value) {
      if (!mounted) return;
      setState(() => _tree = value);
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  void _dispatch(Map<String, Object?> event) {
    try {
      widget.eventLoop.dispatch(event);
    } on StateError catch (e) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Dispatch failed: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          const Divider(height: 1),
          if (widget.svgHostApi != null)
            SvgPreviewPanel(hostApi: widget.svgHostApi!),
          Expanded(
            child: _tree == null
                ? const _EmptyState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _MontyUiRenderer(node: _tree!, dispatch: _dispatch),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).secondaryHeaderColor,
      child: Row(
        children: [
          const Icon(Icons.smart_display, size: 16),
          const SizedBox(width: 6),
          const Text('Monty UI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Send quit event',
            icon: const Icon(Icons.power_settings_new, size: 16),
            onPressed: () => _dispatch({'type': 'quit'}),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Close panel',
            icon: const Icon(Icons.close, size: 16),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bolt, size: 32, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('No UI emitted yet.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              'Run a script that calls el_emit(...) to render here.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Walks the emitted tree and produces Flutter widgets.
///
/// Supported nodes (MVP): text, button, slider, checkbox, text_field,
/// column, row.
class _MontyUiRenderer extends StatelessWidget {
  const _MontyUiRenderer({required this.node, required this.dispatch});

  final Map<String, Object?> node;
  final void Function(Map<String, Object?> event) dispatch;

  @override
  Widget build(BuildContext context) {
    final type = (node['type'] as String?) ?? 'unknown';
    switch (type) {
      case 'text':
        return _buildText();
      case 'button':
        return _buildButton();
      case 'slider':
        return _buildSlider();
      case 'checkbox':
        return _buildCheckbox();
      case 'text_field':
        return _buildTextField();
      case 'column':
        return _buildLinear(Axis.vertical);
      case 'row':
        return _buildLinear(Axis.horizontal);
      default:
        return _buildUnknown(type);
    }
  }

  Widget _buildText() {
    final value = (node['value'] ?? '').toString();
    final size = (node['size'] as num?)?.toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(value, style: TextStyle(fontSize: size)),
    );
  }

  Widget _buildButton() {
    final label = (node['label'] ?? 'Button').toString();
    final id = node['id'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        onPressed: () => dispatch({'type': 'click', 'target': id}),
        child: Text(label),
      ),
    );
  }

  Widget _buildSlider() {
    final id = node['id'];
    final min = (node['min'] as num?)?.toDouble() ?? 0.0;
    final max = (node['max'] as num?)?.toDouble() ?? 100.0;
    final raw = (node['value'] as num?)?.toDouble() ?? min;
    final value = raw.clamp(min, max);
    final label = (node['label'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty) Text('$label: ${value.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
          Slider(
            min: min,
            max: max,
            value: value,
            onChanged: (v) => dispatch({'type': 'change', 'target': id, 'value': v}),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox() {
    final id = node['id'];
    final value = node['value'] == true;
    final label = (node['label'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => dispatch({'type': 'change', 'target': id, 'value': v}),
          ),
          if (label.isNotEmpty) Text(label),
        ],
      ),
    );
  }

  Widget _buildTextField() {
    final id = node['id'];
    final value = (node['value'] ?? '').toString();
    final hint = (node['hint'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: TextEditingController(text: value),
        decoration: InputDecoration(hintText: hint, isDense: true, border: const OutlineInputBorder()),
        onSubmitted: (v) => dispatch({'type': 'submit', 'target': id, 'value': v}),
      ),
    );
  }

  Widget _buildLinear(Axis axis) {
    final raw = node['children'];
    final children = <Widget>[];
    if (raw is List) {
      for (final c in raw) {
        if (c is Map) {
          final childNode = c.map((k, v) => MapEntry(k.toString(), v));
          children.add(_MontyUiRenderer(node: childNode, dispatch: dispatch));
        }
      }
    }
    if (axis == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildUnknown(String type) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '? unknown widget: $type',
        style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic, fontSize: 11),
      ),
    );
  }
}
