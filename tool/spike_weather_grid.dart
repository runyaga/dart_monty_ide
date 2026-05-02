// Spike: Open-Meteo wind grid — viewport-bounded fetch with tile cache.
//
// Models the real usage pattern:
//   1. Map has a visible bounding box.
//   2. We sample a coarse grid over that box at `step` degree intervals.
//   3. Grid cells already in the cache are skipped — only misses hit the API.
//   4. When the map pans, the new viewport overlaps the old one;
//      the overlap is served from cache, only new cells are fetched.
//
// Fetches ONLY wind_speed_10m + wind_direction_10m (not temp/pressure).
//
// Run from the repo root:
//   dart run tool/spike_weather_grid.dart
//   dart run tool/spike_weather_grid.dart --step=0.5 --pans=5
//
// Options:
//   --lat=<f>    Centre latitude  (default: 51.5, London)
//   --lon=<f>    Centre longitude (default: -0.1)
//   --span=<f>   Half-width of viewport in degrees (default: 2.0)
//   --step=<f>   Grid cell size in degrees (default: 0.5)
//   --pans=<n>   Number of simulated eastward pans (default: 3)
//   --pan-dx=<f> Longitude shift per pan in degrees (default: 1.0)

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final cfg = _parseArgs(args);
  final cache = _WindCache();
  final client = http.Client();

  print('Open-Meteo wind grid spike — viewport-bounded + cache');
  print(
    'Centre: (${cfg.lat.toStringAsFixed(2)}, ${cfg.lon.toStringAsFixed(2)})  '
    'span: ±${cfg.span}°  step: ${cfg.step}°  '
    'pans: ${cfg.pans} × Δlon=${cfg.panDx}°',
  );
  print('');

  try {
    for (var pan = 0; pan <= cfg.pans; pan++) {
      final centerLon = cfg.lon + pan * cfg.panDx;
      final box = _BBox(
        minLat: cfg.lat - cfg.span,
        maxLat: cfg.lat + cfg.span,
        minLon: centerLon - cfg.span,
        maxLon: centerLon + cfg.span,
      );
      await _fetchViewport(client, cache, box, cfg.step, pan);
    }

    print('');
    print('─' * 60);
    print('Cache summary: ${cache.size} grid cells stored.');
    print(
      'Each cell key = (lat rounded to ${cfg.step}°, '
      'lon rounded to ${cfg.step}°).',
    );
    print(
      'On a real device, these survive map pans — only cells '
      'scrolled into view trigger new requests.',
    );
  } finally {
    client.close();
  }
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

class _Cfg {
  const _Cfg({
    required this.lat,
    required this.lon,
    required this.span,
    required this.step,
    required this.pans,
    required this.panDx,
  });
  final double lat;
  final double lon;
  final double span;
  final double step;
  final int pans;
  final double panDx;
}

_Cfg _parseArgs(List<String> args) {
  var lat = 51.5;
  var lon = -0.1;
  var span = 2.0;
  var step = 0.5;
  var pans = 3;
  var panDx = 1.0;

  for (final a in args) {
    if (a.startsWith('--lat=')) lat = double.parse(a.substring(6));
    if (a.startsWith('--lon=')) lon = double.parse(a.substring(6));
    if (a.startsWith('--span=')) span = double.parse(a.substring(7));
    if (a.startsWith('--step=')) step = double.parse(a.substring(7));
    if (a.startsWith('--pans=')) pans = int.parse(a.substring(7));
    if (a.startsWith('--pan-dx=')) panDx = double.parse(a.substring(9));
  }

  return _Cfg(
    lat: lat,
    lon: lon,
    span: span,
    step: step,
    pans: pans,
    panDx: panDx,
  );
}

// ---------------------------------------------------------------------------
// Bounding box
// ---------------------------------------------------------------------------

