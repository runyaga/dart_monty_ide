import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:flutter/material.dart';

/// A sidebar widget that displays exposed host functions with their arguments.
class ExternalsInspector extends StatelessWidget {
  /// Creates an [ExternalsInspector].
  const ExternalsInspector({
    required this.controller,
    required this.onClose,
    super.key,
  });

  /// The controller to inspect.
  final MontyIdeController controller;

  /// Callback when the panel should be closed.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final extensions = controller.extensions ?? [];

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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'EXTERNALS',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Collapse Externals',
                  ),
                ],
              ),
            ),
          ),
          if (extensions.isEmpty)
            const Expanded(child: Center(child: Text('No extensions')))
          else
            Expanded(
              child: ListView.builder(
                itemCount: extensions.length,
                itemBuilder: (context, index) {
                  final ext = extensions[index];
                  return ExpansionTile(
                    initiallyExpanded: true,
                    title: Text(
                      ext.namespace.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    children: ext.functions.map((fn) {
                      final args =
                          fn.schema.params.map((p) => p.name).join(', ');
                      return ListTile(
                        title: Text(
                          '${fn.schema.name}($args)',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: fn.schema.description != null
                            ? Text(
                                fn.schema.description!,
                                style: const TextStyle(fontSize: 10),
                              )
                            : null,
                        dense: true,
                      );
                    }).toList(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
