import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:flutter/material.dart';

/// A sidebar widget that displays exposed host functions.
class ExternalsInspector extends StatelessWidget {
  /// Creates an [ExternalsInspector].
  const ExternalsInspector({
    required this.controller,
    super.key,
  });

  /// The controller to inspect.
  final MontyIdeController controller;

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
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'EXTERNALS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
                    title: Text(
                      ext.namespace,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    children: ext.functions.map((fn) {
                      return ListTile(
                        title: Text(
                          fn.schema.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
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
