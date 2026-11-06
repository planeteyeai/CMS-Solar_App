import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/attendance.dart';
import '../../models/site_task.dart';
import '../../services/task_service.dart';
import '../../services/auth_service.dart';
import '../../services/monitoring_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_widgets.dart';
import '../../services/site_status_service.dart';
import '../../widgets/ui_kit.dart';
import '../../widgets/user_avatar.dart';

class OverviewTab extends StatefulWidget {
  final ValueNotifier<String> project;
  const OverviewTab({super.key, required this.project});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  Timer? _timer;
  bool _loading = true;
  String? _error;
  LivelinessData? _live;
  WorkersData? _workers; // on-site / off-site judged against each engineer's OWN site
  List<TaskUpdate> _updates = [];
  TaskSummary? _progress;
  DateTime? _updated;

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    });
  }

  @override
  void dispose() {
    widget.project.removeListener(_load);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final project = widget.project.value;
    if (!silent) setState(() => _loading = true);
    try {
      final live = await MonitoringService.liveliness(auth, project: project);
      WorkersData? workers;
      try {
        workers = await MonitoringService.workersAdjusted(auth, project: project);
      } catch (_) {/* fall back to the server's own counts */}
      List<TaskUpdate> updates = [];
      TaskSummary? progress;
      try {
        final all = await TaskApi.fetchFeed(auth, limit: 300);
        updates = all.where((u) => project.isEmpty || u.projectName == project).toList();
      } catch (_) {/* attendance still useful without task data */}
      if (project.isNotEmpty) {
        for (final p in auth.profile!.assignedProjects) {
          if (p.projectName == project) {
            try {
              progress = (await TaskApi.fetchTasks(auth, projectId: p.id)).summary;
            } catch (_) {}
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _live = live;
        _workers = workers;
        _updates = updates;
        _progress = progress;
        _error = null;
        _loading = false;
        _updated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _live == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _live == null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    final l = _live!;
    final today = DateTime.now();
    final todayCount = _updates
        .where((u) =>
            u.createdAt != null &&
            u.createdAt!.year == today.year &&
            u.createdAt!.month == today.month &&
            u.createdAt!.day == today.day)
        .length;
    final high = _updates.where((u) => u.riskLevel == 'HIGH').length;

    // Counts: judged against each engineer's own assigned site (under 5 m = on site).
    final ws = _workers?.workers;
    final onSite = ws == null ? l.present : ws.where((w) => w.status == 'PRESENT').length;
    final offSiteList = ws == null ? <WorkerStatus>[] : ws.where((w) => w.status == 'INCOMPLETE').toList();
    final offSite = ws == null ? l.offsite : offSiteList.length;
    final absent = ws == null ? l.absent : ws.where((w) => w.status == 'ABSENT').length;
    final maxZone = l.activeZones.fold<int>(
        1, (m, z) => toInt(z['worker_count']) > m ? toInt(z['worker_count']) : m);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 162,
            ),
            children: [
              KpiTile(
                  label: 'On site now',
                  value: '$onSite',
                  color: AppTheme.accentGreen,
                  icon: Icons.how_to_reg_rounded),
              KpiTile(
                  label: 'Off site',
                  value: '$offSite',
                  color: AppTheme.amber,
                  icon: Icons.location_off_rounded),
              KpiTile(
                  label: 'Absent today',
                  value: '$absent',
                  color: AppTheme.accentRed,
                  icon: Icons.person_off_rounded),
              KpiTile(
                  label: 'Attendance records',
                  value: '${l.attendanceCount}',
                  color: AppTheme.accent,
                  icon: Icons.fact_check_rounded),
            ],
          ),
          if (_updated != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Updated ${fmtTime(_updated)} · refreshes every 30 s\n'
                  'On / off site is measured from each engineer\'s own assigned site; within ${kOnSiteToleranceMeters.round()} m counts as on site.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.4)),
            ),

          // Who is off site, and how far from THEIR site
          if (offSiteList.isNotEmpty) ...[
            const SectionTitle('Off site now'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: [
                for (final w in offSiteList)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(children: [
                      UserAvatar(userId: w.workerId, name: w.fullName, size: 44, ringColor: AppTheme.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(w.fullName,
                              style: TextStyle(
                                  color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 15.5)),
                          if (w.siteName.isNotEmpty)
                            Text(w.siteName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                        ]),
                      ),
                      Text(w.siteDistance == null ? 'Off site' : fmtMeters(w.siteDistance!),
                          style: TextStyle(
                              color: AppTheme.amber, fontWeight: FontWeight.w900, fontSize: 20)),
                    ]),
                  ),
              ]),
            ),
          ],

          if (_progress != null) ...[
            const SectionTitle('Site progress'),
            ProgressSummaryCard(summary: _progress!, title: 'Overall progress'),
          ],

          const SectionTitle('Task updates'),
          Row(children: [
            Expanded(
                child: KpiTile(
                    label: 'Saved updates',
                    value: '${_updates.length}',
                    compact: true,
                    height: 132,
                    color: AppTheme.aiColor,
                    icon: Icons.task_alt_rounded)),
            const SizedBox(width: 12),
            Expanded(
                child: KpiTile(
                    label: 'Today',
                    value: '$todayCount',
                    compact: true,
                    height: 132,
                    color: AppTheme.accent,
                    icon: Icons.today_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: KpiTile(
                    label: 'High risk',
                    value: '$high',
                    compact: true,
                    height: 132,
                    color: high > 0 ? AppTheme.accentRed : AppTheme.accentGreen,
                    icon: Icons.warning_amber_rounded)),
          ]),
          if (_updates.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._updates.take(3).map((u) => TaskUpdateTile(
                  update: u,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TaskUpdateDetailScreen(update: u)),
                  ),
                )),
          ],

          const SectionTitle('Active zones'),
          if (l.activeZones.isEmpty)
            AppCard(
                child: Text('No one is in a defined zone right now.',
                    style: TextStyle(color: AppTheme.textSecondary)))
          else
            AppCard(
              child: Column(children: [
                for (final z in l.activeZones)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      SizedBox(
                        width: 110,
                        child: Text('${z['zone']}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: toInt(z['worker_count']) / maxZone,
                            minHeight: 10,
                            backgroundColor: AppTheme.border,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text('${z['worker_count']}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: AppTheme.accent, fontWeight: FontWeight.w900)),
                      ),
                    ]),
                  ),
              ]),
            ),

          const SectionTitle('Recent check-ins'),
          if (l.recentCheckIns.isEmpty)
            AppCard(
                child: Text('No check-ins yet today.',
                    style: TextStyle(color: AppTheme.textSecondary)))
          else
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                for (final c in l.recentCheckIns)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: AppTheme.accentGreen.withOpacity(0.15),
                            shape: BoxShape.circle),
                        child: Icon(Icons.login_rounded,
                            size: 17, color: AppTheme.accentGreen),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${c['worker_full_name'] ?? c['worker_username'] ?? ''}',
                              style: TextStyle(
                                  color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                          Text(
                            [
                              if ('${c['zone'] ?? ''}'.isNotEmpty) '${c['zone']}',
                              if ('${c['project_name'] ?? ''}'.isNotEmpty) '${c['project_name']}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                          ),
                        ]),
                      ),
                      Text(fmtTime(parseDate(c['timestamp'])),
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
        ],
      ),
    );
  }
}
