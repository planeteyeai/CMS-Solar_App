import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/attendance.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/monitoring_service.dart';
import '../../services/site_status_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import '../../widgets/user_avatar.dart';
import '../site_engineer/se_history.dart' show AttendanceTile;
import 'worker_path_screen.dart';

class AttendanceTab extends StatefulWidget {
  final ValueNotifier<String> project;
  const AttendanceTab({super.key, required this.project});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  int _segment = 0; // 0 today, 1 history

  // Today
  bool _loadingToday = true;
  String? _errorToday;
  List<WorkerStatus> _workers = [];
  String _filter = 'ALL';
  String _query = '';

  // History
  bool _loadingHist = false;
  bool _histLoaded = false;
  String? _errorHist;
  List<AttendanceRecord> _records = [];
  late DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_projectChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadToday());
  }

  @override
  void dispose() {
    widget.project.removeListener(_projectChanged);
    super.dispose();
  }

  void _projectChanged() {
    _loadToday();
    if (_histLoaded) _loadHistory();
  }

  Future<void> _loadToday() async {
    if (!mounted) return;
    setState(() {
      _loadingToday = true;
      _errorToday = null;
    });
    try {
      final d = await MonitoringService.workersAdjusted(context.read<AuthService>(),
          project: widget.project.value);
      if (!mounted) return;
      setState(() {
        _workers = d.workers;
        _loadingToday = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorToday = e.toString().replaceFirst('Exception: ', '').replaceFirst('MonitoringException: ', '');
        _loadingToday = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _loadingHist = true;
      _errorHist = null;
    });
    try {
      final rows = await MonitoringService.attendance(
        context.read<AuthService>(),
        project: widget.project.value,
        start: _range.start,
        end: _range.end,
      );
      if (!mounted) return;
      setState(() {
        _records = rows;
        _loadingHist = false;
        _histLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorHist = e.toString().replaceFirst('Exception: ', '');
        _loadingHist = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _range,
    );
    if (r != null) {
      setState(() => _range = r);
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SegmentBar(
          items: const [('0', 'Today'), ('1', 'History')],
          value: '$_segment',
          onChanged: (v) {
            setState(() => _segment = int.parse(v));
            if (_segment == 1 && !_histLoaded) _loadHistory();
          },
        ),
      ),
      Expanded(child: _segment == 0 ? _today() : _history()),
    ]);
  }

  // ── Today ────────────────────────────────────────────────────────────────

  Widget _today() {
    if (_loadingToday) return const Center(child: CircularProgressIndicator());
    if (_errorToday != null) return ErrorState(message: _errorToday!, onRetry: _loadToday);

    int count(String s) => _workers.where((w) => w.status == s).length;
    final filters = <(String, String, int)>[
      ('ALL', 'All', _workers.length),
      ('PRESENT', 'On site', count('PRESENT')),
      ('INCOMPLETE', 'Off site', count('INCOMPLETE')),
      ('CHECKED_OUT', 'Checked out', count('CHECKED_OUT')),
      ('ABSENT', 'Absent', count('ABSENT')),
    ];
    final q = _query.toLowerCase();
    final shown = _workers.where((w) {
      if (_filter != 'ALL' && w.status != _filter) return false;
      if (q.isEmpty) return true;
      return w.fullName.toLowerCase().contains(q) || w.username.toLowerCase().contains(q);
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: const InputDecoration(
              hintText: 'Search worker', prefixIcon: Icon(Icons.search_rounded)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: SegmentBar(
          scrollable: true,
          items: [for (final f in filters) (f.$1, '${f.$2} · ${f.$3}')],
          value: _filter,
          colors: {'PRESENT': AppTheme.accentGreen, 'INCOMPLETE': AppTheme.amber},
          onChanged: (v) => setState(() => _filter = v),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadToday,
          child: shown.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 60),
                  EmptyState(icon: Icons.groups_outlined, title: 'No workers match'),
                ])
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _WorkerTile(
                    worker: shown[i],
                    onTap: () => _showWorker(shown[i]),
                  ),
                ),
        ),
      ),
    ]);
  }

  void _showWorker(WorkerStatus w) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: AppTheme.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _WorkerSheet(worker: w),
    );
  }

  // ── History ──────────────────────────────────────────────────────────────

  Widget _history() {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: OutlinedButton.icon(
        onPressed: _pickRange,
        icon: const Icon(Icons.calendar_month_rounded, size: 18),
        label: Text('${fmtDate(_range.start)}  →  ${fmtDate(_range.end)}'),
      ),
    );
    if (_loadingHist) {
      return Column(children: [header, const Expanded(child: Center(child: CircularProgressIndicator()))]);
    }
    if (_errorHist != null) {
      return Column(children: [
        header,
        Expanded(child: ErrorState(message: _errorHist!, onRetry: _loadHistory)),
      ]);
    }
    final workers = _records.map((r) => r.workerId).toSet().length;
    final withDur = _records.where((r) => r.duration != null).toList();
    final avg = withDur.isEmpty
        ? null
        : Duration(
            seconds: withDur.fold<int>(0, (s, r) => s + r.duration!.inSeconds) ~/
                withDur.length);

    return Column(children: [
      header,
      if (_records.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Expanded(
                child: KpiTile(
                    label: 'Records',
                    compact: true,
                    height: 128,
                    value: '${_records.length}',
                    color: AppTheme.accent,
                    icon: Icons.fact_check_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: KpiTile(
                    label: 'Workers',
                    compact: true,
                    height: 128,
                    value: '$workers',
                    color: AppTheme.aiColor,
                    icon: Icons.groups_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: KpiTile(
                    label: 'Avg on site',
                    compact: true,
                    height: 128,
                    value: avg == null ? '—' : fmtDuration(avg),
                    color: AppTheme.accentGreen,
                    icon: Icons.timer_rounded)),
          ]),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadHistory,
          child: _records.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 60),
                  EmptyState(
                      icon: Icons.event_busy_rounded,
                      title: 'No attendance in this range'),
                ])
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _records.length,
                  itemBuilder: (_, i) => AttendanceTile(record: _records[i]),
                ),
        ),
      ),
    ]);
  }
}

