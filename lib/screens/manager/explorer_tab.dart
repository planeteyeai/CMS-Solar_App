import 'package:flutter/material.dart';

import '../../services/admin_data_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import '../admin_data_screens.dart';

/// Superadmin: read everything stored in the database.
class ExplorerTab extends StatelessWidget {
  const ExplorerTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('Everything in the database',
            style: TextStyle(
                color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(
          'Browse every dataset. Tap a record to see all its fields.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        for (final ds in AdminDatasets.all)
          AppCard(
            margin: const EdgeInsets.only(bottom: 10),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AdminDataListScreen(dataset: ds)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(ds.icon, color: AppTheme.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ds.title,
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(ds.subtitle,
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ]),
          ),
        AppCard(
          onTap: () => showCustomEndpointDialog(context),
          child: Row(children: [
            Icon(Icons.code_rounded, color: AppTheme.textSecondary),
            SizedBox(width: 14),
            Expanded(
              child: Text('Open any other endpoint…',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ],
    );
  }
}
