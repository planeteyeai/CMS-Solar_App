import 'dart:math' as math;

import '../config/api_config.dart';
import '../models/attendance.dart';
import 'api_helpers.dart';
import 'auth_service.dart';
import 'monitoring_service.dart';

class TrackingException implements Exception {
  final String message;
  const TrackingException(this.message);
  @override
  String toString() => message;
}

/// Latest known position of one engineer.
class LivePosition {
  final int workerId;
  final String username;
  final String fullName;
  final double lat;
  final double lon;
  final DateTime? timestamp;
  final int minutesAgo;
  final String zone;
  final String projectName;
  final bool? insideProject;
  final String attendanceStatus;
  final DateTime? checkIn;
  final bool isLive;

  const LivePosition({
    required this.workerId,
    required this.username,
    required this.fullName,
    required this.lat,
    required this.lon,
    required this.timestamp,
    required this.minutesAgo,
    required this.zone,
    required this.projectName,
    required this.insideProject,
    required this.attendanceStatus,
    required this.checkIn,
    required this.isLive,
  });

  /// live (recent ping while checked in) | stale (no ping for a while) | offline
  String get state => isLive ? 'live' : (minutesAgo <= 90 && attendanceStatus == 'ACTIVE' ? 'stale' : 'offline');

  factory LivePosition.fromJson(Map<String, dynamic> j) {
    final ts = parseDate(j['timestamp']);
    return LivePosition(
      workerId: toInt(j['worker_id']),
      username: (j['username'] ?? '').toString(),
      fullName: (j['full_name'] ?? j['username'] ?? '').toString(),
      lat: toDouble(j['latitude']) ?? 0,
      lon: toDouble(j['longitude']) ?? 0,
      timestamp: ts,
      minutesAgo: j['minutes_since_update'] != null
          ? toInt(j['minutes_since_update'])
          : (ts == null ? 9999 : DateTime.now().difference(ts).inMinutes),
      zone: (j['zone'] ?? '').toString(),
      projectName: (j['project_name'] ?? '').toString(),
      insideProject: j['inside_project'] is bool ? j['inside_project'] as bool : null,
      attendanceStatus: (j['attendance_status'] ?? '').toString().toUpperCase(),
      checkIn: parseDate(j['check_in']),
      isLive: j['is_live'] == true,
    );
  }
}

class PathPoint {
  final double lat;
  final double lon;
  final DateTime? timestamp;
  final String zone;
  final bool? inside;
  final double segmentMeters;
  final int gapMinutes;
  const PathPoint({
    required this.lat,
    required this.lon,
    required this.timestamp,
    required this.zone,
    required this.inside,
    required this.segmentMeters,
    required this.gapMinutes,
  });
}

class WorkerPath {
  final int workerId;
  final String name;
  final List<PathPoint> points;
  final double distanceMeters;
  final int durationMinutes;
  final int outsidePoints;
  final String attendanceStatus;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final bool truncated;

  const WorkerPath({
    required this.workerId,
    required this.name,
    required this.points,
    required this.distanceMeters,
    required this.durationMinutes,
    required this.outsidePoints,
    required this.attendanceStatus,
    required this.checkIn,
    required this.checkOut,
    required this.truncated,
  });

  DateTime? get lastAt => points.isEmpty ? null : points.last.timestamp;
  DateTime? get firstAt => points.isEmpty ? null : points.first.timestamp;
}

double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dp = rad(lat2 - lat1);
  final dl = rad(lon2 - lon1);
  final a = math.pow(math.sin(dp / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a.toDouble())));
}

String fmtDistance(double meters) =>
    meters >= 1000 ? '${(meters / 1000).toStringAsFixed(2)} km' : '${meters.round()} m';

String fmtAgo(int minutes) {
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min ago';
  final h = minutes ~/ 60;
  if (h < 24) return '${h}h ${minutes % 60}m ago';
  return '${h ~/ 24}d ago';
}

/// Superadmin live tracking.
class TrackingService {
  TrackingService._();

  static bool _missing(dynamic res) =>
      res != null && res.statusCode == 404 && decodeBody(res) is! Map;

  // ── live positions ───────────────────────────────────────────────────────

  static Future<List<LivePosition>> live(AuthService auth, {String project = ''}) async {
    final uri = Uri.parse(ApiConfig.liveLocationsUrl)
        .replace(queryParameters: project.isEmpty ? null : {'project_name': project});
    final res = await auth.authenticatedGet(uri.toString());
    if (_missing(res)) return _liveFromWorkers(auth, project);
    if (res == null || res.statusCode != 200) {
      throw TrackingException(errorMessage(res, fallback: 'Could not load live locations'));
    }
    return extractList(decodeBody(res)).map(LivePosition.fromJson).toList();
  }

