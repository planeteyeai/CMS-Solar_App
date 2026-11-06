import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/attendance.dart';
import '../../services/auth_service.dart';
import '../../services/checkin_service.dart';
import '../../services/task_service.dart';
import '../../services/weather_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/attendance_card.dart';
import '../../widgets/profile_photo.dart';
import '../../widgets/task_widgets.dart';
import '../../widgets/ui_kit.dart';
import 'task_detail_screen.dart';

class SeHomeTab extends StatefulWidget {
  final VoidCallback onLogout;
  const SeHomeTab({super.key, required this.onLogout});

  @override
  State<SeHomeTab> createState() => _SeHomeTabState();
}

class _SeHomeTabState extends State<SeHomeTab> with WidgetsBindingObserver {
  Timer? _clock;
  Timer? _sync;
  DateTime _now = DateTime.now();
  WeatherInfo? _weather;
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _sync = Timer.periodic(const Duration(seconds: 45), (_) => _refresh(silent: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _sync?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    await Future.wait([
      context.read<CheckInService>().refresh(auth, silent: silent),
      context.read<TaskStore>().load(auth, silent: silent),
      WeatherService.current().then((w) {
        if (mounted && w != null) setState(() => _weather = w);
      }),
    ]);
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _checkIn() async {
    final err = await context.read<CheckInService>().checkIn(context.read<AuthService>());
    if (!mounted) return;
    _toast(err ?? 'Checked in. Your attendance is now visible to your team lead.');
  }

  Future<void> _checkOut() async {
    final svc = context.read<CheckInService>();
    final auth = context.read<AuthService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Check out from site?'),
        content: Text('You have been on site for ${fmtDuration(svc.timeOnSite)}. '
            'Your final location will be recorded.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CHECK OUT'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final msg = await svc.checkOut(auth);
    if (mounted) _toast(msg ?? 'Checked out. Have a good rest of the day.');
  }

  String _place(String? project) {
    final m = RegExp(r'\(([^)]+)\)').firstMatch(project ?? '');
    return m?.group(1) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final svc = context.watch<CheckInService>();
    final store = context.watch<TaskStore>();
    final profile = auth.profile!;
    final hour = _now.hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final projectName =
        store.projectName.isNotEmpty ? store.projectName : (profile.primaryProjectName ?? '');

    final tasks = store.tasks.where((t) {
      switch (_filter) {
        case 'DONE':
          return t.isDone;
        case 'PROGRESS':
          return t.isInProgress;
        case 'PENDING':
          return t.isPending;
        default:
          return true;
      }
    }).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${greeting.toUpperCase()},',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 2),
                  Text(profile.fullName,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6)),
                ]),
              ),
              ProfileMenu(
                userId: profile.id,
                initials: profile.initials,
                name: profile.fullName,
                role: profile.primaryRole,
                onLogout: widget.onLogout,
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              Pill('SITE ENGINEER', color: AppTheme.accent, icon: Icons.engineering_rounded),
              if (projectName.isNotEmpty)
                Pill(projectName, color: AppTheme.aiColor, icon: Icons.solar_power_rounded),
            ]),
            const SizedBox(height: 16),

            PhotoPrompt(userId: profile.id, name: profile.fullName),

            // Time + weather (dark hero card in every theme)
            AppCard(
              radius: 18,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              gradient: AppTheme.heroGradient,
              borderColor: Colors.white.withOpacity(0.08),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(DateFormat('HH:mm:ss').format(_now),
                          style: AppTheme.numStyle(
                              size: 42, color: AppTheme.heroText, letterSpacing: -1.5)),
                    ),
                    const SizedBox(height: 4),
                    Text(DateFormat('EEEE, d MMMM y').format(_now),
                        style: TextStyle(
                            color: AppTheme.heroMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
                if (_weather != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.3)),
                      ),
                      child: Icon(_weather!.icon, color: const Color(0xFFFCD34D), size: 28),
                    ),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${_weather!.tempC.round()}°C',
                          style: AppTheme.numStyle(
                              size: 24, color: AppTheme.heroText, letterSpacing: -0.5)),
                      Text(_place(projectName).isEmpty ? _weather!.label : _place(projectName),
                          style: TextStyle(color: AppTheme.heroMuted, fontSize: 11.5)),
                    ]),
                  ]),
              ]),
            ),
            const SizedBox(height: 12),

            AttendanceCard(svc: svc, onCheckIn: _checkIn, onCheckOut: _checkOut),
            const SizedBox(height: 12),

            // Progress
            if (store.loading && !store.loaded)
              const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()))
            else if (store.error != null && !store.loaded)
              AppCard(
                child: Column(children: [
                  Text(store.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textPrimary)),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _refresh, child: const Text('RETRY')),
                ]),
              )
            else ...[
              if (store.isLocal) ...[
                AppCard(
                  borderColor: AppTheme.amber.withOpacity(0.6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.phone_android_rounded, color: AppTheme.amber, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        store.pendingSync > 0
                            ? 'Working on this phone. ${store.pendingSync} update${store.pendingSync == 1 ? '' : 's'} waiting to upload; they will send automatically when the server is ready.'
                            : 'Working on this phone. Progress you save is stored here and uploads automatically when the server is ready.',
                        style: TextStyle(color: AppTheme.textPrimary, height: 1.4, fontSize: 13),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
              ] else if (store.pendingSync > 0) ...[
                AppCard(
                  borderColor: AppTheme.amber.withOpacity(0.6),
                  child: Text('${store.pendingSync} update(s) saved on this phone are waiting to upload.',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                ),
                const SizedBox(height: 12),
              ],
              ProgressSummaryCard(summary: store.summary),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: Text('Site Tasks (${store.tasks.length})',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filter,
                      dropdownColor: AppTheme.surfaceCard,
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('All Tasks')),
                        DropdownMenuItem(value: 'DONE', child: Text('Done')),
                        DropdownMenuItem(value: 'PROGRESS', child: Text('In Progress')),
                        DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                      ],
                      onChanged: (v) => setState(() => _filter = v ?? 'ALL'),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No tasks in this filter.',
                          style: TextStyle(color: AppTheme.textSecondary))),
                )
              else
                for (final t in tasks)
                  TaskRow(
                    task: t,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id)),
                      );
                      if (mounted) _refresh(silent: true);
                    },
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
