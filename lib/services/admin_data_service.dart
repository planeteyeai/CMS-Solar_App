import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'auth_service.dart';

/// One browsable collection of data in the superadmin explorer.
///
/// [paths] is a list of candidate endpoints, tried in order. The first one that
/// answers with HTTP 200 is used and remembered. Paths marked "known" in
/// [AdminDatasets] already exist in the app's API config; the others are the
/// most likely DRF routes and can be overridden from the UI if your backend
/// uses a different route.
class AdminDataset {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> paths;
  final bool supportsDate;

  const AdminDataset({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.paths,
    this.supportsDate = false,
  });
}

class AdminDatasets {
  AdminDatasets._();

  static const workers = AdminDataset(
    key: 'workers',
    title: 'Worker status (today)',
    subtitle: 'Present / checked out / absent with last location',
    icon: Icons.how_to_reg_rounded,
    paths: ['/api/dashboard/workers/'],
  );

  static const attendance = AdminDataset(
    key: 'attendance',
    title: 'Attendance records',
    subtitle: 'Every check-in / check-out; filter by date',
    icon: Icons.event_available_rounded,
    supportsDate: true,
    paths: ['/api/dashboard/ai-data/attendance/'],
  );

  static const locations = AdminDataset(
    key: 'locations',
    title: 'GPS location pings',
    subtitle: 'Raw location history for all workers',
    icon: Icons.my_location_rounded,
    paths: ['/api/dashboard/ai-data/location/'],
  );

  static const siteTasks = AdminDataset(
    key: 'site_tasks',
    title: 'Site tasks & progress',
    subtitle: 'Every task of every project with current progress',
    icon: Icons.checklist_rtl_rounded,
    paths: ['/api/projects-data/site-tasks/'],
  );

  static const taskUpdates = AdminDataset(
    key: 'task_updates',
    title: 'Task update history',
    subtitle: 'Every saved progress update with AI estimate, edits and remarks',
    icon: Icons.history_rounded,
    paths: ['/api/projects-data/site-task-updates/?limit=300'],
  );

  static const analyses = AdminDataset(
    key: 'analyses',
    title: 'Legacy site inspections',
    subtitle: 'Older AI inspection records',
    icon: Icons.smart_toy_rounded,
    paths: ['/api/projects-data/site-inspections/'],
  );

  static const activity = AdminDataset(
    key: 'activity',
    title: 'Activity feed',
    subtitle: 'Check-ins, zone entries and exits',
    icon: Icons.timeline_rounded,
    paths: ['/api/dashboard/activity-feed/'],
  );

  static const analytics = AdminDataset(
    key: 'analytics',
    title: 'Attendance analytics',
    subtitle: 'Zone occupancy and worker trends',
    icon: Icons.insights_rounded,
    paths: ['/api/dashboard/analytics/'],
  );

  static const users = AdminDataset(
    key: 'users',
    title: 'Users',
    subtitle: 'All accounts, roles and assignments',
    icon: Icons.people_alt_rounded,
    paths: ['/api/accounts/users/'],
  );

  static const assignments = AdminDataset(
    key: 'assignments',
    title: 'Project assignments',
    subtitle: 'Who is assigned to which project',
    icon: Icons.assignment_ind_rounded,
    paths: ['/api/accounts/assignments/'],
  );

  static const projects = AdminDataset(
    key: 'projects',
    title: 'Projects',
    subtitle: 'Every project in the database',
    icon: Icons.apartment_rounded,
    paths: ['/api/projects-data/projects/'],
  );

  static const liveLocations = AdminDataset(
    key: 'live_locations',
    title: 'Live locations',
    subtitle: 'Latest saved position of every tracked engineer',
    icon: Icons.my_location_rounded,
    paths: ['/api/dashboard/live-locations/'],
  );

  static const dpr = AdminDataset(
    key: 'dpr',
    title: 'Daily progress reports (DPR)',
    subtitle: 'All DPRs with approval status',
    icon: Icons.description_rounded,
    paths: ['/api/dpr/'],
  );

  static const evidence = AdminDataset(
    key: 'evidence',
    title: 'Evidence files',
    subtitle: 'Uploaded photos, videos and documents',
    icon: Icons.photo_library_rounded,
    paths: ['/api/projects-data/evidence/'],
  );

  static const risks = AdminDataset(
    key: 'risks',
    title: 'Risks',
    subtitle: 'Project risk register',
    icon: Icons.warning_amber_rounded,
    paths: ['/api/projects-data/project-risks/'],
  );

  static const ncrs = AdminDataset(
    key: 'ncrs',
    title: 'Quality NCRs',
    subtitle: 'Non-conformance reports',
    icon: Icons.fact_check_rounded,
    paths: ['/api/projects-data/quality-ncrs/'],
  );

  static const alerts = AdminDataset(
    key: 'alerts',
    title: 'Alerts',
    subtitle: 'Forecast and admin alerts',
    icon: Icons.notifications_active_rounded,
    paths: ['/api/projects-data/forecast-alerts/?status=all'],
  );

  static const auditLogs = AdminDataset(
    key: 'audit_logs',
    title: 'Audit logs',
    subtitle: 'Who did what and when',
    icon: Icons.manage_search_rounded,
    paths: ['/api/projects-data/audit-logs/'],
  );

  static const epcs = AdminDataset(
    key: 'epcs',
    title: 'EPC contractors',
    subtitle: 'EPC vendor master',
    icon: Icons.business_rounded,
    paths: ['/api/accounts/epcs/'],
  );

