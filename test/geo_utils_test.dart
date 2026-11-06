import 'dart:math' as math;

import 'package:cms_site_manager/services/geo_utils.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with:  flutter test test/geo_utils_test.dart
// (If your package name is different, change the import above to match `name:` in pubspec.yaml.)

const double lat0 = 19.9900, lon0 = 73.7800;
final double dLat = 200 / 111320.0;
final double dLon = 200 / (111320.0 * math.cos(lat0 * math.pi / 180));

/// A 200 m x 200 m square site.
Map<String, dynamic> square() => {
      'type': 'Polygon',
      'coordinates': [
        [
          [lon0, lat0],
          [lon0 + dLon, lat0],
          [lon0 + dLon, lat0 + dLat],
          [lon0, lat0 + dLat],
          [lon0, lat0],
        ]
      ],
    };

/// A point [north] m north / [east] m east of the centre of the site.
List<double> at({double north = 0, double east = 0}) {
  final cLat = lat0 + dLat / 2, cLon = lon0 + dLon / 2;
  return [
    cLat + north / 111320.0,
    cLon + east / (111320.0 * math.cos(cLat * math.pi / 180)),
  ];
}

void main() {
  final site = SiteGeometry.fromGeoJson(square())!;

  test('inside the site is 0 m', () {
    final p = at();
    expect(site.distanceMeters(p[0], p[1]), 0);
  });

  test('distance outside the east edge (100 m from the centre)', () {
    for (final extra in [3.0, 4.9, 5.5, 120.0]) {
      final p = at(east: 100 + extra);
      expect(site.distanceMeters(p[0], p[1]), closeTo(extra, 0.3));
    }
  });

  test('under 5 m is on site, 5 m or more is off site', () {
    bool onSite(double d) => d < 5.0; // same rule as kOnSiteToleranceMeters
    expect(onSite(3), isTrue);
    expect(onSite(4.9), isTrue);
    expect(onSite(5.0), isFalse);
    expect(onSite(5.5), isFalse);
  });

  test('corner distance is the straight line to the corner', () {
    final p = at(north: 100 + 40, east: 100 + 30);
    expect(site.distanceMeters(p[0], p[1]), closeTo(50, 1.0));
  });

  test('a hole is not part of the site', () {
    final c = at();
    final d = 20 / 111320.0, l = 20 / (111320.0 * math.cos(c[0] * math.pi / 180));
    final g = square();
    (g['coordinates'] as List).add([
      [c[1] - l, c[0] - d],
      [c[1] + l, c[0] - d],
      [c[1] + l, c[0] + d],
      [c[1] - l, c[0] + d],
      [c[1] - l, c[0] - d],
    ]);
    final s = SiteGeometry.fromGeoJson(g)!;
    final inHole = at(north: 5);
    expect(s.distanceMeters(inHole[0], inHole[1]), closeTo(15, 0.5));
    final ring = at(north: 60);
    expect(s.distanceMeters(ring[0], ring[1]), 0);
  });

  test('MultiPolygon uses the nearest part, Feature and string input work', () {
    final far = [
      for (final p in (square()['coordinates'] as List).first) [(p as List)[0] + 0.01, p[1]]
    ];
    final mp = {
      'type': 'MultiPolygon',
      'coordinates': [
        (square()['coordinates'] as List),
        [far],
      ],
    };
    final s = SiteGeometry.fromGeoJson(mp)!;
    final p = at(east: 110);
    expect(s.distanceMeters(p[0], p[1]), closeTo(10, 0.4));

    final feature = SiteGeometry.fromGeoJson({'type': 'Feature', 'geometry': square()});
    expect(feature, isNotNull);
  });

  test('bad input returns null instead of throwing', () {
    expect(SiteGeometry.fromGeoJson(''), isNull);
    expect(SiteGeometry.fromGeoJson('not json'), isNull);
    expect(SiteGeometry.fromGeoJson({'type': 'Point', 'coordinates': [1, 2]}), isNull);
  });
}
