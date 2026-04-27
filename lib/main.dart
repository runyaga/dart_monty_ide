import 'dart:async';
import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:dart_monty_ide/src/bridge/flutter_extension.dart';
import 'package:dart_monty_ide/src/bridge/widget_registry.dart';
import 'package:dart_monty_ide/src/vfs/local_vfs.dart';
import 'package:dart_monty_ide/src/vfs/memory_vfs.dart';
import 'package:dart_monty_ide/src/vfs/monty_vfs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MontyVfs vfs;
  if (kIsWeb) {
    vfs = MemoryMontyVfs();
  } else {
    final appDocsDir = await getApplicationDocumentsDirectory();
    final workspacePath = '${appDocsDir.path}/monty_workspace';
    vfs = LocalMontyVfs(rootPath: workspacePath);
  }

  // Setup Flutter Bridge
  final registry = WidgetRegistry();
  final flutterExtension = MontyFlutterExtension(registry);
  final controller = MontyIdeController(extensions: [flutterExtension]);

  // Seed sample files
  await vfs.writeFile(
    'hello.py',
    'def hi(name):\n    return f"hello {name}"\n\nprint(hi("Monty"))\n',
  );

  await vfs.writeFile(
    'gui_demo.py',
    'print("🎨 Updating Flutter widgets...")\n'
        'flutter.set_color("box_1", "teal")\n'
        'flutter.set_prop("label_1", "text", "Updated from Monty Python!")\n'
        'flutter.set_prop("box_1", "size", 120)\n'
        'print("Done.")\n',
  );

  runApp(MyApp(vfs: vfs, controller: controller, registry: registry));
}

/// The main application widget.
class MyApp extends StatelessWidget {
  /// Creates a [MyApp].
  const MyApp({
    required this.vfs,
    required this.controller,
    required this.registry,
    super.key,
  });

  /// The VFS instance.
  final MontyVfs vfs;

  /// The Monty IDE controller.
  final MontyIdeController controller;

  /// The widget registry for the bridge.
  final WidgetRegistry registry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monty IDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MyHomePage(vfs: vfs, controller: controller, registry: registry),
    );
  }
}

/// The home page of the Monty IDE application.
class MyHomePage extends StatelessWidget {
  /// Creates a [MyHomePage].
  const MyHomePage({
    required this.vfs,
    required this.controller,
    required this.registry,
    super.key,
  });

  /// The VFS instance.
  final MontyVfs vfs;

  /// The Monty IDE controller.
  final MontyIdeController controller;

  /// The widget registry for the bridge.
  final WidgetRegistry registry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Monty Python IDE'),
      ),
      body: MontyIde(
        vfs: vfs,
        controller: controller,
        registry: registry,
      ),
    );
  }
}
