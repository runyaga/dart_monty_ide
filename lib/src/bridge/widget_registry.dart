import 'package:flutter/material.dart';

/// A registry that allows Python to interact with Flutter widgets by ID.
class WidgetRegistry extends ChangeNotifier {
  final Map<String, Map<String, dynamic>> _properties = {};

  /// Sets a property for a widget with the given [id].
  void setProperty(String id, String key, dynamic value) {
    _properties.putIfAbsent(id, () => {})[key] = value;
    notifyListeners();
  }

  /// Gets a property for a widget with the given [id].
  dynamic getProperty(String id, String key) {
    return _properties[id]?[key];
  }

  /// Lists all registered widget IDs.
  List<String> get registeredIds => _properties.keys.toList();

  /// Gets all properties for a specific widget ID.
  Map<String, dynamic>? getProperties(String id) => _properties[id];
}

/// A widget that wraps another widget and connects it to the [WidgetRegistry].
class MontyProxyWidget extends StatelessWidget {
  /// Creates a [MontyProxyWidget].
  const MontyProxyWidget({
    required this.id,
    required this.builder,
    required this.registry,
    super.key,
  });

  /// The unique ID for this widget.
  final String id;

  /// The registry to listen to.
  final WidgetRegistry registry;

  /// Builder that receives the current properties for this ID.
  final Widget Function(BuildContext context, Map<String, dynamic> props)
  builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final props = registry.getProperties(id) ?? {};

        return builder(context, props);
      },
    );
  }
}