  /// Fallback when the live-locations endpoint is not deployed: use the dashboard workers list.
  static Future<List<LivePosition>> _liveFromWorkers(AuthService auth, String project) async {
    try {
      final d = await MonitoringService.workers(auth, project: project);
      final now = DateTime.now();
      return [
        for (final w in d.workers)
          if (w.lat != null && w.lon != null)
            LivePosition(
              workerId: w.workerId,
              username: w.username,
              fullName: w.fullName,
              lat: w.lat!,
              lon: w.lon!,
              timestamp: w.lastSeen,
              minutesAgo: w.lastSeen == null ? 9999 : now.difference(w.lastSeen!).inMinutes,
              zone: w.zone,
              projectName: project,
              insideProject: w.insideProject,
              attendanceStatus: w.status == 'PRESENT' ? 'ACTIVE' : '',
              checkIn: null,
              isLive: w.status == 'PRESENT',
            )
      ];
    } on MonitoringException catch (e) {
      throw TrackingException(e.message);
    }
  }

  // ── path ─────────────────────────────────────────────────────────────────

  /// The route travelled on [day] (local calendar day).
  static Future<WorkerPath> path(AuthService auth, int workerId, DateTime day,
      {String name = ''}) async {
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    final uri = Uri.parse(ApiConfig.workerPathUrl).replace(queryParameters: {
      'worker_id': '$workerId',
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    });
    final res = await auth.authenticatedGet(uri.toString());
    if (_missing(res)) return _pathFromHistory(auth, workerId, day, name);
    if (res == null || res.statusCode != 200) {
      throw TrackingException(errorMessage(res, fallback: 'Could not load the route'));
    }
    final d = decodeBody(res) as Map;
    final w = d['worker'] is Map ? Map<String, dynamic>.from(d['worker'] as Map) : <String, dynamic>{};
    final sum = d['summary'] is Map ? Map<String, dynamic>.from(d['summary'] as Map) : <String, dynamic>{};
    final att = d['attendance'] is Map ? Map<String, dynamic>.from(d['attendance'] as Map) : <String, dynamic>{};
    final pts = extractList(d, keys: const ['points'])
        .map((p) => PathPoint(
              lat: toDouble(p['latitude']) ?? 0,
              lon: toDouble(p['longitude']) ?? 0,
              timestamp: parseDate(p['timestamp']),
              zone: (p['zone'] ?? '').toString(),
              inside: p['inside_project'] is bool ? p['inside_project'] as bool : null,
              segmentMeters: toDouble(p['segment_meters']) ?? 0,
              gapMinutes: toInt(p['gap_minutes']),
            ))
        .toList();
    return WorkerPath(
      workerId: workerId,
      name: (w['full_name'] ?? name).toString(),
      points: pts,
      distanceMeters: toDouble(sum['distance_meters']) ?? 0,
      durationMinutes: toInt(sum['duration_minutes']),
      outsidePoints: toInt(sum['outside_project_points']),
      attendanceStatus: (att['status'] ?? '').toString(),
      checkIn: parseDate(att['check_in']),
      checkOut: parseDate(att['check_out']),
      truncated: sum['truncated'] == true,
    );
  }

  /// Fallback: GET /api/worker/{id}/locations/ (newest first) and build the path on the phone.
  static Future<WorkerPath> _pathFromHistory(
      AuthService auth, int workerId, DateTime day, String name) async {
    final uri = Uri.parse(ApiConfig.workerLocationsUrl(workerId))
        .replace(queryParameters: {'limit': '500', 'date': fmtDate(day)});
    final res = await auth.authenticatedGet(uri.toString());
    if (res == null || res.statusCode != 200) {
      throw TrackingException(errorMessage(res, fallback: 'Could not load the route'));
    }
    final rows = extractList(decodeBody(res))
      ..sort((a, b) => '${a['timestamp']}'.compareTo('${b['timestamp']}'));
    final pts = <PathPoint>[];
    var total = 0.0;
    var outside = 0;
    for (final r in rows) {
      final lat = toDouble(r['latitude']) ?? 0;
      final lon = toDouble(r['longitude']) ?? 0;
      final ts = parseDate(r['timestamp']);
      final prev = pts.isEmpty ? null : pts.last;
      final seg = prev == null ? 0.0 : haversineMeters(prev.lat, prev.lon, lat, lon);
      final gap = (prev?.timestamp == null || ts == null) ? 0 : ts.difference(prev!.timestamp!).inMinutes;
      total += seg;
      final inside = r['inside_project'] is bool ? r['inside_project'] as bool : null;
      if (inside == false) outside++;
      pts.add(PathPoint(
        lat: lat,
        lon: lon,
        timestamp: ts,
        zone: (r['current_zone'] ?? '').toString(),
        inside: inside,
        segmentMeters: seg,
        gapMinutes: gap,
      ));
    }
    final dur = pts.length > 1 && pts.first.timestamp != null && pts.last.timestamp != null
        ? pts.last.timestamp!.difference(pts.first.timestamp!).inMinutes
        : 0;
    return WorkerPath(
      workerId: workerId,
      name: name,
      points: pts,
      distanceMeters: total,
      durationMinutes: dur,
      outsidePoints: outside,
      attendanceStatus: '',
      checkIn: null,
      checkOut: null,
      truncated: rows.length >= 500,
    );
  }
}