  static const all = <AdminDataset>[
    workers,
    attendance,
    siteTasks,
    taskUpdates,
    liveLocations,
    locations,
    activity,
    analytics,
    users,
    assignments,
    projects,
    dpr,
    evidence,
    risks,
    ncrs,
    alerts,
    auditLogs,
    epcs,
    analyses,
  ];
}

class AdminPage {
  final List<Map<String, dynamic>> items;
  final String? next;
  final int? count;
  final String sourceUrl;
  const AdminPage({
    required this.items,
    required this.next,
    required this.count,
    required this.sourceUrl,
  });
}

class AdminDataException implements Exception {
  final String message;
  final int? statusCode;
  final bool notFound;
  final List<String> tried;
  const AdminDataException(
    this.message, {
    this.statusCode,
    this.notFound = false,
    this.tried = const [],
  });
  @override
  String toString() => message;
}

/// Read-only access to everything the superadmin is allowed to see.
/// The backend enforces permissions; this class only reads and parses.
class AdminDataService {
  AdminDataService._();

  static final Map<String, String> _resolved = {};
  static const _kOverridePrefix = 'admin_endpoint_override_';

  // ── Endpoint override (persisted) ───────────────────────────────────────
  static Future<String?> getOverride(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_kOverridePrefix$key');
  }

  static Future<void> setOverride(String key, String? path) async {
    final prefs = await SharedPreferences.getInstance();
    _resolved.remove(key);
    if (path == null || path.trim().isEmpty) {
      await prefs.remove('$_kOverridePrefix$key');
    } else {
      await prefs.setString('$_kOverridePrefix$key', path.trim());
    }
  }

  // ── Fetching ─────────────────────────────────────────────────────────────
  static Future<AdminPage> fetchDataset(
    AuthService auth,
    AdminDataset ds, {
    String? search,
    DateTime? date,
  }) async {
    final extra = <String, String>{};
    if (search != null && search.trim().isNotEmpty) {
      extra['search'] = search.trim();
    }
    if (date != null) {
      final d =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      // Attendance export takes a date range; other lists ignore extras.
      extra['date'] = d;
      extra['start_date'] = d;
      extra['end_date'] = d;
    }

    final override = await getOverride(ds.key);
    final candidates = <String>[
      if (override != null) override,
      if (override == null && _resolved[ds.key] != null) _resolved[ds.key]!,
      if (override == null) ...ds.paths,
    ];

    final tried = <String>[];
    for (final path in candidates) {
      final url = _withParams(ApiConfig.url(path), extra);
      tried.add(url);
      final outcome = await _get(auth, url);
      if (outcome is AdminPage) {
        _resolved[ds.key] = path;
        return outcome;
      }
      // outcome == null → endpoint missing; try the next candidate.
    }
    throw AdminDataException(
      'No matching endpoint was found on the server for "${ds.title}".',
      notFound: true,
      tried: tried,
    );
  }

  /// Fetch an arbitrary URL (used for pagination and the custom endpoint).
  static Future<AdminPage> fetchUrl(AuthService auth, String url) async {
    final outcome = await _get(auth, url);
    if (outcome is AdminPage) return outcome;
    throw AdminDataException(
      'Endpoint not found (404).',
      statusCode: 404,
      notFound: true,
      tried: [url],
    );
  }

  /// Returns an [AdminPage] on success, null when the endpoint is missing,
  /// and throws for auth / network / server errors.
  static Future<AdminPage?> _get(AuthService auth, String url) async {
    final res = await auth.authenticatedGet(url);
    if (res == null) {
      throw const AdminDataException(
          'Network error. Check your connection and try again.');
    }
    if (res.statusCode == 401) {
      throw const AdminDataException(
          'Session expired. Please log out and sign in again.',
          statusCode: 401);
    }
    if (res.statusCode == 403) {
      throw const AdminDataException(
          'The server denied access. This account needs superadmin permission on this endpoint.',
          statusCode: 403);
    }
    if (res.statusCode == 404 || res.statusCode == 405) return null;
    if (res.statusCode != 200) {
      throw AdminDataException('Server error (${res.statusCode}).',
          statusCode: res.statusCode);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null; // 200 but not JSON (e.g. an HTML fallback page)
    }
    return _parse(decoded, url);
  }

  static AdminPage _parse(dynamic decoded, String url) {
    List<dynamic> raw;
    String? next;
    int? count;

    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map) {
      next = decoded['next'] is String ? decoded['next'] as String : null;
      count = decoded['count'] is num ? (decoded['count'] as num).toInt() : null;
      const listKeys = [
        'results', 'data', 'items', 'tasks', 'worker_statuses', 'events', 'workers', 'analyses', 'records',
        'attendance', 'events', 'activities', 'users', 'projects',
      ];
      List<dynamic>? found;
      for (final k in listKeys) {
        if (decoded[k] is List) {
          found = decoded[k] as List;
          break;
        }
      }
      raw = found ?? [decoded]; // single object (e.g. analytics) → one record
    } else {
      raw = [decoded];
    }

    final items = raw
        .map<Map<String, dynamic>>((e) => e is Map
            ? Map<String, dynamic>.from(e)
            : <String, dynamic>{'value': e})
        .toList();
    return AdminPage(items: items, next: next, count: count, sourceUrl: url);
  }

  static String _withParams(String url, Map<String, String> extra) {
    if (extra.isEmpty) return url;
    final uri = Uri.parse(url);
    return uri
        .replace(queryParameters: {...uri.queryParameters, ...extra})
        .toString();
  }

  // ── Small helper for the dashboard summary ───────────────────────────────
  static bool asBool(dynamic v) {
    if (v is bool) return v;
    final s = v?.toString().toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'yes' || s == 'checked_in' || s == 'online';
  }
}
