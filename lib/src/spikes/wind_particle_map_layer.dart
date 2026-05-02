import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Spike: Wind particle animation as a `flutter_map` layer.
///
/// Drop this into `FlutterMap(children: [..., WindParticleLayer()])`.
/// Particles live in lat/lon space so they stay anchored to the earth
/// as the map pans and zooms. `MapCamera.of(context)` projects each
/// particle's lat/lon to screen pixels every frame.
///
/// Wind data is a synthetic sinusoidal field for the spike.
/// In production, replace [_WindGrid] with real Open-Meteo data.
class WindParticleLayer extends StatefulWidget {
  /// Creates a [WindParticleLayer].
  const WindParticleLayer({
    this.particleCount = 400,
    this.speedScale = 0.00004,
    super.key,
  });

  /// Number of particles to animate.
  final int particleCount;

  /// How fast particles move in degrees/frame relative to wind speed (m/s).
  final double speedScale;

  @override
  State<WindParticleLayer> createState() => _WindParticleLayerState();
}

class _WindParticleLayerState extends State<WindParticleLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_Particle> _particles = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    // TickerFuture completes when stopped; lifecycle managed via dispose().
    // ignore: discarded_futures
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _ensureParticles(LatLngBounds bounds) {
    if (_initialized && _particles.length == widget.particleCount) return;
    _initialized = true;
    _particles.clear();
    for (var i = 0; i < widget.particleCount; i++) {
      _particles.add(_Particle.random(bounds));
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final bounds = camera.visibleBounds;
    _ensureParticles(bounds);

    return CustomPaint(
      painter: _WindParticleMapPainter(
        camera: camera,
        particles: _particles,
        speedScale: widget.speedScale,
        bounds: bounds,
      ),
      size: camera.nonRotatedSize,
    );
  }
}

// ---------------------------------------------------------------------------
// Painter — projects lat/lon particles to screen each frame
// ---------------------------------------------------------------------------

class _WindParticleMapPainter extends CustomPainter {
  _WindParticleMapPainter({
    required this.camera,
    required this.particles,
    required this.speedScale,
    required this.bounds,
  });

  final MapCamera camera;
  final List<_Particle> particles;
  final double speedScale;
  final LatLngBounds bounds;

  static const _grid = _WindGrid();

  @override
  void paint(Canvas canvas, Size size) {
    // Trail fade.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0D1117).withAlpha(30),
    );

    final paint = Paint()..strokeCap = StrokeCap.round;

    for (final p in particles) {
      final wind = _grid.sample(p.lat, p.lng, bounds);

      // Advance position in degrees.
      p
        ..lat = p.lat + wind.dy * speedScale
        ..lng = p.lng + wind.dx * speedScale;

      // Respawn if out of bounds or aged out.
      p.age++;
      if (p.age > p.maxAge ||
          p.lat < bounds.south ||
          p.lat > bounds.north ||
          p.lng < bounds.west ||
          p.lng > bounds.east) {
        p.reset(bounds);
        continue;
      }

      // Project to screen.
      final screen = camera.latLngToScreenOffset(LatLng(p.lat, p.lng));

      // Color by speed: blue → cyan → green → yellow.
      final speed = wind.distance;
      final t = (speed / 10.0).clamp(0.0, 1.0);
      final r = (t * 100).round();
      final g = (80 + t * 175).round().clamp(0, 255);
      final b = (255 - t * 200).round().clamp(0, 255);
      final alpha = (60 + (p.age / p.maxAge * 160)).round().clamp(0, 220);

      paint
        ..color = Color.fromARGB(alpha, r, g, b)
        ..strokeWidth = 1.8;

      canvas.drawPoints(ui.PointMode.points, [screen], paint);
    }
  }

  @override
  bool shouldRepaint(_WindParticleMapPainter old) => true;
}

// ---------------------------------------------------------------------------
// Synthetic wind grid (replace with real Open-Meteo data in production)
// ---------------------------------------------------------------------------

class _WindGrid {
  const _WindGrid();

  static const int _cols = 12;
  static const int _rows = 10;

  /// Returns a wind vector (dx=east m/s, dy=north m/s) for a lat/lon
  /// normalised to [bounds]. Uses overlapping sine waves to fake a
  /// low-pressure system in the viewport centre.
  ui.Offset sample(double lat, double lng, LatLngBounds bounds) {
    final u = ((lng - bounds.west) / (bounds.east - bounds.west))
        .clamp(0.0, 1.0);
    final v = ((lat - bounds.south) / (bounds.north - bounds.south))
        .clamp(0.0, 1.0);

    // Bilinear sample of a synthetic 12×10 vector grid.
    final gx = u * (_cols - 1);
    final gy = v * (_rows - 1);
    final x0 = gx.floor().clamp(0, _cols - 2);
    final y0 = gy.floor().clamp(0, _rows - 2);
    final tx = gx - x0;
    final ty = gy - y0;

    ui.Offset g(int col, int row) {
      final gu = col / (_cols - 1);
      final gv = row / (_rows - 1);
      final dx =
          5.0 + 3.0 * math.sin(gv * math.pi) +
          2.0 * math.cos(gu * 2 * math.pi);
      final dy =
          2.0 * math.sin(gu * math.pi * 2) - 1.5 * math.cos(gv * math.pi);
      return ui.Offset(dx, dy);
    }

    final top = _lerp(g(x0, y0), g(x0 + 1, y0), tx);
    final bot = _lerp(g(x0, y0 + 1), g(x0 + 1, y0 + 1), tx);
    return _lerp(top, bot, ty);
  }

  static ui.Offset _lerp(ui.Offset a, ui.Offset b, double t) =>
      ui.Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
}

// ---------------------------------------------------------------------------
// Particle — position in lat/lon degrees
// ---------------------------------------------------------------------------

class _Particle {
  _Particle.random(LatLngBounds bounds) {
    reset(bounds);
  }

  static final _rng = math.Random();

  double lat = 0;
  double lng = 0;
  int age = 0;
  int maxAge = 0;

  void reset(LatLngBounds bounds) {
    lat = bounds.south + _rng.nextDouble() * (bounds.north - bounds.south);
    lng = bounds.west + _rng.nextDouble() * (bounds.east - bounds.west);
    age = _rng.nextInt(60);
    maxAge = 80 + _rng.nextInt(140);
  }
}
