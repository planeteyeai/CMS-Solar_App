import 'dart:convert';
import 'dart:math' as math;

/// Pure-Dart geometry helpers (no Flutter imports, easy to unit test).
///
/// A site boundary is GeoJSON in [lon, lat] order: Polygon, MultiPolygon, Feature,
/// FeatureCollection or GeometryCollection.
class GeoPolygon {
  /// Ring 0 is the outer boundary, any further rings are holes.
  /// Each point is [lon, lat].
  final List<List<List<double>>> rings;
  const GeoPolygon(this.rings);
}

class SiteGeometry {
  final List<GeoPolygon> polygons;
  const SiteGeometry(this.polygons);

  bool get isEmpty => polygons.isEmpty;

  /// Parses a GeoJSON string/map. Returns null when nothing usable is found.
  static SiteGeometry? fromGeoJson(dynamic input) {
    dynamic data = input;
    if (data is String) {
      if (data.trim().isEmpty) return null;
      try {
        data = jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    final polys = <GeoPolygon>[];
    _collect(data, polys);
    return polys.isEmpty ? null : SiteGeometry(polys);
  }

  static void _collect(dynamic node, List<GeoPolygon> out) {
    if (node is! Map) return;
    switch (node['type']) {
      case 'Polygon':
        final p = _polygon(node['coordinates']);
        if (p != null) out.add(p);
        break;
      case 'MultiPolygon':
        final c = node['coordinates'];
        if (c is List) {
          for (final poly in c) {
            final p = _polygon(poly);
            if (p != null) out.add(p);
          }
        }
        break;
      case 'Feature':
        _collect(node['geometry'], out);
        break;
      case 'FeatureCollection':
        final f = node['features'];
        if (f is List) {
          for (final e in f) {
            _collect(e, out);
          }
        }
        break;
      case 'GeometryCollection':
        final g = node['geometries'];
        if (g is List) {
          for (final e in g) {
            _collect(e, out);
          }
        }
        break;
    }
  }

  static GeoPolygon? _polygon(dynamic coords) {
    if (coords is! List) return null;
    final rings = <List<List<double>>>[];
    for (final r in coords) {
      if (r is! List) continue;
      final ring = <List<double>>[];
      for (final pt in r) {
        if (pt is List && pt.length >= 2 && pt[0] is num && pt[1] is num) {
          ring.add([(pt[0] as num).toDouble(), (pt[1] as num).toDouble()]);
        }
      }
      if (ring.length >= 3) rings.add(ring);
    }
    return rings.isEmpty ? null : GeoPolygon(rings);
  }

  /// Distance in metres from ([lat], [lon]) to the site: 0 when the point is inside
  /// (or on the boundary), otherwise the shortest distance to the boundary.
  double distanceMeters(double lat, double lon) {
    var best = double.infinity;
    for (final p in polygons) {
      final d = _polygonDistance(p, lat, lon);
      if (d < best) best = d;
      if (best == 0) return 0;
    }
    return best;
  }

  static double _polygonDistance(GeoPolygon poly, double lat, double lon) {
    // Local flat projection centred on the query point (accurate for site-sized areas).
    final mLat = 111320.0;
    final mLon = 111320.0 * math.cos(lat * math.pi / 180.0);
    List<List<double>> project(List<List<double>> ring) => [
          for (final p in ring) [(p[0] - lon) * mLon, (p[1] - lat) * mLat]
        ];

    final outer = project(poly.rings.first);
    if (!_originInside(outer)) {
      return _distanceToRing(outer);
    }
    // Inside the outer ring: check holes.
    for (var i = 1; i < poly.rings.length; i++) {
      final hole = project(poly.rings[i]);
      if (_originInside(hole)) return _distanceToRing(hole);
    }
    return 0;
  }

  /// Ray casting with the query point at the origin.
  static bool _originInside(List<List<double>> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i][0], yi = ring[i][1];
      final xj = ring[j][0], yj = ring[j][1];
      if ((yi > 0) != (yj > 0)) {
        final xCross = (xj - xi) * (0 - yi) / (yj - yi) + xi;
        if (0 < xCross) inside = !inside;
      }
    }
    return inside;
  }

  static double _distanceToRing(List<List<double>> ring) {
    var best = double.infinity;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final d = _originToSegment(ring[j][0], ring[j][1], ring[i][0], ring[i][1]);
      if (d < best) best = d;
    }
    return best;
  }

  static double _originToSegment(double ax, double ay, double bx, double by) {
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return math.sqrt(ax * ax + ay * ay);
    var t = -(ax * dx + ay * dy) / len2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final px = ax + t * dx, py = ay + t * dy;
    return math.sqrt(px * px + py * py);
  }
}