class _BBox {
  const _BBox({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  List<(double, double)> gridPoints(double step) {
    final pts = <(double, double)>[];
    var lat = (minLat / step).ceil() * step;
    while (lat <= maxLat) {
      var lon = (minLon / step).ceil() * step;
      while (lon <= maxLon) {
        pts.add((_snap(lat, step), _snap(lon, step)));
        lon += step;
      }
      lat += step;
    }
    return pts;
  }

  // Round to nearest step to ensure consistent cell keys.
  static double _snap(double v, double step) =>
      (v / step).round() * step;
}

// ---------------------------------------------------------------------------
// Wind cache — keyed on snapped (lat, lon) cell coordinates
// ---------------------------------------------------------------------------

class _WindCache {
  final Map<(double, double), _WindVector> _store = {};

  bool has(double lat, double lon) => _store.containsKey((lat, lon));

  void put(double lat, double lon, _WindVector v) =>
      _store[(lat, lon)] = v;

  _WindVector? get(double lat, double lon) => _store[(lat, lon)];

  int get size => _store.length;
}

class _WindVector {
  const _WindVector({required this.speedMs, required this.directionDeg});
  final double speedMs;
  final double directionDeg; // meteorological: from which direction wind blows
}

// ---------------------------------------------------------------------------
// Viewport fetch
// ---------------------------------------------------------------------------

Future<void> _fetchViewport(
  http.Client client,
  _WindCache cache,
  _BBox box,
  double step,
  int panIndex,
) async {
  final all = box.gridPoints(step);
  final misses = all.where((p) => !cache.has(p.$1, p.$2)).toList();
  final hits = all.length - misses.length;

  print(
    'Pan $panIndex — viewport '
    '[${box.minLat.toStringAsFixed(1)}, ${box.minLon.toStringAsFixed(1)}] → '
    '[${box.maxLat.toStringAsFixed(1)}, ${box.maxLon.toStringAsFixed(1)}]',
  );
  print(
    '  grid: ${all.length} points  '
    'cache hits: $hits  '
    'fetching: ${misses.length}',
  );

  if (misses.isEmpty) {
    print('  → Fully served from cache. No HTTP requests.\n');
    return;
  }

  final wallStart = DateTime.now().millisecondsSinceEpoch;
  final futures = misses.map((p) => _fetchPoint(client, p.$1, p.$2));
  final results = await Future.wait(futures);
  final wallMs = DateTime.now().millisecondsSinceEpoch - wallStart;

  var ok = 0;
  var failed = 0;
  for (final r in results) {
    if (r.vector != null) {
      cache.put(r.lat, r.lon, r.vector!);
      ok++;
    } else {
      failed++;
    }
  }

  final latencies = results.map((r) => r.latencyMs).toList()..sort();
  final p50 = latencies[latencies.length ~/ 2];
  final p90 =
      latencies[(latencies.length * 0.9).floor().clamp(0, latencies.length - 1)];

  print(
    '  → Fetched $ok ok  $failed failed  '
    'wall: ${wallMs}ms  p50: ${p50}ms  p90: ${p90}ms',
  );

  if (results.isNotEmpty) {
    final sample = results.firstWhere(
      (r) => r.vector != null,
      orElse: () => results.first,
    );
    if (sample.vector != null) {
      print(
        '  sample (${sample.lat.toStringAsFixed(2)}, '
        '${sample.lon.toStringAsFixed(2)}): '
        '${sample.vector!.speedMs.toStringAsFixed(1)} m/s  '
        '${sample.vector!.directionDeg.toStringAsFixed(0)}°',
      );
    }
  }

  _printVerdictLine(misses.length, wallMs, p50, p90);
  print('');
}

void _printVerdictLine(int n, int wallMs, int p50, int p90) {
  final msPerPoint = n > 0 ? wallMs ~/ n : 0;
  final verdict = wallMs < 1200
      ? '✓ under 1.2 s'
      : wallMs < 3000
          ? '~ acceptable with spinner'
          : '✗ too slow — reduce step size';
  print('  $verdict  ($n calls, ~$msPerPoint ms/call, p90=${p90}ms)');
}

// ---------------------------------------------------------------------------
// Single-point fetch — wind only
// ---------------------------------------------------------------------------

class _FetchResult {
  _FetchResult({
    required this.lat,
    required this.lon,
    required this.latencyMs,
    this.vector,
    this.error,
  });
  final double lat;
  final double lon;
  final int latencyMs;
  final _WindVector? vector;
  final String? error;
}

Future<_FetchResult> _fetchPoint(
  http.Client client,
  double lat,
  double lon,
) async {
  final url = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=${lat.toStringAsFixed(4)}'
    '&longitude=${lon.toStringAsFixed(4)}'
    '&current=wind_speed_10m,wind_direction_10m'
    '&timezone=auto',
  );

  final t0 = DateTime.now().millisecondsSinceEpoch;
  try {
    final resp = await client
        .get(url)
        .timeout(const Duration(seconds: 12));
    final ms = DateTime.now().millisecondsSinceEpoch - t0;

    if (resp.statusCode != 200) {
      return _FetchResult(
        lat: lat,
        lon: lon,
        latencyMs: ms,
        error: 'HTTP ${resp.statusCode}',
      );
    }

    final body = jsonDecode(resp.body) as Map<String, Object?>;
    final current = body['current'] as Map<String, Object?>? ?? {};
    final speed = (current['wind_speed_10m'] as num?)?.toDouble();
    final dir = (current['wind_direction_10m'] as num?)?.toDouble();

    if (speed == null || dir == null) {
      return _FetchResult(
        lat: lat,
        lon: lon,
        latencyMs: ms,
        error: 'missing fields',
      );
    }

    return _FetchResult(
      lat: lat,
      lon: lon,
      latencyMs: ms,
      vector: _WindVector(speedMs: speed, directionDeg: dir),
    );
  } on TimeoutException {
    return _FetchResult(
      lat: lat,
      lon: lon,
      latencyMs: DateTime.now().millisecondsSinceEpoch - t0,
      error: 'timeout',
    );
  } on Exception catch (e) {
    return _FetchResult(
      lat: lat,
      lon: lon,
      latencyMs: DateTime.now().millisecondsSinceEpoch - t0,
      error: e.toString(),
    );
  }
}
