import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:flutter/material.dart';

/// A widget that displays the current Python global variables.
class VariableInspector extends StatefulWidget {
  /// Creates a [VariableInspector].
  const VariableInspector({
    required this.controller,
    required this.onClose,
    super.key,
  });

  /// The controller to inspect.
  final MontyIdeController controller;

  /// Callback when the panel should be closed.
  final VoidCallback onClose;

  @override
  State<VariableInspector> createState() => _VariableInspectorState();
}

class _VariableInspectorState extends State<VariableInspector> {
  List<Map<String, String>> _variables = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _refresh();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!widget.controller.isExecuting && widget.controller.isInitialized) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!widget.controller.isInitialized || widget.controller.isExecuting) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      // Introspection script with unique variable names to avoid shadowing
      const script = r'''
[ (k, repr(v), type(v).__name__) for k, v in globals().items() if not k.startswith("_") ]
''';
      final result = await widget.controller.executeSilent(script);
      if (result != null && result.value.dartValue is List) {
        final List<dynamic> list = result.value.dartValue as List<dynamic>;
        final vars = list.map((item) {
          final row = item as List<dynamic>;
          return {
            'name': row[0].toString(),
            'value': row[1].toString(),
            'type': row[2].toString(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            _variables = vars;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: Theme.of(context).secondaryHeaderColor,
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'VARIABLES',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh, size: 16),
                      tooltip: 'Refresh Variables',
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Collapse Variables',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isLoading && _variables.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_variables.isEmpty)
            const Expanded(child: Center(child: Text('No variables', style: TextStyle(fontSize: 11))))
          else
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  columnSpacing: 8,
                  horizontalMargin: 8,
                  dataRowMinHeight: 24,
                  dataRowMaxHeight: 48,
                  headingRowHeight: 28,
                  columns: const [
                    DataColumn(label: Text('Name', style: TextStyle(fontSize: 10))),
                    DataColumn(label: Text('Value', style: TextStyle(fontSize: 10))),
                  ],
                  rows: _variables.map((v) {
                    return DataRow(cells: [
                      DataCell(Text(v['name']!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                      DataCell(Tooltip(
                        message: '${v['type']}: ${v['value']}',
                        child: Text(
                          v['value']!, 
                          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'), 
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
