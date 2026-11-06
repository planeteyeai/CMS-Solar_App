import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/ui_kit.dart';

/// Theme tab: choose Dark, Regular (the original look) or Light (clean white).
/// The choice is applied at once and remembered on the phone.
class ThemeTab extends StatelessWidget {
  /// Show the big page title (when used as a bottom tab).
  final bool showHeader;
  const ThemeTab({super.key, this.showHeader = false});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    const order = [AppThemeMode.light, AppThemeMode.regular, AppThemeMode.dark];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (showHeader) ...[
          const SizedBox(height: 4),
          Text('Theme',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text('Choose how the app looks on this phone.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13.5)),
          const SizedBox(height: 18),
        ] else ...[
          Text('Choose how the app looks on this phone.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13.5)),
          const SizedBox(height: 14),
        ],
        for (final m in order) ...[
          _ThemeOption(
            palette: AppPalette.of(m),
            selected: controller.mode == m,
            onTap: () => controller.setMode(m),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        Text(
          'Your choice is saved. Light is best in bright sunlight, Dark is easier on the eyes at night, '
          'and Regular keeps the original navy and orange look.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.45),
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOption({required this.palette, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      borderColor: selected ? AppTheme.accent : null,
      child: Row(children: [
        _Preview(palette: palette),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(palette.label,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(palette.blurb,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.35)),
          ]),
        ),
        const SizedBox(width: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? AppTheme.primary : Colors.transparent,
            border: Border.all(color: selected ? AppTheme.primary : AppTheme.border, width: 2),
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 18, color: AppTheme.onPrimary)
              : null,
        ),
      ]),
    );
  }
}

/// Small drawing of a screen in the colours of [palette].
class _Preview extends StatelessWidget {
  final AppPalette palette;
  const _Preview({required this.palette});

  @override
  Widget build(BuildContext context) {
    Color c(int slot) => palette.color(slot);
    return Container(
      width: 72,
      height: 92,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: c(Slot.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c(Slot.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 30, height: 5, decoration: _bar(c(Slot.textPrimary))),
        const SizedBox(height: 4),
        Container(
          height: 22,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c(Slot.heroA), c(Slot.heroB)]),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 28,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c(Slot.surfaceCard),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c(Slot.border)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 34, height: 4, decoration: _bar(c(Slot.textSecondary))),
            const Spacer(),
            Row(children: [
              Container(width: 14, height: 7, decoration: _bar(c(Slot.accentGreen))),
              const SizedBox(width: 3),
              Container(width: 14, height: 7, decoration: _bar(c(Slot.primary))),
            ]),
          ]),
        ),
      ]),
    );
  }

  BoxDecoration _bar(Color color) =>
      BoxDecoration(color: color, borderRadius: BorderRadius.circular(3));
}
