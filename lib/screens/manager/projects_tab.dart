import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';

/// Project Manager: the projects they own, one tap to monitor a project.
class ProjectsTab extends StatelessWidget {
  final ValueNotifier<String> project;
  final void Function(String name) onOpenProject;
  const ProjectsTab({super.key, required this.project, required this.onOpenProject});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthService>().profile!;
    final list = [...profile.assignedProjects]
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.projectName.compareTo(b.projectName);
      });

    if (list.isEmpty) {
      return const EmptyState(
          icon: Icons.apartment_outlined,
          title: 'No projects assigned',
          message: 'Ask a superadmin to assign you to a project.');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('${list.where((p) => p.isActive).length} active of ${list.length} projects',
            style: TextStyle(color: AppTheme.textSecondary)),
        const SizedBox(height: 12),
        for (final p in list)
          AppCard(
            margin: const EdgeInsets.only(bottom: 10),
            onTap: () => onOpenProject(p.projectName),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (p.isActive ? AppTheme.accentGreen : AppTheme.textMuted)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.solar_power_rounded,
                    color: p.isActive ? AppTheme.accentGreen : AppTheme.textMuted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.projectName,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  const SizedBox(height: 6),
                  Pill((p.status.isEmpty ? (p.isActive ? 'active' : 'inactive') : p.status).toUpperCase(),
                      color: p.isActive ? AppTheme.accentGreen : AppTheme.textMuted),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ]),
          ),
        const SizedBox(height: 6),
        Text('Tap a project to see its attendance and AI analyses.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ],
    );
  }
}
