import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/site_task.dart';
import '../../services/auth_service.dart';
import '../../services/task_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_widgets.dart';
import '../../widgets/ui_kit.dart';

/// Task progress and the full update history written by site engineers.
class ProgressTab extends StatefulWidget {
  final ValueNotifier<String> project;
  const ProgressTab({super.key, required this.project});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  int _segment = 0; // 0 tasks, 1 updates

  // Tasks
  bool _loadingTasks = false;
  String? _errorTasks;
  TaskListResult? _tasks;

  // Updates
  bool _loadingUpdates = true;
  String? _errorUpdates;
  List<TaskUpdate> _updates = [];
  String _filter = 'ALL';
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_onProject);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUpdates();
      _loadTasks();
    });
  }

  @override
  void dispose() {
    widget.project.removeListener(_onProject);
    super.dispose();
  }

  void _onProject() {
    _loadTasks();
    setState(() {}); // re-filter updates
  }

  int? _projectId() {
    final name = widget.project.value;
    if (name.isEmpty) return null;
    final list = context.read<AuthService>().profile!.assignedProjects;
    for (final p in list) {
      if (p.projectName == name) return p.id;
    }
    return null;
  }

  Future<void> _loadTasks() async {
    final id = _projectId();
    if (id == null) {
      setState(() {
        _tasks = null;
        _errorTasks = null;
        _loadingTasks = false;
      });
      return;
    }
    setState(() {
      _loadingTasks = true;
      _errorTasks = null;
    });
    try {
      final r = await TaskApi.fetchTasks(context.read<AuthService>(), projectId: id);
      if (!mounted) return;
      setState(() {
        _tasks = r;
        _loadingTasks = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorTasks = e.toString().replaceFirst('TaskException: ', '');
        _loadingTasks = false;
      });
    }
  }

  Future<void> _loadUpdates() async {
    setState(() {
      _loadingUpdates = true;
      _errorUpdates = null;
    });
    try {
      final u = await TaskApi.fetchFeed(context.read<AuthService>(), limit: 300);
      if (!mounted) return;
      setState(() {
        _updates = u;
        _loadingUpdates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorUpdates = e.toString().replaceFirst('TaskException: ', '');
        _loadingUpdates = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SegmentBar(
          items: const [('0', 'Tasks'), ('1', 'Updates')],
          value: '$_segment',
          onChanged: (v) => setState(() => _segment = int.parse(v)),
        ),
      ),
      Expanded(child: _segment == 0 ? _tasksView() : _updatesView()),
    ]);
  }

  // ── Tasks ────────────────────────────────────────────────────────────────

  Widget _tasksView() {
    final profile = context.read<AuthService>().profile!;
    if (widget.project.value.isEmpty || _projectId() == null) {
      final names = profile.assignedProjects.map((p) => p.projectName).toSet().toList()..sort();
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const EmptyState(
              icon: Icons.apartment_rounded,
              title: 'Choose a project',
              message: 'Pick a project to see the progress of each task.'),
          for (final n in names)
            AppCard(
              margin: const EdgeInsets.only(bottom: 8),
              onTap: () => widget.project.value = n,
              child: Row(children: [
                Icon(Icons.solar_power_rounded, color: AppTheme.accent),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(n,
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontWeight: FontWeight.w700))),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              ]),
            ),
        ],
      );
    }
    if (_loadingTasks) return const Center(child: CircularProgressIndicator());
    if (_errorTasks != null) return ErrorState(message: _errorTasks!, onRetry: _loadTasks);
    final r = _tasks;
    if (r == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          ProgressSummaryCard(summary: r.summary, title: 'Overall progress'),
          const SectionTitle('Tasks'),
          for (final t in r.tasks)
            TaskRow(
              task: t,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TaskHistoryScreen(task: t)),
              ),
            ),
        ],
      ),
    );
  }

  // ── Updates ──────────────────────────────────────────────────────────────

  bool _match(TaskUpdate u) {
    final p = widget.project.value;
    if (p.isNotEmpty && u.projectName != p) return false;
    switch (_filter) {
      case 'EDITED':
        if (!u.edited) return false;
      case 'RISK':
        if (u.riskLevel == 'LOW') return false;
    }
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return u.taskName.toLowerCase().contains(q) ||
        u.userName.toLowerCase().contains(q) ||
        u.summary.toLowerCase().contains(q);
  }

  Widget _updatesView() {
    if (_loadingUpdates) return const Center(child: CircularProgressIndicator());
    if (_errorUpdates != null) return ErrorState(message: _errorUpdates!, onRetry: _loadUpdates);

    final inProject = _updates.where((u) {
      final p = widget.project.value;
      return p.isEmpty || u.projectName == p;
    }).toList();
    final shown = _updates.where(_match).toList();
    final filters = [
      ('ALL', 'All · ${inProject.length}'),
      ('EDITED', 'Edited by engineer · ${inProject.where((u) => u.edited).length}'),
      ('RISK', 'Medium/High risk · ${inProject.where((u) => u.riskLevel != 'LOW').length}'),
    ];

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: const InputDecoration(
              hintText: 'Search task, engineer or summary', prefixIcon: Icon(Icons.search_rounded)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: SegmentBar(
          scrollable: true,
          items: filters,
          value: _filter,
          onChanged: (v) => setState(() => _filter = v),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadUpdates,
          child: shown.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 60),
                  EmptyState(
                      icon: Icons.history_toggle_off_rounded,
                      title: 'No updates found',
                      message: 'Progress saved by site engineers appears here.'),
                ])
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => TaskUpdateTile(
                    update: shown[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TaskUpdateDetailScreen(update: shown[i])),
                    ),
                  ),
                ),
        ),
      ),
    ]);
  }
}
