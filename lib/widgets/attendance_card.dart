import 'package:flutter/material.dart';

import '../models/attendance.dart';
import '../services/checkin_service.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

class AttendanceCard extends StatelessWidget {
  final CheckInService svc;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  const AttendanceCard(
      {required this.svc, required this.onCheckIn, required this.onCheckOut});

  @override
  Widget build(BuildContext context) {
    final state = svc.state;
    final color = state == PresenceState.checkedIn
        ? AppTheme.accentGreen
        : state == PresenceState.checkedOut
            ? AppTheme.accent
            : AppTheme.textMuted;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('ATTENDANCE',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3)),
          const Spacer(),
          Pill(svc.statusLabel, color: color, icon: Icons.circle, round: true),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _Metric('CHECK-IN', fmtTime(svc.checkInTime))),
          const SizedBox(width: 10),
          Expanded(
              child: _Metric(
                  svc.isCheckedOut ? 'CHECK-OUT' : 'TIME ON SITE',
                  svc.isCheckedOut
                      ? fmtTime(svc.checkOutTime)
                      : (svc.checkInTime == null ? '—' : fmtDuration(svc.timeOnSite)))),
          if (svc.isCheckedOut) ...[
            const SizedBox(width: 10),
            Expanded(child: _Metric('TOTAL', fmtDuration(svc.timeOnSite))),
          ],
        ]),
        if (svc.today != null) ...[
          const SizedBox(height: 14),
          _LocationLine(svc: svc),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: svc.isCheckedIn ? AppTheme.accentRed : AppTheme.accentGreen,
              foregroundColor: svc.isCheckedIn
                  ? (AppTheme.isLight ? Colors.white : AppTheme.onPrimary)
                  : AppTheme.onGreen,
              disabledBackgroundColor: AppTheme.surfaceElev,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.0),
            ),
            onPressed: svc.busy ? null : (svc.isCheckedIn ? onCheckOut : onCheckIn),
            icon: svc.busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.textMuted))
                : Icon(svc.isCheckedIn ? Icons.logout_rounded : Icons.login_rounded),
            label: Text(svc.busy
                ? 'GETTING LOCATION…'
                : svc.isCheckedIn
                    ? 'CHECK OUT'
                    : svc.isCheckedOut
                        ? 'CHECK IN AGAIN'
                        : 'CHECK IN'),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElev,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.place_outlined,
                size: 16, color: svc.error != null ? AppTheme.amber : AppTheme.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                svc.error ??
                    (svc.isCheckedIn
                        ? 'Your location is recorded every ${CheckInService.pingInterval.inMinutes} minutes while you are checked in, even with the app in the background, so your site team can see your route. Check out to stop tracking.'
                        : 'Check-in records your GPS position and is visible to your team lead, project manager and superadmin.'),
                style: TextStyle(
                    color: svc.error != null ? AppTheme.amber : AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.45),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _LocationLine extends StatelessWidget {
  final CheckInService svc;
  const _LocationLine({required this.svc});

  @override
  Widget build(BuildContext context) {
    final inside = svc.insideProject;
    final zone = svc.zone;
    final text = zone.isNotEmpty
        ? zone
        : (inside == true ? 'Inside project area' : 'Location recorded');
    final c = inside == false ? AppTheme.amber : AppTheme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(inside == false ? Icons.location_off_rounded : Icons.location_on_rounded,
            color: c, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            inside == false ? 'Outside project boundary · $text' : text,
            style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElev,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppTheme.numStyle(size: 24, letterSpacing: -0.8)),
          ),
        ]),
      );
}
