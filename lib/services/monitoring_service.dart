import 'dart:async';

import '../config/api_config.dart';
import '../models/attendance.dart';
import 'api_helpers.dart';
import 'auth_service.dart';
import 'site_status_service.dart';

class LivelinessData {
  final int present;
  final int offsite;
  final int absent;
  final int attendanceCount;
  final List<Map<String, dynamic>> activeZones;
  final List<Map<String, dynamic>> recentCheckIns;
  const LivelinessData({
    required this.present,
    required this.offsite,
    required this.absent,
    required this.attendanceCount,
    required this.activeZones,
    required this.recentCheckIns,
  });
}

class WorkersData {
  final List<WorkerStatus> workers;
  final List<Map<String, dynamic>> zones;
  const WorkersData({required this.workers, required this.zones});
}

class MonitoringException implements Exception {
  final String message;
  const MonitoringException(this.message);
  @override
  String toString() => message;
}

/// Read-only attendance monitoring for Team Lead / Project Manager / Superadmin.
class MonitoringService {
  MonitoringService._();

  static String _url(String base, Map<String, String> qp) {
    final clean = {...qp}..removeWhere((k, v) => v.isEmpty);
    return Uri.parse(base)
        .replace(queryParameters: clean.isEmpty ? null : clean)
        .toString();
  }

  static Future<dynamic> _get(AuthService auth, String url) async {
    final res = await auth.authenticatedGet(url);
    if (res == null || res.statusCode != 200) {
      throw MonitoringException(errorMessage(res, fallback: 'Could not load data'));
    }
    return decodeBody(res);
  }

  static Future<LivelinessData> liveliness(AuthService auth, {String project = ''}) async {
    final d = await _get(auth, _url(ApiConfig.livelinessUrl, {'project_name': project}));
    final m = d is Map ? d : <dynamic, dynamic>{};
    List<Map<String, dynamic>> list(dynamic v) => v is List
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return LivelinessData(
      present: toInt(m['workers_present']),
      offsite: toInt(m['workers_offsite']),
      absent: toInt(m['workers_absent']),
      attendanceCount: toInt(m['attendance_count']),
      activeZones: list(m['active_zones']),
      recentCheckIns: list(m['recent_check_ins']),
    );
  }

  static Future<WorkersData> workers(AuthService auth, {String project = ''}) async {
    final d = await _get(auth, _url(ApiConfig.workersUrl, {'project_name': project}));
    final m = d is Map ? d : <dynamic, dynamic>{};
    final ws = <WorkerStatus>[];
    var zones = <Map<String, dynamic>>[];

    if (m['worker_statuses'] is List) {
      for (final e in (m['worker_statuses'] as List).whereType<Map>()) {
        ws.add(WorkerStatus.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    if (m['zones'] is List) {
      zones = (m['zones'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else if (m['zones'] is Map) {
      // Alternative shape: {"Block-A": [ {worker_id, username, status, last_location}, … ]}
      (m['zones'] as Map).forEach((zone, list) {
        if (list is! List) return;
        zones.add({'zone': '$zone', 'worker_count': list.length});
        if (m['worker_statuses'] is List) return; // already have the flat list
        for (final e in list.whereType<Map>()) {
          final w = Map<String, dynamic>.from(e)..putIfAbsent('zone', () => '$zone');
          ws.add(WorkerStatus.fromJson(w));
        }
      });
    }
    return WorkersData(workers: ws, zones: zones);
  }

  /// Worker list with on-site / off-site decided against EACH engineer's own assigned
  /// site (not every site), treating anything closer than 5 m as on site.
  /// Falls back to the server's own status when a site has no boundary.
  static Future<WorkersData> workersAdjusted(AuthService auth, {String project = ''}) async {
    final d = await workers(auth, project: project);
    try {
      final contexts = await SiteStatusService.contextsFor(
        auth,
        d.workers.map((w) => w.workerId),
        fallbackProject: {
          if (project.isNotEmpty) for (final w in d.workers) w.workerId: project,
        },
      );
      final adjusted = <WorkerStatus>[
        for (final w in d.workers) _adjust(w, contexts[w.workerId]),
      ];
      return WorkersData(workers: adjusted, zones: d.zones);
    } catch (_) {
      return d; // never block the screen because of the extra calculation
    }
  }

  static WorkerStatus _adjust(WorkerStatus w, SiteContext? ctx) {
    final active = w.status == 'PRESENT' || w.status == 'INCOMPLETE';
    if (ctx == null || !active || w.lat == null || w.lon == null) return w;
    final r = ctx.reading(w.lat!, w.lon!, backendInside: w.insideProject);
    if (r.onSite == null) return w; // unknown: keep what the server said
    return w.copyWith(
      status: r.onSite! ? 'PRESENT' : 'INCOMPLETE',
      insideProject: r.onSite,
      siteDistance: r.distanceMeters,
      siteName: r.siteName,
    );
  }

  static Future<List<Map<String, dynamic>>> activityFeed(AuthService auth,
      {String project = ''}) async {
    final d = await _get(auth, _url(ApiConfig.activityFeedUrl, {'project_name': project}));
    return extractList(d);
  }

  /// Attendance rows for a date range (inclusive, yyyy-MM-dd).
  static Future<List<AttendanceRecord>> attendance(
    AuthService auth, {
    String project = '',
    required DateTime start,
    required DateTime end,
  }) async {
    final d = await _get(
      auth,
      _url(ApiConfig.attendanceExportUrl, {
        'project_name': project,
        'start_date': fmtDate(start),
        'end_date': fmtDate(end),
      }),
    );
    final rows = extractList(d).map(AttendanceRecord.fromJson).toList();
    rows.sort((a, b) {
      final c = (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000));
      return c != 0 ? c : (b.checkIn ?? DateTime(2000)).compareTo(a.checkIn ?? DateTime(2000));
    });
    return rows;
  }

  /// Own attendance history (Site Engineer).
  static Future<List<AttendanceRecord>> myAttendance(AuthService auth,
      {int limit = 30}) async {
    final id = auth.profile?.id;
    if (id == null) return [];
    final d = await _get(
        auth, _url(ApiConfig.workerAttendanceUrl(id), {'limit': '$limit'}));
    return extractList(d).map(AttendanceRecord.fromJson).toList();
  }

  /// A worker's activity log (CHECK_IN, ZONE_ENTRY …). Superadmin only on the
  /// current backend, unless the access patch is applied.
  static Future<List<Map<String, dynamic>>> workerActivity(
      AuthService auth, int workerId,
      {String? date}) async {
    final d = await _get(
        auth, _url(ApiConfig.workerActivityUrl(workerId), {'limit': '100', 'date': date ?? ''}));
    return extractList(d);
  }
}
