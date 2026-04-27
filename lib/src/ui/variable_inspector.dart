import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:flutter/material.dart';

/// A widget that displays the current Python global variables.
class VariableInspector extends StatefulWidget {
  /// Creates a [VariableInspector].
  const VariableInspector({
    required this.controller,
    super.key,
  });

  /// The controller to inspect.
  final MontyIdeController controller;

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
      const script = '''
[ (_ide_k, repr(_ide_v), type(_ide_v).__name__) for _ide_k, _ide_v in globals().items() if not _ide_k.startswith("__") ]
''';
      final result = await widget.controller.executeSilent(script);
      if (result != null && result.value is List) {
        final List<dynamic> list = result.value as List<dynamic>;
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
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'VARIABLES',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                ),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  tooltip: 'Refresh Variables',
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
                  dataRowMaxHeight: 32,
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
                        child: Text(v['value']!, style: const TextStyle(fontSize: 10, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
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
