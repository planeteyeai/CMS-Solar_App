import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/site_task.dart';
import '../../services/auth_service.dart';
import '../../services/task_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_widgets.dart';
import '../../widgets/ui_kit.dart';
import 'task_detail_screen.dart';

/// All tasks with search and status filter.
class SeTasksTab extends StatefulWidget {
  const SeTasksTab({super.key});

  @override
  State<SeTasksTab> createState() => _SeTasksTabState();
}

class _SeTasksTabState extends State<SeTasksTab> {
  String _filter = 'ALL';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TaskStore>();
    final q = _query.toLowerCase();
    bool match(SiteTask t) {
      switch (_filter) {
        case 'DONE':
          if (!t.isDone) return false;
        case 'PROGRESS':
          if (!t.isInProgress) return false;
        case 'PENDING':
          if (!t.isPending) return false;
      }
      return q.isEmpty || t.name.toLowerCase().contains(q);
    }

    final shown = store.tasks.where(match).toList();
    final s = store.summary;
    final filters = [
      ('ALL', 'All · ${s.total}'),
      ('PROGRESS', 'In progress · ${s.inProgress}'),
      ('PENDING', 'Pending · ${s.pending}'),
      ('DONE', 'Done · ${s.done}'),
    ];

    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Site Tasks',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6)),
              if (store.projectName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Engineering execution schedule · ${store.projectName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(
                hintText: 'Search tasks', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: SegmentBar(
            scrollable: true,
            items: filters,
            value: _filter,
            colors: {'PROGRESS': AppTheme.amber, 'DONE': AppTheme.accentGreen},
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: store.loading && !store.loaded
              ? const Center(child: CircularProgressIndicator())
              : store.error != null && !store.loaded
                  ? ErrorState(
                      message: store.error!,
                      onRetry: () => store.load(context.read<AuthService>()))
                  : RefreshIndicator(
                      onRefresh: () => store.load(context.read<AuthService>(), silent: true),
                      child: shown.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 60),
                              EmptyState(icon: Icons.task_alt_rounded, title: 'No tasks match'),
                            ])
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                              itemCount: shown.length,
                              itemBuilder: (_, i) => TaskRow(
                                task: shown[i],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => TaskDetailScreen(taskId: shown[i].id)),
                                ),
                              ),
                            ),
                    ),
        ),
      ]),
    );
  }
}