class _WorkerTile extends StatelessWidget {
  final WorkerStatus worker;
  final VoidCallback onTap;
  const _WorkerTile({required this.worker, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = worker;
    final c = presenceColor(w.status);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(children: [
        UserAvatar(userId: w.workerId, name: w.fullName, size: 44, ringColor: c),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w.fullName,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 16.5)),
            const SizedBox(height: 3),
            Text(
              w.lastSeen == null
                  ? 'No location yet'
                  : (w.status == 'INCOMPLETE' && w.siteDistance != null
                      ? '${fmtMeters(w.siteDistance!)} from ${w.siteName.isEmpty ? 'site' : w.siteName} · ${fmtTime(w.lastSeen)}'
                      : '${w.zone.isEmpty ? 'Location' : w.zone} · ${fmtTime(w.lastSeen)}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: w.status == 'INCOMPLETE' ? AppTheme.amber : AppTheme.textMuted,
                  fontSize: 13,
                  fontWeight: w.status == 'INCOMPLETE' ? FontWeight.w700 : FontWeight.w500),
            ),
          ]),
        ),
        Pill(w.statusLabel.toUpperCase(), color: c),
      ]),
    );
  }
}

class _WorkerSheet extends StatefulWidget {
  final WorkerStatus worker;
  const _WorkerSheet({required this.worker});

  @override
  State<_WorkerSheet> createState() => _WorkerSheetState();
}

class _WorkerSheetState extends State<_WorkerSheet> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>>? _events;

  Future<void> _loadActivity() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ev = await MonitoringService.workerActivity(
          context.read<AuthService>(), widget.worker.workerId,
          date: fmtDate(DateTime.now()));
      if (!mounted) return;
      setState(() {
        _events = ev;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('MonitoringException: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.worker;
    final c = presenceColor(w.status);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.fullName,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                Text('@${w.username}',
                    style: TextStyle(color: AppTheme.textMuted)),
              ]),
            ),
            Pill(w.statusLabel.toUpperCase(), color: c),
          ]),
          const SizedBox(height: 18),
          AppCard(
            child: Column(children: [
              _row('Zone', w.zone.isEmpty ? '—' : w.zone),
              _row('Assigned site', w.siteName.isEmpty ? '—' : w.siteName),
              _row(
                  'Distance from site',
                  w.siteDistance == null
                      ? (w.insideProject == null ? '—' : (w.insideProject! ? 'On site' : 'Off site'))
                      : (w.siteDistance! < kOnSiteToleranceMeters ? 'On site' : fmtMeters(w.siteDistance!))),
              _row('Last seen', fmtDateTime(w.lastSeen)),
              _row('Coordinates',
                  w.lat == null ? '—' : '${w.lat!.toStringAsFixed(5)}, ${w.lon!.toStringAsFixed(5)}'),
            ]),
          ),
          const SizedBox(height: 14),
          if (context.read<AuthService>().profile?.appRole == AppRole.superAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => WorkerPathScreen(workerId: w.workerId, name: w.fullName)),
                ),
                icon: const Icon(Icons.route_rounded),
                label: const Text('VIEW ROUTE ON MAP'),
              ),
            ),
          if (_events == null)
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadActivity,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.timeline_rounded, size: 18),
              label: const Text("TODAY'S ACTIVITY LOG"),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: TextStyle(color: AppTheme.amber, height: 1.4)),
            ),
          if (_events != null) ...[
            const SectionTitle("Today's activity"),
            if (_events!.isEmpty)
              Text('No events today.',
                  style: TextStyle(color: AppTheme.textSecondary))
            else
              for (final e in _events!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    SizedBox(
                      width: 52,
                      child: Text(fmtTime(parseDate(e['timestamp'])),
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text(
                        '${e['event_type']}'.replaceAll('_', ' ') +
                            ('${e['current_zone'] ?? ''}'.isEmpty ? '' : ' · ${e['current_zone']}'),
                        style: TextStyle(color: AppTheme.textPrimary),
                      ),
                    ),
                  ]),
                ),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
              width: 120,
              child: Text(k, style: TextStyle(color: AppTheme.textMuted))),
          Expanded(
              child: Text(v,
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
        ]),
      );
}
