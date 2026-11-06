import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Shown when the logged-in user is NOT a Site Engineer.
/// All other roles (PMC Head, Team Leader, Coordinator, etc.) see this screen
/// with a prompt to use the web platform.
class RoleDashboard extends StatelessWidget {
  const RoleDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle,
      child: Consumer<AuthService>(
        builder: (ctx, auth, _) {
          final profile = auth.profile;
          final role    = profile?.primaryRole ?? 'User';

          return Scaffold(
            backgroundColor: AppTheme.surface,
            appBar: AppBar(
              title: Row(children: [
                Icon(Icons.construction_rounded,
                    color: AppTheme.accent, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('CMS SITE MANAGER AI',
                        style: TextStyle(letterSpacing: 1.5))),
              ]),
              actions: [
                IconButton(
                  icon: Icon(Icons.logout_rounded,
                      color: AppTheme.accentRed),
                  tooltip: 'Log out',
                  onPressed: () => _logout(ctx, auth),
                ),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.4),
                          blurRadius: 20, spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        profile?.initials ?? '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28, fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Name
                  Text(
                    profile?.fullName ?? 'Welcome',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 24, fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),

                  // Role badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppTheme.accent.withOpacity(0.4)),
                    ),
                    child: Text(
                      role.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 12, fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Info card
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(children: [
                      Icon(Icons.smartphone_rounded,
                          color: AppTheme.textMuted, size: 36),
                      const SizedBox(height: 16),
                      Text(
                        'Mobile App — Site Engineers Only',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16, fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'This mobile interface is designed for Site Engineers '
                        'to manage GPS check-ins, asset scans, and AI-powered '
                        'inspections on-site.\n\n'
                        'Your role ($role) has a full dashboard available '
                        'on the web platform.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14, height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 36),

                  // Logout
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => _logout(ctx, auth),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accentRed,
                        side: BorderSide(color: AppTheme.accentRed),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('SIGN OUT',
                          style: TextStyle(
                            fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _logout(BuildContext ctx, AuthService auth) async {
    await auth.logout();
    // _Root observes AuthService and returns to LoginScreen automatically.
  }
}
