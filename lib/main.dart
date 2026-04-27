import 'package:dart_monty_ide/dart_monty_ide.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

/// The main application widget.
class MyApp extends StatelessWidget {
  /// Creates a [MyApp].
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monty IDE',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

/// The home page of the Monty IDE application.
class MyHomePage extends StatelessWidget {
  /// Creates a [MyHomePage].
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Monty Python IDE'),
      ),
      body: const MontyIde(),
    );
  }
}
