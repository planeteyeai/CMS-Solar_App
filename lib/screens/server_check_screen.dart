import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../services/api_helpers.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

enum _Level { ok, warn, fail }

class _Result {
  final String name;
  final String note;
  final String url;
  final int? status;
  final _Level level;
  final String detail;
  const _Result(this.name, this.note, this.url, this.status, this.level, this.detail);
}

/// Shows, from the phone itself, which backend endpoints this app needs and
/// whether the server has them. Useful right after a backend deployment.
class ServerCheckScreen extends StatefulWidget {
  const ServerCheckScreen({super.key});

  @override
  State<ServerCheckScreen> createState() => _ServerCheckScreenState();
}

class _ServerCheckScreenState extends State<ServerCheckScreen> {
  bool _running = false;
  List<_Result> _results = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  /// 404 with a JSON body = route exists but nothing found (fine).
  /// 404 without JSON = the route itself does not exist on the server.
  _Result _classify(String name, String note, String url, http.Response? res,
      {bool okWhen404Json = false, String expectMissing = ''}) {
    if (res == null) {
      return _Result(name, note, url, null, _Level.fail, 'No answer (offline, wrong address or timeout)');
    }
    final c = res.statusCode;
    final json = decodeBody(res) is Map;
    if (c >= 200 && c < 300) return _Result(name, note, url, c, _Level.ok, 'Available');
    if (c == 404 && json && okWhen404Json) {
      return _Result(name, note, url, c, _Level.ok, 'Available (no data yet)');
    }
    if (c == 404 && !json) {
      return _Result(name, note, url, c, _Level.fail,
          'Route not found: this endpoint is not deployed on the server');
    }
    if (c == 401) return _Result(name, note, url, c, _Level.fail, 'Not logged in / token rejected');
    if (c == 403) return _Result(name, note, url, c, _Level.warn, 'Exists, but this account has no permission');
    if (c == 503) return _Result(name, note, url, c, _Level.warn, 'Exists, but a server setting is missing (e.g. file storage)');
    if (c >= 500) return _Result(name, note, url, c, _Level.fail, 'Server error (migration missing or code error)');
    return _Result(name, note, url, c, _Level.warn, 'Unexpected answer');
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results = [];
    });
    final auth = context.read<AuthService>();
    final me = auth.profile;
    final out = <_Result>[];
    void add(_Result r) {
      out.add(r);
      if (mounted) setState(() => _results = List.of(out));
    }

    // Public
    http.Response? health;
    try {
      health = await http.get(Uri.parse(ApiConfig.url('/health/'))).timeout(const Duration(seconds: 12));
    } catch (_) {}
    add(_classify('Server reachable', 'GET /health/', ApiConfig.url('/health/'), health));

    Future<void> get(String name, String note, String path, {bool okWhen404Json = false}) async {
      final url = ApiConfig.url(path);
      add(_classify(name, note, url, await auth.authenticatedGet(url), okWhen404Json: okWhen404Json));
    }

    await get('Login profile', 'GET /api/accounts/me/', '/api/accounts/me/');
    if (me != null) {
      await get('Today\'s attendance', 'GET /api/worker/{id}/attendance/today/',
          '/api/worker/${me.id}/attendance/today/', okWhen404Json: true);
    }
    await get('Live attendance counts', 'GET /api/dashboard/liveliness/', '/api/dashboard/liveliness/');
    await get('Worker statuses', 'GET /api/dashboard/workers/', '/api/dashboard/workers/');
    await get('Attendance records', 'GET /api/dashboard/ai-data/attendance/', '/api/dashboard/ai-data/attendance/');

    // New task feature
    await get('Site tasks', 'GET /api/projects-data/site-tasks/', '/api/projects-data/site-tasks/', okWhen404Json: true);
    await get('Task update history', 'GET /api/projects-data/site-task-updates/', '/api/projects-data/site-task-updates/');
    final presign = ApiConfig.url('/api/projects-data/site-tasks/1/evidence/presign/');
    add(_classify('Photo upload links (AWS S3)', 'OPTIONS …/site-tasks/{id}/evidence/presign/', presign,
        await auth.authenticatedRequest('OPTIONS', presign), okWhen404Json: false));

    // On-site / off-site vs the engineer's own site (Super Admin / Team Lead / Project Manager)
    if (me != null && me.appRole != AppRole.siteEngineer) {
      await get('Site assignments', 'GET /api/accounts/assignments/', '/api/accounts/assignments/');
      final siteName = me.primaryProjectName;
      if (siteName != null && siteName.isNotEmpty) {
        await get('Site boundary', 'GET /api/projects/boundary/?project_name=…',
            '/api/projects/boundary/?project_name=${Uri.encodeQueryComponent(siteName)}',
            okWhen404Json: true);
      }
    }

    // Live tracking (superadmin) + profile pictures
    final me2 = auth.profile;
    await get('Live locations (superadmin)', 'GET /api/dashboard/live-locations/', '/api/dashboard/live-locations/');
    final pathUrl = ApiConfig.url('/api/dashboard/worker-path/');
    add(_classify('Route / path (superadmin)', 'OPTIONS /api/dashboard/worker-path/', pathUrl,
        await auth.authenticatedRequest('OPTIONS', pathUrl)));
    if (me2 != null) {
      await get('Profile picture', 'GET /api/accounts/users/{id}/profile-picture/',
          '/api/accounts/users/${me2.id}/profile-picture/', okWhen404Json: true);
    }

    // Documented existing upload route (fallback storage)
    final ev = ApiConfig.url('/api/projects-data/evidence/');
    add(_classify('Evidence upload route', 'OPTIONS /api/projects-data/evidence/', ev,
        await auth.authenticatedRequest('OPTIONS', ev)));

    if (mounted) setState(() => _running = false);
  }

  String _report() {
    final b = StringBuffer()
      ..writeln('Server: ${ApiConfig.base}')
      ..writeln('AI: runs on the server (${AiConfig.endpoint}); no key in the app')
      ..writeln();
    for (final r in _results) {
      b.writeln('${r.level == _Level.ok ? 'OK  ' : r.level == _Level.warn ? 'WARN' : 'FAIL'} '
          '${r.status ?? '-'}  ${r.name}  (${r.note})  ${r.detail}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final fails = _results.where((r) => r.level == _Level.fail).length;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('CONNECTION CHECK'),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _results.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _report()));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Report copied')));
                  },
          ),
          IconButton(
              tooltip: 'Run again',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _running ? null : _run),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SERVER',
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const SizedBox(height: 4),
              SelectableText(ApiConfig.base,
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.verified_user_rounded, size: 18, color: AppTheme.accentGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('AI runs on the server. There is no AI key in this app.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ),
              ]),
            ]),
          ),
          if (_running) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 3)),
          if (!_running && _results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                fails == 0
                    ? 'Everything the app needs is available.'
                    : '$fails item${fails == 1 ? '' : 's'} not available. The app keeps working from the phone where it can; send the copied report to your backend team.',
                style: TextStyle(color: fails == 0 ? AppTheme.accentGreen : AppTheme.amber, height: 1.4),
              ),
            ),
          const SizedBox(height: 10),
          for (final r in _results)
            AppCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  r.level == _Level.ok
                      ? Icons.check_circle_rounded
                      : r.level == _Level.warn
                          ? Icons.warning_amber_rounded
                          : Icons.cancel_rounded,
                  color: r.level == _Level.ok
                      ? AppTheme.accentGreen
                      : r.level == _Level.warn
                          ? AppTheme.amber
                          : AppTheme.accentRed,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                          child: Text(r.name,
                              style: TextStyle(
                                  color: AppTheme.textPrimary, fontWeight: FontWeight.w800))),
                      if (r.status != null) Pill('${r.status}', color: AppTheme.textSecondary),
                    ]),
                    const SizedBox(height: 2),
                    Text(r.note, style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                    const SizedBox(height: 4),
                    Text(r.detail, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.35)),
                  ]),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
