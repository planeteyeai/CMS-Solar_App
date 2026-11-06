import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/attendance.dart';
import '../models/site_task.dart';
import '../services/auth_service.dart';
import '../services/task_service.dart';
import '../theme/app_theme.dart';
import 'ai_report.dart';
import 'ui_kit.dart';

Color taskColor(SiteTask t) =>
    t.isDone ? AppTheme.accentGreen : (t.isInProgress ? AppTheme.accent : AppTheme.textMuted);

Color progressColor(double p) =>
    p >= 100 ? AppTheme.accentGreen : (p > 0 ? AppTheme.accent : AppTheme.textMuted);

Uint8List? decodeB64(String b) {
  try {
    final i = b.indexOf(',');
    return base64Decode(b.startsWith('data:') && i > 0 ? b.substring(i + 1) : b);
  } catch (_) {
    return null;
  }
}

/// "Site Work Progress" card: overall ring, bar and Done / In Progress / Pending.
class ProgressSummaryCard extends StatelessWidget {
  final TaskSummary summary;
  final String title;
  const ProgressSummaryCard({super.key, required this.summary, this.title = 'Site Work Progress'});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          PercentRing(percent: s.overall, color: progressColor(s.overall), size: 92),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2)),
              const SizedBox(height: 3),
              Text('${s.done} of ${s.total} tasks completed',
                  style: TextStyle(
                      color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (s.overall / 100).clamp(0.0, 1.0).toDouble(),
                  minHeight: 10,
                  backgroundColor: AppTheme.surfaceElev,
                  color: AppTheme.accent,
                ),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _Stat(Icons.check_circle_rounded, AppTheme.accentGreen, '${s.done}', 'Done'),
          const SizedBox(width: 10),
          _Stat(Icons.schedule_rounded, AppTheme.amber, '${s.inProgress}', 'In Progress'),
          const SizedBox(width: 10),
          _Stat(Icons.radio_button_unchecked_rounded, AppTheme.textMuted, '${s.pending}', 'Pending'),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Stat(this.icon, this.color, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final light = AppTheme.isLight;
    final fg = AppTheme.onTint(color);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(light ? 0.08 : 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(light ? 0.30 : 0.38)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppTheme.numStyle(size: 30, color: fg, height: 1.1, letterSpacing: -1)),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class TaskStatusPill extends StatelessWidget {
  final SiteTask task;
  const TaskStatusPill(this.task, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = task.isDone ? AppTheme.accentGreen : (task.isInProgress ? AppTheme.amber : AppTheme.textSecondary);
    return Pill(
      task.statusLabel,
      color: c,
      icon: task.isDone
          ? Icons.check_circle_outline_rounded
          : (task.isInProgress ? Icons.schedule_rounded : Icons.schedule_rounded),
    );
  }
}

/// Numbered task row: index badge, progress ring with the percentage inside, status tag.
class TaskRow extends StatelessWidget {
  final SiteTask task;
  final VoidCallback onTap;
  const TaskRow({super.key, required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = task;
    final c = taskColor(t);
    final fg = AppTheme.onTint(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.isPending ? AppTheme.border : c.withOpacity(AppTheme.isLight ? 0.45 : 0.6)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.isPending ? AppTheme.surfaceElev : c.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('${t.order}',
                      style: AppTheme.numStyle(
                          size: 13, color: t.isPending ? AppTheme.textSecondary : fg, letterSpacing: 0)),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (t.progress / 100).clamp(0.0, 1.0).toDouble(),
                        strokeWidth: 4,
                        backgroundColor: AppTheme.surfaceElev,
                        color: c,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Text('${t.progress.round()}%',
                        style: AppTheme.numStyle(size: 10.5, color: fg, letterSpacing: -0.4)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                TaskStatusPill(t),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 22),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class DeltaChip extends StatelessWidget {
  final double before;
  final double after;
  const DeltaChip({super.key, required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final d = after - before;
    final c = d > 0.4 ? AppTheme.accentGreen : (d < -0.4 ? AppTheme.accentRed : AppTheme.textSecondary);
    final sign = d > 0.4 ? '+' : '';
    return Pill('${before.round()}% → ${after.round()}%  ($sign${d.round()})', color: c,
        icon: d >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded);
  }
}

/// One saved update in a list.
class TaskUpdateTile extends StatelessWidget {
  final TaskUpdate update;
  final bool showTask;
  final bool showUser;
  final VoidCallback onTap;
  const TaskUpdateTile({
    super.key,
    required this.update,
    required this.onTap,
    this.showTask = true,
    this.showUser = true,
  });

  @override
  Widget build(BuildContext context) {
    final u = update;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(showTask ? '${u.taskOrder}. ${u.taskName}' : fmtDateTime(u.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 15.5)),
          ),
          Pill('${u.after.round()}%', color: progressColor(u.after)),
        ]),
        const SizedBox(height: 3),
        Text(
          [
            if (showTask) fmtDateTime(u.createdAt),
            if (showUser && u.userName.isNotEmpty) u.userName,
            if (u.projectName.isNotEmpty && showUser) u.projectName,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          DeltaChip(before: u.before, after: u.after),
          if (u.aiPercent != null)
            Pill(u.edited ? 'AI ${u.aiPercent!.round()}% · EDITED' : 'AI ${u.aiPercent!.round()}%',
                color: u.edited ? AppTheme.amber : AppTheme.aiColor, icon: Icons.smart_toy_rounded),
          if (u.riskLevel != 'LOW') Pill('${u.riskLevel} RISK', color: softRiskColor(u.riskLevel)),
          if (u.hazardCount > 0)
            Pill('${u.hazardCount} HAZARD${u.hazardCount == 1 ? '' : 'S'}',
                color: softRiskColor(u.worstHazardSeverity), icon: Icons.shield_outlined),
          if (u.photoCount > 0)
            Pill('${u.photoCount}', color: AppTheme.textSecondary, icon: Icons.photo_rounded),
          if (u.videoCount > 0)
            Pill('${u.videoCount}', color: AppTheme.textSecondary, icon: Icons.videocam_rounded),
        ]),
        if (u.summary.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElev,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(u.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
          ),
        ],
      ]),
    );
  }
}

/// Everything about one saved update.
class TaskUpdateDetailScreen extends StatefulWidget {
  final TaskUpdate update;
  const TaskUpdateDetailScreen({super.key, required this.update});

  @override
  State<TaskUpdateDetailScreen> createState() => _TaskUpdateDetailScreenState();
}

class _TaskUpdateDetailScreenState extends State<TaskUpdateDetailScreen> {
  late TaskUpdate _u = widget.update;

  @override
  void initState() {
    super.initState();
    // Feed responses omit photos; fetch the task history to get them.
    if (_u.photos.isEmpty &&
        _u.photoPaths.isEmpty &&
        _u.evidence.isEmpty &&
        (_u.photoCount > 0 || _u.evidenceCount > 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final (_, history) =
              await TaskApi.fetchDetail(context.read<AuthService>(), _u.taskId);
          final full = history.where((h) => h.id == _u.id).toList();
          if (mounted && full.isNotEmpty) setState(() => _u = full.first);
        } catch (_) {}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    final a = u.analysis;
    String s(dynamic v) => v?.toString() ?? '';
    final equipment = a['equipment'] is List ? (a['equipment'] as List).map((e) => '$e').toList() : <String>[];
    final safety = a['safety_findings'] is List ? (a['safety_findings'] as List).map((e) => '$e').toList() : <String>[];
    final recs = a['recommendations'] is List ? (a['recommendations'] as List).map((e) => '$e').toList() : <String>[];
    final report = TaskAnalysis.fromAi(a); // detailed report + hazards (newer updates only)

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('PROGRESS UPDATE')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          AppCard(
            child: Row(children: [
              PercentRing(percent: u.after, color: progressColor(u.after), size: 104),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${u.taskOrder}. ${u.taskName}',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w900, height: 1.2)),
                  const SizedBox(height: 8),
                  DeltaChip(before: u.before, after: u.after),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (u.userName.isNotEmpty) Pill(u.userName, color: AppTheme.accent, icon: Icons.person_rounded),
            if (u.projectName.isNotEmpty) Pill(u.projectName, color: AppTheme.aiColor, icon: Icons.apartment_rounded),
            Pill(fmtDateTime(u.createdAt), color: AppTheme.textSecondary, icon: Icons.schedule_rounded),
            if (u.lat != null && u.lon != null)
              Pill('${u.lat!.toStringAsFixed(4)}, ${u.lon!.toStringAsFixed(4)}',
                  color: AppTheme.textSecondary, icon: Icons.location_on_rounded),
          ]),

          if (u.aiPercent != null) ...[
            const SectionTitle('AI estimate vs final'),
            AppCard(
              child: Column(children: [
                _row('AI estimated', '${u.aiPercent!.round()}%'),
                _row('Final (saved)', '${u.after.round()}%'),
                _row('Edited by engineer', u.edited ? 'Yes' : 'No'),
                if (s(a['confidence']).isNotEmpty) _row('AI confidence', '${a['confidence']}%'),
                _row('Risk', u.riskLevel),
                if (s(a['image_quality']).isNotEmpty) _row('Photo quality', s(a['image_quality'])),
              ]),
            ),
          ],

          if (u.summary.isNotEmpty) ...[
            const SectionTitle('Summary'),
            AppCard(
                child: Text(u.summary,
                    style: TextStyle(color: AppTheme.textPrimary, height: 1.5, fontSize: 14.5))),
          ],
          ..._quantitySection(a),
          if (report.hasReport) ...[
            const SizedBox(height: 22),
            AppCard(
              borderColor: AppTheme.aiColor.withOpacity(0.4),
              child: AiReportView(analysis: report, showOverview: false),
            ),
          ],
          if (u.edited && u.aiSummary.isNotEmpty && u.aiSummary != u.summary) ...[
            const SectionTitle('Original AI summary'),
            AppCard(
                child: Text(u.aiSummary,
                    style: TextStyle(color: AppTheme.textSecondary, height: 1.5))),
          ],
          if (u.findings.isNotEmpty) ...[
            const SectionTitle('Findings'),
            AppCard(child: Column(children: [for (final f in u.findings) _bullet(f, AppTheme.accent)])),
          ],
          if (!report.hasReport && safety.isNotEmpty) ...[
            const SectionTitle('Safety'),
            AppCard(child: Column(children: [for (final f in safety) _bullet(f, AppTheme.accentRed)])),
          ],
          if (equipment.isNotEmpty) ...[
            const SectionTitle('Equipment seen'),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final e in equipment) Pill(e, color: AppTheme.accent)]),
          ],
          if (recs.isNotEmpty) ...[
            const SectionTitle('Recommendations'),
            AppCard(child: Column(children: [for (final f in recs) _bullet(f, AppTheme.aiColor)])),
          ],
          if (u.remarks.isNotEmpty) ...[
            const SectionTitle('Remarks'),
            AppCard(child: Text(u.remarks, style: TextStyle(color: AppTheme.textPrimary, height: 1.5))),
          ],

          if (u.evidence.isNotEmpty) ...[
            SectionTitle('Evidence photos (${u.evidence.length})'),
            for (final ev in u.evidence) _evidenceCard(ev),
          ],
          if (u.photoPaths.isNotEmpty) ...[
            const SectionTitle('Photos'),
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: u.photoPaths.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final f = File(u.photoPaths[i]);
                  if (!f.existsSync()) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.black,
                        insetPadding: const EdgeInsets.all(8),
                        child: InteractiveViewer(child: Image.file(f)),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AspectRatio(
                          aspectRatio: 4 / 3, child: Image.file(f, fit: BoxFit.cover, cacheWidth: 500)),
                    ),
                  );
                },
              ),
            ),
          ],
          if (u.photos.isNotEmpty) ...[
            const SectionTitle('Photos'),
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: u.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final b = decodeB64(u.photos[i]);
                  if (b == null) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.black,
                        insetPadding: const EdgeInsets.all(8),
                        child: InteractiveViewer(child: Image.memory(b)),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AspectRatio(aspectRatio: 4 / 3, child: Image.memory(b, fit: BoxFit.cover)),
                    ),
                  );
                },
              ),
            ),
          ],
          if (u.media.isNotEmpty) ...[
            const SectionTitle('Evidence files'),
            AppCard(
              child: Column(children: [
                for (final m in u.media)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Icon(s(m['type']) == 'video' ? Icons.videocam_rounded : Icons.photo_rounded,
                          size: 18, color: AppTheme.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s(m['name']),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                      ),
                      if (s(m['type']) == 'video')
                        Text(_dur(toInt(m['duration_seconds'])),
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    ]),
                  ),
                const SizedBox(height: 4),
                Text('Videos are stored on the engineer\'s device.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _evidenceCard(EvidenceItem ev) {
    final a = ev.analysis;
    final desc = (a['description'] ?? '').toString();
    final obs = a['observations'] is List ? (a['observations'] as List).map((e) => '$e').toList() : <String>[];
    final safety = a['safety_findings'] is List ? (a['safety_findings'] as List).map((e) => '$e').toList() : <String>[];
    final risk = (a['risk_level'] ?? '').toString().toUpperCase();
    final vis = a['visible_progress_percent'];
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (ev.url != null)
          GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.black,
                insetPadding: const EdgeInsets.all(8),
                child: InteractiveViewer(child: Image.network(ev.url!)),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.network(
                  ev.url!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  errorBuilder: (_, __, ___) => Center(
                      child: Icon(Icons.broken_image_outlined, color: AppTheme.textMuted, size: 40)),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(ev.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              if (risk.isNotEmpty) Pill('$risk RISK', color: softRiskColor(risk)),
              if (vis is num) ...[
                const SizedBox(width: 6),
                Pill('${vis.round()}% visible', color: AppTheme.accent),
              ],
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(desc, style: TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: 13)),
            ],
            for (final o in obs)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('• $o', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
              ),
            for (final o in safety)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('⚠ $o', style: TextStyle(color: AppTheme.accentRed, fontSize: 12.5)),
              ),
            if (desc.isEmpty && obs.isEmpty && safety.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('No AI analysis stored for this photo.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
          ]),
        ),
      ]),
    );
  }

  static String _dur(int s) => '${two(s ~/ 60)}:${two(s % 60)}';

  List<Widget> _quantitySection(Map<String, dynamic> analysis) {
    final quantities = QuantityReading.listFrom(analysis['quantities']);
    if (quantities.isEmpty) return const [];
    final edited = analysis['quantities_edited'] == true;
    return [
      const SectionTitle('Measured quantities'),
      if (edited)
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Edited by the site engineer before saving.',
              style: TextStyle(color: AppTheme.amber, fontSize: 12.5)),
        ),
      for (final q in quantities)
        AppCard(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(q.item.isEmpty ? 'Item' : q.item,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 6),
            _row('Number', q.number.isEmpty ? '—' : q.number),
            _row('Size', q.size.isEmpty ? '—' : q.size),
            _row('Material', q.material.isEmpty ? '—' : q.material),
            _row('Quantity', q.quantityLabel.isEmpty ? '—' : q.quantityLabel),
          ]),
        ),
    ];
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 140, child: Text(k, style: TextStyle(color: AppTheme.textMuted, fontSize: 13))),
          Expanded(
              child: Text(v,
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5))),
        ]),
      );

  Widget _bullet(String t, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 7, color: c),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: TextStyle(color: AppTheme.textPrimary, height: 1.4))),
        ]),
      );
}

