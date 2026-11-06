import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'services/checkin_service.dart';
import 'services/task_service.dart';
import 'screens/login_screen.dart';
import 'screens/site_engineer/se_shell.dart';
import 'screens/manager/manager_shell.dart';
import 'screens/role_dashboard.dart';
import 'models/user_profile.dart';
import 'theme/app_palette.dart';
import 'widgets/construction_backdrop.dart';
import 'widgets/journey_loader.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Saved theme (Dark / Regular / Light) must be known before the first frame.
  final themeController = await ThemeController.load();
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlayStyle);

  // Initialise auth (restores JWT + profile from SharedPreferences)
  final auth = AuthService();
  await auth.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => CheckInService()),
        ChangeNotifierProvider(create: (_) => TaskStore()),
      ],
      child: const CmsSiteManagerApp(),
    ),
  );
}

class CmsSiteManagerApp extends StatefulWidget {
  const CmsSiteManagerApp({super.key});

  @override
  State<CmsSiteManagerApp> createState() => _CmsSiteManagerAppState();
}

class _CmsSiteManagerAppState extends State<CmsSiteManagerApp> {
  late final ThemeController _theme = context.read<ThemeController>();
  late AppThemeMode _shown = _theme.mode;

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (_shown == _theme.mode) return;
    setState(() => _shown = _theme.mode);
    // Colours are read while widgets are built, so rebuild the whole app once
    // after the new palette is active (keeps the current screen and its state).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rebuildAllChildren(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CMS Site Manager AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(_shown),
      home: const _Root(),
    );
  }
}

/// ── Role-based routing ────────────────────────────────────────────────────
///
///  Not logged in      → LoginScreen
///  Site Engineer      → SiteEngineerShell (time, check-in, task progress with AI, history)
///  Team Lead          → ManagerShell (team attendance + analyses)
///  Project Manager    → ManagerShell (+ projects)
///  Superadmin         → ManagerShell (+ full database explorer)
///  Anything else      → RoleDashboard
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (_, auth, __) {
        if (auth.loading) return const _Splash();
        if (!auth.isLoggedIn) return const LoginScreen();

        switch (auth.profile!.appRole) {
          case AppRole.superAdmin:
          case AppRole.projectManager:
          case AppRole.teamLead:
            return const ManagerShell();
          case AppRole.siteEngineer:
            return const SiteEngineerShell();
          case AppRole.other:
            return const RoleDashboard();
        }
      },
    );
  }
}

// ── Splash ────────────────────────────────────────────────────────────────

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    // Shown while signing in and while the saved session is restored: the S-shaped
    // route draws itself through all milestones, so the waiting time looks purposeful.
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: ConstructionBackdrop(
        child: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final h = (c.maxHeight - 340).clamp(200.0, 320.0).toDouble();
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [AppTheme.primary, AppTheme.accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(AppTheme.isLight ? 0.2 : 0.45),
                          blurRadius: 20, spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.engineering_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 14),
                  Text('CMS Site Manager AI',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5,
                      )),
                  const SizedBox(height: 4),
                  Text('Solar Site Construction Management',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: JourneyLoader(height: h),
                  ),
                  const SizedBox(height: 16),
                  Text('Preparing your workspace…',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3)),
                ]),
              ),
            ),
          );
        }),
        ),
      ),
    );
  }
}
