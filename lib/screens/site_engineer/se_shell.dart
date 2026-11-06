import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/checkin_service.dart';
import '../../services/task_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import '../theme_screen.dart';
import 'se_tasks.dart';
import 'se_history.dart';
import 'se_home.dart';

/// Site Engineer experience: Home (time, attendance, progress) · Tasks · History · Theme.
class SiteEngineerShell extends StatefulWidget {
  const SiteEngineerShell({super.key});

  @override
  State<SiteEngineerShell> createState() => _SiteEngineerShellState();
}

class _SiteEngineerShellState extends State<SiteEngineerShell> {
  int _tab = 0;
  final _historyKey = GlobalKey<SeHistoryTabState>();

  Future<void> _logout() async {
    context.read<CheckInService>().reset();
    context.read<TaskStore>().reset();
    await context.read<AuthService>().logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: IndexedStack(index: _tab, children: [
        SeHomeTab(onLogout: _logout),
        const SeTasksTab(),
        SeHistoryTab(key: _historyKey),
        const SafeArea(child: ThemeTab(showHeader: true)),
      ]),
      bottomNavigationBar: AppBottomNav(
        index: _tab,
        onTap: (i) {
          setState(() => _tab = i);
          if (i == 2) _historyKey.currentState?.reload();
        },
        items: const [
          AppNavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
          AppNavItem(Icons.checklist_rtl_rounded, Icons.fact_check_rounded, 'Tasks'),
          AppNavItem(Icons.history_outlined, Icons.history_rounded, 'History'),
          AppNavItem(Icons.palette_outlined, Icons.palette_rounded, 'Theme'),
        ],
      ),
    );
  }
}
