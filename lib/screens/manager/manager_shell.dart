import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/checkin_service.dart';
import '../../services/task_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'progress_tab.dart';
import 'attendance_tab.dart';
import 'explorer_tab.dart';
import 'overview_tab.dart';
import 'projects_tab.dart';
import 'tracking_tab.dart';

/// One console for Team Lead, Project Manager and Superadmin. The tabs differ by role:
///   Team Lead        → Overview · Attendance · Analyses
///   Project Manager  → Overview · Attendance · Analyses · Projects
///   Superadmin       → Overview · Attendance · Analyses · Data (everything in the DB)
class ManagerShell extends StatefulWidget {
  const ManagerShell({super.key});

  @override
  State<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends State<ManagerShell> {
  int _tab = 0;

  /// '' means "all projects".
  final ValueNotifier<String> _project = ValueNotifier<String>('');

  @override
  void dispose() {
    _project.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final profile = auth.profile!;
    final role = profile.appRole;

    final tabs = <_TabDef>[
      _TabDef('Overview', Icons.dashboard_outlined, Icons.dashboard_rounded,
          OverviewTab(project: _project)),
      _TabDef('Attendance', Icons.how_to_reg_outlined, Icons.how_to_reg_rounded,
          AttendanceTab(project: _project)),
      if (role == AppRole.superAdmin)
        _TabDef('Map', Icons.map_outlined, Icons.map_rounded, TrackingTab(project: _project)),
      _TabDef('Progress', Icons.trending_up_rounded, Icons.trending_up_rounded,
          ProgressTab(project: _project)),
      if (role == AppRole.projectManager)
        _TabDef('Projects', Icons.apartment_outlined, Icons.apartment_rounded,
            ProjectsTab(
              project: _project,
              onOpenProject: (name) {
                _project.value = name;
                setState(() => _tab = 0);
              },
            )),
      if (role == AppRole.superAdmin)
        _TabDef('Data', Icons.storage_outlined, Icons.storage_rounded,
            const ExplorerTab()),
    ];
    if (_tab >= tabs.length) _tab = 0;

    final title = switch (role) {
      AppRole.superAdmin => 'SUPERADMIN',
      AppRole.projectManager => 'PROJECT MANAGER',
      AppRole.teamLead => 'TEAM LEAD',
      _ => 'CMS',
    };

    final names = <String>{
      for (final p in profile.assignedProjects)
        if (p.projectName.isNotEmpty) p.projectName,
    }.toList()
      ..sort();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        titleSpacing: 20,
        toolbarHeight: 68,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4)),
          const SizedBox(height: 1),
          Text(profile.fullName,
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
        ]),
        actions: [
          ProfileMenu(
            userId: profile.id,
            initials: profile.initials,
            name: profile.fullName,
            role: profile.primaryRole,
            onLogout: () {
              context.read<CheckInService>().reset();
              context.read<TaskStore>().reset();
              context.read<AuthService>().logout();
            },
          ),
        ],
      ),
      body: Column(children: [
        // Project filter (hidden on the Data tab)
        if (tabs[_tab].label != 'Data' && tabs[_tab].label != 'Projects')
          _ProjectBar(project: _project, names: names),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [for (final t in tabs) t.page],
          ),
        ),
      ]),
      bottomNavigationBar: AppBottomNav(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: [
          for (final t in tabs) AppNavItem(t.icon, t.selectedIcon, t.label),
        ],
      ),
    );
  }
}

class _TabDef {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
  _TabDef(this.label, this.icon, this.selectedIcon, this.page);
}

class _ProjectBar extends StatelessWidget {
  final ValueNotifier<String> project;
  final List<String> names;
  const _ProjectBar({required this.project, required this.names});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: project,
      builder: (_, value, __) {
        final items = <String>['', ...names];
        if (value.isNotEmpty && !items.contains(value)) items.add(value);
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.cardShadow,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceCard,
              icon: Icon(Icons.expand_more_rounded, color: AppTheme.textSecondary),
              items: [
                for (final n in items)
                  DropdownMenuItem(
                    value: n,
                    child: Row(children: [
                      Icon(n.isEmpty ? Icons.public_rounded : Icons.solar_power_rounded,
                          size: 18, color: AppTheme.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(n.isEmpty ? 'All projects' : n,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
              ],
              onChanged: (v) => project.value = v ?? '',
            ),
          ),
        );
      },
    );
  }
}
