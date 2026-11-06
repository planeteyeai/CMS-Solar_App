import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/attendance.dart';
import '../../models/site_task.dart';
import '../../services/auth_service.dart';
import '../../services/monitoring_service.dart';
import '../../services/task_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_widgets.dart';
import '../../widgets/ui_kit.dart';

/// History: every progress update I saved (from the database) + my attendance.
class SeHistoryTab extends StatefulWidget {
  const SeHistoryTab({super.key});

  @override
  State<SeHistoryTab> createState() => SeHistoryTabState();
}

class SeHistoryTabState extends State<SeHistoryTab> {
  int _segment = 0; // 0 updates, 1 attendance
  bool _loading = true;
  String? _error;
  List<TaskUpdate> _updates = [];
  List<AttendanceRecord> _attendance = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  Future<void> reload() async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final store = context.read<TaskStore>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        TaskApi.fetchFeed(auth, projectId: store.projectId, userId: auth.profile!.id, limit: 200),
        MonitoringService.myAttendance(auth),
      ]);
      if (!mounted) return;
      setState(() {
        _updates = results[0] as List<TaskUpdate>;
        _attendance = results[1] as List<AttendanceRecord>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').replaceFirst('TaskException: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('History',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6)),
              Text('Audit trail, AI inspections and attendance records',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentBar(
            items: [
              ('0', 'Updates (${_updates.length})'),
              ('1', 'Attendance (${_attendance.length})'),
            ],
            value: '$_segment',
            onChanged: (v) => setState(() => _segment = int.parse(v)),
          ),
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(message: _error!, onRetry: reload);
    return RefreshIndicator(
      onRefresh: reload,
      child: _segment == 0 ? _updatesList() : _attendanceList(),
    );
  }

  Widget _updatesList() {
    if (_updates.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        EmptyState(
            icon: Icons.history_toggle_off_rounded,
            title: 'No progress updates yet',
            message: 'Open a task, add photos, run the AI estimate and save to build your history.'),
      ]);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _updates.length,
      itemBuilder: (_, i) => TaskUpdateTile(
        update: _updates[i],
        showUser: false,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TaskUpdateDetailScreen(update: _updates[i])),
        ),
      ),
    );
  }

  Widget _attendanceList() {
    if (_attendance.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        EmptyState(
            icon: Icons.event_busy_rounded,
            title: 'No attendance yet',
            message: 'Check in from the Home tab to start your record.'),
      ]);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _attendance.length,
      itemBuilder: (_, i) => AttendanceTile(record: _attendance[i], showWorker: false),
    );
  }
}

/// One attendance row (used by every role).
class AttendanceTile extends StatelessWidget {
  final AttendanceRecord record;
  final bool showWorker;
  const AttendanceTile({super.key, required this.record, this.showWorker = true});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final c = presenceColor(r.status);
    final dur = r.duration;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              showWorker
                  ? (r.workerUsername.isNotEmpty ? r.workerUsername : 'Worker #${r.workerId}')
                  : fmtDate(r.date),
              style: TextStyle(
                  color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          if (showWorker)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(fmtDate(r.date),
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ),
          Pill(r.status.isEmpty ? '—' : r.status, color: c, round: true),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _cell('IN', fmtTime(r.checkIn))),
          Expanded(child: _cell('OUT', fmtTime(r.checkOut))),
          Expanded(child: _cell('DURATION', dur == null ? '—' : fmtDuration(dur))),
        ]),
        if (r.zone.isNotEmpty || r.projectName.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            [if (r.projectName.isNotEmpty) r.projectName, if (r.zone.isNotEmpty) r.zone].join(' · '),
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ]),
    );
  }

  Widget _cell(String l, String v) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l,
            style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 3),
        Text(v, style: AppTheme.numStyle(size: 16, letterSpacing: -0.3)),
      ]);
}