/// Read-only history of one task (used by Team Lead / Project Manager / Superadmin).
class TaskHistoryScreen extends StatefulWidget {
  final SiteTask task;
  const TaskHistoryScreen({super.key, required this.task});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  bool _loading = true;
  String? _error;
  late SiteTask _task = widget.task;
  List<TaskUpdate> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (t, h) = await TaskApi.fetchDetail(context.read<AuthService>(), widget.task.id);
      if (!mounted) return;
      setState(() {
        _task = t;
        _history = h;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('TaskException: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: Text('TASK ${t.order} OF HISTORY')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    children: [
                      AppCard(
                        child: Row(children: [
                          PercentRing(percent: t.progress, color: taskColor(t), size: 84),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t.name,
                                  style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 6),
                              TaskStatusPill(t),
                              if (t.updatedAt != null) ...[
                                const SizedBox(height: 6),
                                Text('Updated ${fmtDateTime(t.updatedAt)}'
                                    '${t.updatedBy.isEmpty ? '' : ' by ${t.updatedBy}'}',
                                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                              ],
                            ]),
                          ),
                        ]),
                      ),
                      if (t.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        AppCard(
                            child: Text(t.description,
                                style: TextStyle(color: AppTheme.textSecondary, height: 1.45))),
                      ],
                      SectionTitle('Update history (${_history.length})'),
                      if (_history.isEmpty)
                        AppCard(
                            child: Text('No updates saved for this task yet.',
                                style: TextStyle(color: AppTheme.textSecondary)))
                      else
                        for (final u in _history)
                          TaskUpdateTile(
                            update: u,
                            showTask: false,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => TaskUpdateDetailScreen(update: u))),
                          ),
                    ],
                  ),
                ),
    );
  }
}
