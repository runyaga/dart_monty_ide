import 'package:dart_monty_ide/src/spikes/wind_particle_map_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Spike: wind particles rendered on top of a real flutter_map tile layer.
///
/// Navigate to this page to see particles anchored to the earth:
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => const WindMapDemoPage()));
class WindMapDemoPage extends StatefulWidget {
  /// Creates a [WindMapDemoPage].
  const WindMapDemoPage({super.key});

  @override
  State<WindMapDemoPage> createState() => _WindMapDemoPageState();
}

class _WindMapDemoPageState extends State<WindMapDemoPage> {
  int _particleCount = 400;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wind on map — spike'),
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(29.76, -95.37), // Houston, TX
              initialZoom: 7,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.dartMontyIde',
              ),
              WindParticleLayer(particleCount: _particleCount),
            ],
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Card(
      color: const Color(0xCC0D1117),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              '$_particleCount particles',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            Expanded(
              child: Slider(
                value: _particleCount.toDouble(),
                min: 50,
                max: 1000,
                divisions: 19,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.white24,
                onChanged: (v) =>
                    setState(() => _particleCount = v.toInt()),
              ),
            ),
            const Text(
              '1000',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
