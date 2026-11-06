import 'package:flutter/material.dart';

import '../models/site_task.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

/// The assistant's notes on a scan: work status, quality, site conditions, safety notes
/// and suggested follow-ups.
///
/// Safety observations are shown in the lower part of the report in calm colours (no red,
/// no big counters), as advice to review and not as an alarm.
class AiReportView extends StatelessWidget {
  final TaskAnalysis analysis;

  /// Show the assistant's overview paragraph (hidden when the summary is shown elsewhere).
  final bool showOverview;
  const AiReportView({super.key, required this.analysis, this.showOverview = true});

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Row(children: [
        const AiBadge(size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Site Assistant Notes',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
        ),
        Pill('${a.riskLevel} RISK', color: softRiskColor(a.riskLevel)),
      ]),

      if (showOverview && a.summary.isNotEmpty) ...[
        const SizedBox(height: 14),
        _Block(
          icon: Icons.notes_rounded,
          title: 'Overview',
          color: AppTheme.accent,
          child: Text(a.summary,
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, height: 1.55)),
        ),
      ],

      // 1. Work status and quality come first
      if (a.workCompleted.isNotEmpty)
        _ListBlock('Work completed', Icons.check_circle_outline_rounded, AppTheme.accentGreen, a.workCompleted),
      if (a.workInProgress.isNotEmpty)
        _ListBlock('Work in progress', Icons.autorenew_rounded, AppTheme.accent, a.workInProgress),
      if (a.workRemaining.isNotEmpty)
        _ListBlock('Work remaining', Icons.pending_actions_rounded, AppTheme.textSecondary, a.workRemaining),
      if (a.qualityObservations.isNotEmpty)
        _ListBlock('Quality and workmanship', Icons.verified_outlined, AppTheme.aiColor, a.qualityObservations),

      // 2. Site conditions
      if (a.ppeStatus.isNotEmpty || a.housekeeping.isNotEmpty || a.environment.isNotEmpty || a.peopleTotal > 0) ...[
        const SizedBox(height: 12),
        _Block(
          icon: Icons.engineering_outlined,
          title: 'Site conditions',
          color: AppTheme.accentGreen,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (a.ppeStatus.isNotEmpty) _Labelled('PPE', a.ppeStatus),
            if (a.housekeeping.isNotEmpty) _Labelled('Housekeeping', a.housekeeping),
            if (a.environment.isNotEmpty) _Labelled('Weather and ground', a.environment),
            if (a.peopleTotal > 0)
              _Labelled('People visible', '${a.peopleTotal} (${a.peopleWithPpe} with full PPE)'),
          ]),
        ),
      ],

      // 3. Safety notes: lower down, calm and low-key
      const SizedBox(height: 12),
      _SafetyNotes(analysis: a),

      // 4. Suggested follow-ups (last)
      if (a.immediateActions.isNotEmpty) ...[
        const SizedBox(height: 12),
        _Block(
          icon: Icons.playlist_add_check_rounded,
          title: 'Suggested follow-ups',
          color: AppTheme.accent,
          child: Column(children: [
            for (var i = 0; i < a.immediateActions.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${i + 1}',
                        style: AppTheme.numStyle(size: 12, color: AppTheme.onTint(AppTheme.accent), letterSpacing: 0)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(a.immediateActions[i],
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, height: 1.45)),
                  ),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }
}

/// Safety observations in a soft card.
class _SafetyNotes extends StatelessWidget {
  final TaskAnalysis analysis;
  const _SafetyNotes({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final notes = analysis.hazards;
    return _Block(
      icon: Icons.shield_outlined,
      title: 'Safety notes',
      color: AppTheme.amber,
      trailing: notes.isEmpty
          ? null
          : Text('${notes.length}',
              style: AppTheme.numStyle(size: 14, color: AppTheme.textMuted, letterSpacing: 0)),
      child: notes.isEmpty
          ? Row(children: [
              Icon(Icons.check_circle_outline_rounded, color: AppTheme.accentGreen, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('No safety notes from this scan.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4)),
              ),
            ])
          : Column(children: [
              for (final n in notes) _SafetyNote(note: n),
            ]),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  final Hazard note;
  const _SafetyNote({required this.note});

  @override
  Widget build(BuildContext context) {
    final c = softRiskColor(note.severity);
    final light = AppTheme.isLight;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.amber.withOpacity(light ? 0.07 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.amber.withOpacity(light ? 0.28 : 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.shield_outlined, color: AppTheme.amber, size: 18),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(note.hazard,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35)),
          ),
          const SizedBox(width: 8),
          Text(note.severity,
              style: TextStyle(
                  color: AppTheme.onTint(c), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        ]),
        if (note.category.isNotEmpty || note.location.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            [if (note.category.isNotEmpty) note.category, if (note.location.isNotEmpty) note.location].join(' · '),
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
          ),
        ],
        if (note.action.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Suggested: ',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w700)),
            Expanded(
              child: Text(note.action,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.4)),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  const _Heading(this.text, this.icon, this.color, {this.trailing});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: AppTheme.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w800)),
        ),
        if (trailing != null) trailing!,
      ]);
}

class _Block extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Widget child;
  final Widget? trailing;
  const _Block({
    required this.icon,
    required this.title,
    required this.color,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElev.withOpacity(AppTheme.isLight ? 0.6 : 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Heading(title, icon, color, trailing: trailing),
          const SizedBox(height: 10),
          child,
        ]),
      );
}

class _ListBlock extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;
  const _ListBlock(this.title, this.icon, this.color, this.items);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _Block(
          icon: icon,
          title: title,
          color: color,
          child: Column(children: [
            for (final t in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Icon(Icons.circle, size: 6, color: color),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(t,
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, height: 1.45)),
                  ),
                ]),
              ),
          ]),
        ),
      );
}

class _Labelled extends StatelessWidget {
  final String label;
  final String text;
  const _Labelled(this.label, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9)),
          const SizedBox(height: 2),
          Text(text, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, height: 1.45)),
        ]),
      );
}
