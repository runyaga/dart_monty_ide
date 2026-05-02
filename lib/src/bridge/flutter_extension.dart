import 'dart:math' as math;
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';

/// Extension that allows Python to interact with Flutter widgets.
class MontyFlutterExtension extends MontyExtension {
  /// Creates a [MontyFlutterExtension].
  MontyFlutterExtension(this.registry);

  /// The registry to update.
  final WidgetRegistry registry;
  final math.Random _random = math.Random();

  @override
  String get namespace => 'flutter';

  @override
  List<HostFunction> get functions => [
    HostFunction(
      schema: const HostFunctionSchema(
        name: 'flutter_set_prop',
        description: 'Sets a property on a widget with the given ID.',
        params: [
          HostParam(name: 'id', type: HostParamType.string),
          HostParam(name: 'key', type: HostParamType.string),
          HostParam(name: 'value', type: HostParamType.any),
        ],
      ),
      handler: (args, ctx) async {
        final id = args['id'] as String? ?? '';
        final key = args['key'] as String? ?? '';
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
          HostParam(name: 'id', type: HostParamType.string),
          HostParam(name: 'key', type: HostParamType.string),
        ],
      ),
      handler: (args, ctx) async {
        final id = args['id'] as String? ?? '';
        final key = args['key'] as String? ?? '';

        return registry.getProperty(id, key);
      },
    ),
    HostFunction(
      schema: const HostFunctionSchema(
        name: 'flutter_set_color',
        description: 'Convenience helper to set a widget color.',
        params: [
          HostParam(name: 'id', type: HostParamType.string),
          HostParam(name: 'color', type: HostParamType.string),
        ],
      ),
      handler: (args, ctx) async {
        final id = args['id'] as String? ?? '';
        final color = args['color'] as String? ?? '';
        registry.setProperty(id, 'color', color);

        return null;
      },
    ),
    HostFunction(
      schema: const HostFunctionSchema(
        name: 'flutter_randint',
        description:
            'Returns a random integer N such that a <= N <= b. '
            'Identical to random.randint(a, b).',
        params: [
          HostParam(name: 'a', type: HostParamType.number),
          HostParam(name: 'b', type: HostParamType.number),
        ],
      ),
      handler: (args, ctx) async {
        final aValue = args['a'];
        final bValue = args['b'];
        final a = (aValue is num) ? aValue.toInt() : 0;
        final b = (bValue is num) ? bValue.toInt() : 0;
        if (b <= a) return a;

        return a + _random.nextInt(b - a + 1);
      },
    ),
    HostFunction(
      schema: const HostFunctionSchema(
        name: 'flutter_shuffle',
        description: 'Shuffles a list of items and returns a new list.',
        params: [
          HostParam(name: 'items', type: HostParamType.list),
        ],
      ),
      handler: (args, ctx) async {
        final itemsValue = args['items'];
        final items = itemsValue is Iterable
            ? List<Object?>.from(itemsValue)
            : <Object?>[];

        return items..shuffle(_random);
      },
    ),
  ];
}
