import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';

/// Extension that allows Python to interact with Flutter widgets.
/// Monty does not support modules, so functions are exposed as
/// flutter_set_prop(), etc.
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
            name: 'flutter_set_prop',
            description: 'Sets a property on a widget with the given ID.',
            params: [
              HostParam(
                name: 'id',
                type: HostParamType.string,
              ),
              HostParam(
                name: 'key',
                type: HostParamType.string,
              ),
              HostParam(
                name: 'value',
                type: HostParamType.any,
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
            name: 'flutter_get_prop',
            description: 'Gets a property from a widget with the given ID.',
            params: [
              HostParam(
                name: 'id',
                type: HostParamType.string,
              ),
              HostParam(
                name: 'key',
                type: HostParamType.string,
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
            name: 'flutter_set_color',
            description: 'Convenience helper to set a widget color.',
            params: [
              HostParam(
                name: 'id',
                type: HostParamType.string,
              ),
              HostParam(
                name: 'color',
                type: HostParamType.string,
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
