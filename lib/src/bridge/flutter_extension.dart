import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';

/// Extension that allows Python to interact with Flutter widgets.
class MontyFlutterExtension extends MontyExtension {
  /// Creates a [MontyFlutterExtension].
  MontyFlutterExtension(this.registry);

  /// The registry to update.
  final WidgetRegistry registry;

  @override
  String get namespace => 'flutter';

  @override
  List<HostFunction> get functions => [
        HostFunction(
          schema: const HostFunctionSchema(
            name: 'set_prop',
            description: 'Sets a property on a widget with the given ID.',
            params: [
              HostParam(
                name: 'id',
                type: HostParamType.string,
                description: 'The unique ID of the widget.',
              ),
              HostParam(
                name: 'key',
                type: HostParamType.string,
                description: 'The property name (e.g., "color", "text").',
              ),
              HostParam(
                name: 'value',
                type: HostParamType.any,
                description: 'The value to set.',
              ),
            ],
          ),
          handler: (args, ctx) async {
            final id = args['id'] as String;
            final key = args['key'] as String;
            final value = args['value'];
            registry.setProperty(id, key, value);
            return null;
          },
        ),
        HostFunction(
          schema: const HostFunctionSchema(
            name: 'get_prop',
            description: 'Gets a property from a widget with the given ID.',
            params: [
              HostParam(
                name: 'id',
                type: HostParamType.string,
                description: 'The unique ID of the widget.',
              ),
              HostParam(
                name: 'key',
                type: HostParamType.string,
                description: 'The property name.',
              ),
            ],
          ),
          handler: (args, ctx) async {
            final id = args['id'] as String;
            final key = args['key'] as String;
            return registry.getProperty(id, key);
          },
        ),
        HostFunction(
          schema: const HostFunctionSchema(
            name: 'set_color',
            description: 'Convenience helper to set a widget color.',
            params: [
              HostParam(
                name: 'id',
                type: HostParamType.string,
              ),
              HostParam(
                name: 'color',
                type: HostParamType.string,
                description: 'Color name (red, blue, green, etc.)',
              ),
            ],
          ),
          handler: (args, ctx) async {
            final id = args['id'] as String;
            final color = args['color'] as String;
            registry.setProperty(id, 'color', color);
            return null;
          },
        ),
      ];
}
