import '../config/api_config.dart';
import 'api_helpers.dart';
import 'auth_service.dart';
import 'geo_utils.dart';

/// An engineer within this many metres of THEIR OWN site counts as on site
/// (GPS error is usually larger than a few metres).
const double kOnSiteToleranceMeters = 5.0;

String fmtMeters(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

/// Result of comparing one GPS position with the engineer's assigned site(s).
class SiteReading {
  /// true = on site, false = off site, null = unknown (no boundary to compare with).
  final bool? onSite;

  /// Distance to the nearest assigned site boundary (0 = inside); null when unknown.
  final double? distanceMeters;
  final String siteName;
  const SiteReading({this.onSite, this.distanceMeters, this.siteName = ''});

  bool get measured => distanceMeters != null;

  /// "On site" / "38 m from site" / ''.
  String get label {
    if (onSite == true) return 'On site';
    if (distanceMeters != null) return '${fmtMeters(distanceMeters!)} from site';
    return onSite == false ? 'Off site' : '';
  }
}

class _Site {
  final String name;
  final SiteGeometry geometry;
  const _Site(this.name, this.geometry);
}

/// The sites one engineer is assigned to, with their boundaries.
class SiteContext {
  final List<String> assignedNames;
  final List<_Site> _sites;
  const SiteContext(this.assignedNames, this._sites);

  static const empty = SiteContext([], []);

  bool get hasBoundary => _sites.isNotEmpty;

  /// Only the engineer's own assigned site(s) are used. [backendInside] is the
  /// server's own flag, used only when no boundary is available.
  SiteReading reading(double lat, double lon, {bool? backendInside}) {
    if (_sites.isEmpty) {
      return SiteReading(
        onSite: backendInside,
        siteName: assignedNames.isEmpty ? '' : assignedNames.first,
      );
    }
    double? best;
    var bestName = '';
    for (final s in _sites) {
      final d = s.geometry.distanceMeters(lat, lon);
      if (best == null || d < best) {
        best = d;
        bestName = s.name;
      }
    }
    return SiteReading(
      onSite: best! < kOnSiteToleranceMeters,
      distanceMeters: best,
      siteName: bestName,
    );
  }
}

/// Works out, for every site engineer, how far they are from THEIR assigned site.
/// Assignments and boundaries are cached so the 30-second refreshes stay cheap.
class SiteStatusService {
  SiteStatusService._();

  static Map<int, Set<String>> _assigned = {};
  static DateTime? _assignedAt;
  static final Map<String, ({SiteGeometry? geometry, DateTime at})> _boundaries = {};

  static const _assignedTtl = Duration(minutes: 10);
  static const _boundaryTtl = Duration(minutes: 30);
  static const _missingTtl = Duration(minutes: 5);

  static void clearCache() {
    _assigned = {};
    _assignedAt = null;
    _boundaries.clear();
  }

  static Future<void> _loadAssignments(AuthService auth) async {
    if (_assignedAt != null && DateTime.now().difference(_assignedAt!) < _assignedTtl) return;
    final map = <int, Set<String>>{};

    // 1. Assignment table (superadmin / admin).
    final res = await auth.authenticatedGet(ApiConfig.assignmentsUrl);
    if (res != null && res.statusCode == 200) {
      for (final a in extractList(decodeBody(res))) {
        if (a['is_active'] == false) continue;
        final id = (a['user'] is num) ? (a['user'] as num).toInt() : int.tryParse('${a['user']}');
        final name = (a['project_name'] ?? '').toString();
        if (id != null && name.isNotEmpty) map.putIfAbsent(id, () => <String>{}).add(name);
      }
    }

    // 2. Fallback: project list with site_engineers[].
    if (map.isEmpty) {
      final pr = await auth.authenticatedGet(ApiConfig.projectsUrl);
      if (pr != null && pr.statusCode == 200) {
        for (final p in extractList(decodeBody(pr))) {
          final name = (p['name'] ?? p['project_name'] ?? '').toString();
          final engineers = p['site_engineers'];
          if (name.isEmpty || engineers is! List) continue;
          for (final e in engineers) {
            final id = e is num ? e.toInt() : int.tryParse('$e');
            if (id != null) map.putIfAbsent(id, () => <String>{}).add(name);
          }
        }
      }
    }

    if (map.isNotEmpty || _assigned.isEmpty) _assigned = map;
    _assignedAt = DateTime.now();
  }

  static Future<SiteGeometry?> _boundary(AuthService auth, String project) async {
    final cached = _boundaries[project];
    if (cached != null) {
      final ttl = cached.geometry == null ? _missingTtl : _boundaryTtl;
      if (DateTime.now().difference(cached.at) < ttl) return cached.geometry;
    }
    SiteGeometry? geometry;
    try {
      final url = Uri.parse(ApiConfig.projectBoundaryUrl)
          .replace(queryParameters: {'project_name': project}).toString();
      final res = await auth.authenticatedGet(url);
      if (res != null && res.statusCode == 200) {
        final d = decodeBody(res);
        if (d is Map) geometry = SiteGeometry.fromGeoJson(d['boundary_geojson']);
      }
    } catch (_) {}
    _boundaries[project] = (geometry: geometry, at: DateTime.now());
    return geometry;
  }

  /// Contexts for many workers at once (one assignment call, one call per site).
  /// [fallbackProject] per worker is used only if the worker has no assignment on record.
  static Future<Map<int, SiteContext>> contextsFor(
    AuthService auth,
    Iterable<int> workerIds, {
    Map<int, String> fallbackProject = const {},
  }) async {
    try {
      await _loadAssignments(auth);
    } catch (_) {}

    final names = <int, Set<String>>{};
    for (final id in workerIds) {
      final s = <String>{...(_assigned[id] ?? const <String>{})};
      final fb = fallbackProject[id] ?? '';
      if (s.isEmpty && fb.isNotEmpty) s.add(fb);
      names[id] = s;
    }

    final allSites = <String>{for (final s in names.values) ...s};
    final geoms = <String, SiteGeometry?>{};
    await Future.wait([
      for (final n in allSites)
        _boundary(auth, n).then((g) => geoms[n] = g).catchError((_) {
          geoms[n] = null;
          return null;
        }),
    ]);

    return {
      for (final e in names.entries)
        e.key: SiteContext(
          e.value.toList(),
          [
            for (final n in e.value)
              if (geoms[n] != null && !geoms[n]!.isEmpty) _Site(n, geoms[n]!)
          ],
        ),
    };
  }

  static Future<SiteContext> contextFor(AuthService auth, int workerId,
      {String fallbackProject = ''}) async {
    final m = await contextsFor(auth, [workerId],
        fallbackProject: fallbackProject.isEmpty ? const {} : {workerId: fallbackProject});
    return m[workerId] ?? SiteContext.empty;
  }
}
