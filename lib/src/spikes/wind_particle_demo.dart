import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Spike: Wind particle animation performance test.
///
/// Shows an animated particle field driven by a hardcoded sinusoidal wind
/// grid — no HTTP, no map. Lets us measure the particle-count threshold
/// before frame time exceeds 16 ms (60 fps).
///
/// Navigate to this screen from main during spiking:
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => const WindParticleDemoPage()));
class WindParticleDemoPage extends StatefulWidget {
  /// Creates a [WindParticleDemoPage].
  const WindParticleDemoPage({super.key});

  @override
  State<WindParticleDemoPage> createState() => _WindParticleDemoPageState();
}

class _WindParticleDemoPageState extends State<WindParticleDemoPage>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  int _particleCount = 300;
  bool _running = true;

  // FPS tracking
  final List<double> _frameTimes = [];
  double _fps = 0;
  double _frameMs = 0;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // TickerFuture completes when stopped; we manage lifecycle via dispose().
    // ignore: discarded_futures
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    if (_lastTick != Duration.zero) {
      final dtMs = (elapsed - _lastTick).inMicroseconds / 1000;
      _frameTimes.add(dtMs);
      if (_frameTimes.length > 60) _frameTimes.removeAt(0);
      final avg =
          _frameTimes.fold<double>(0, (a, b) => a + b) / _frameTimes.length;
      _fps = avg > 0 ? 1000 / avg : 0.0;
      _frameMs = avg;
    }
    _lastTick = elapsed;
    setState(() {}); // trigger repaint
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        title: const Text(
          'Wind particle spike',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ClipRect(
              child: CustomPaint(
                painter: _WindParticlePainter(
                  particleCount: _particleCount,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final fpsColor = _fps >= 55
        ? Colors.greenAccent
        : _fps >= 30
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${_fps.toStringAsFixed(1)} fps  '
                '(${_frameMs.toStringAsFixed(1)} ms/frame)',
                style: TextStyle(
                  color: fpsColor,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '$_particleCount particles',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          Row(
            children: [
              const Text(
                '50',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              Expanded(
                child: Slider(
                  value: _particleCount.toDouble(),
                  min: 50,
                  max: 1000,
                  divisions: 19,
                  activeColor: Colors.cyanAccent,
                  inactiveColor: Colors.white12,
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
          Row(
            children: [
              _chip('100', 100),
              _chip('300', 300),
              _chip('500', 500),
              _chip('750', 750),
              _chip('1000', 1000),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    setState(() => _running = !_running),
                child: Text(
                  _running ? 'Pause' : 'Resume',
                  style: const TextStyle(color: Colors.cyanAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '≥55 fps = green  ≥30 = orange  <30 = red  '
            '(threshold: 16 ms / frame for 60 fps)',
            style: TextStyle(
              color: Colors.white.withAlpha(100),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int count) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: _particleCount == count
          ? Colors.cyanAccent.withAlpha(60)
          : Colors.white10,
      side: BorderSide(
        color: _particleCount == count ? Colors.cyanAccent : Colors.white12,
      ),
      labelStyle: TextStyle(
        color: _particleCount == count ? Colors.cyanAccent : Colors.white60,
      ),
      onPressed: () => setState(() => _particleCount = count),
    ),
  );
}

// ---------------------------------------------------------------------------
// Particle painter
// ---------------------------------------------------------------------------

class _WindParticlePainter extends CustomPainter {
  _WindParticlePainter({required this.particleCount});

  final int particleCount;

  // Particles are allocated lazily on first paint and reused across frames.
  static final List<_Particle> _particles = [];
  static Size _lastSize = Size.zero;

  // How fast wall-clock time maps to animation speed.
  static const double _speedScale = 0.06;

  // Wind grid resolution (synthetic sinusoidal field).
  static const int _gridW = 12;
  static const int _gridH = 10;

  // Pre-computed grid vectors (filled on first paint / resize).
  static final List<ui.Offset> _grid = [];
  static bool _gridDirty = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (size != _lastSize) {
      _lastSize = size;
      _gridDirty = true;
    }

    if (_gridDirty) {
      _buildGrid(size);
      _gridDirty = false;
    }

    // Ensure particle list matches requested count.
    while (_particles.length < particleCount) {
      _particles.add(_Particle.random(size));
    }
    while (_particles.length > particleCount) {
      _particles.removeLast();
    }

    // Fade trail: draw a semi-transparent rect over the previous frame.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0D1117).withAlpha(38),
    );

    final dotPaint = Paint()..strokeCap = StrokeCap.round;

    for (final p in _particles) {
      // Sample wind vector at particle position via bilinear interpolation.
      final wind = _sampleGrid(p.x / size.width, p.y / size.height);
      p
        ..x = p.x + wind.dx * _speedScale
        ..y = p.y + wind.dy * _speedScale;

      // Wrap edges.
      if (p.x < 0) p.x += size.width;
      if (p.x > size.width) p.x -= size.width;
      if (p.y < 0) p.y += size.height;
      if (p.y > size.height) p.y -= size.height;

      p.age++;
      if (p.age > p.maxAge) {
        p.reset(size);
      }

      // Color by speed magnitude: blue → cyan → green → yellow.
      final speed = wind.distance;
      final t = (speed / 8.0).clamp(0.0, 1.0);
      final r = (t * 100).round();
      final g = (80 + t * 175).round().clamp(0, 255);
      final b = (255 - t * 180).round().clamp(0, 255);
      final alpha = (80 + (p.age / p.maxAge * 140)).round().clamp(0, 220);

      dotPaint
        ..color = Color.fromARGB(alpha, r, g, b)
        ..strokeWidth = 1.5;

      canvas.drawPoints(
        ui.PointMode.points,
        [Offset(p.x, p.y)],
        dotPaint,
      );
    }
  }

  // Build a synthetic wind vector grid using overlapping sine waves.
  static void _buildGrid(Size size) {
    _grid.clear();
    for (var row = 0; row < _gridH; row++) {
      for (var col = 0; col < _gridW; col++) {
        final u = col / (_gridW - 1); // 0..1 normalised x
        final v = row / (_gridH - 1); // 0..1 normalised y
        // Fake wind: westerly base + a low-pressure curl in the centre.
        final dx =
            5.0 + 3.0 * math.sin(v * math.pi) + 2.0 * math.cos(u * 2 * math.pi);
        final dy =
            2.0 * math.sin(u * math.pi * 2) - 1.5 * math.cos(v * math.pi);
        _grid.add(ui.Offset(dx, dy));
      }
    }
  }

  // Bilinear interpolation into the grid (normalised 0..1 coordinates).
  static ui.Offset _sampleGrid(double u, double v) {
    final gx = (u * (_gridW - 1)).clamp(0.0, _gridW - 1.0);
    final gy = (v * (_gridH - 1)).clamp(0.0, _gridH - 1.0);
    final x0 = gx.floor().clamp(0, _gridW - 2);
    final y0 = gy.floor().clamp(0, _gridH - 2);
    final tx = gx - x0;
    final ty = gy - y0;

    ui.Offset g(int col, int row) => _grid[row * _gridW + col];

    final top = _lerp(g(x0, y0), g(x0 + 1, y0), tx);
    final bot = _lerp(g(x0, y0 + 1), g(x0 + 1, y0 + 1), tx);
    return _lerp(top, bot, ty);
  }

  static ui.Offset _lerp(ui.Offset a, ui.Offset b, double t) =>
      ui.Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);

  @override
  bool shouldRepaint(_WindParticlePainter old) => true;
}

// ---------------------------------------------------------------------------
// Particle state
// ---------------------------------------------------------------------------

class _Particle {
  _Particle.random(Size size) {
    reset(size);
  }

  static final _rng = math.Random();

  double x = 0;
  double y = 0;
  int age = 0;
  int maxAge = 0;

  void reset(Size size) {
    x = _rng.nextDouble() * size.width;
    y = _rng.nextDouble() * size.height;
    age = _rng.nextInt(60);
    maxAge = 80 + _rng.nextInt(120);
  }
}
