import 'package:flutter/material.dart';

import '../screens/server_check_screen.dart';
import '../screens/theme_screen.dart';
import '../services/avatar_service.dart';
import '../services/site_status_service.dart';
import '../theme/app_theme.dart';
import 'profile_photo.dart';
import 'user_avatar.dart';

Color riskColor(String risk) {
  switch (risk.toUpperCase()) {
    case 'HIGH':
    case 'CRITICAL':
      return AppTheme.accentRed;
    case 'MEDIUM':
      return AppTheme.amber;
    case 'LOW':
    case 'NONE':
      return AppTheme.accentGreen;
    default:
      return AppTheme.textMuted;
  }
}

/// Calm colours for what the assistant finds in a scan: no red. Higher levels are a warmer
/// amber, lower levels are neutral, so notes read as advice and not as alarms.
Color softRiskColor(String level) {
  switch (level.toUpperCase()) {
    case 'CRITICAL':
    case 'HIGH':
      return AppTheme.primary; // warm orange
    case 'MEDIUM':
      return AppTheme.amber;
    case 'LOW':
    case 'NONE':
      return AppTheme.accentGreen;
    default:
      return AppTheme.textMuted;
  }
}

Color presenceColor(String status) {
  switch (status.toUpperCase()) {
    case 'PRESENT':
    case 'ACTIVE':
      return AppTheme.accentGreen;
    case 'CHECKED_OUT':
    case 'COMPLETED':
      return AppTheme.accent;
    case 'INCOMPLETE':
      return AppTheme.amber;
    default:
      return AppTheme.textMuted;
  }
}

/// Rounded card: hairline border and, on the white theme, a soft shadow.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;
  final EdgeInsetsGeometry margin;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.borderColor,
    this.margin = EdgeInsets.zero,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? AppTheme.surfaceCard : null,
        gradient: gradient,
        borderRadius: r,
        border: Border.all(color: borderColor ?? AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: r,
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
            ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  /// Fully rounded (status chips such as CHECKED IN); default is a small rounded tag.
  final bool round;
  const Pill(this.text,
      {super.key, required this.color, this.icon, this.filled = false, this.round = false});

  @override
  Widget build(BuildContext context) {
    final light = AppTheme.isLight;
    final fg = filled ? Colors.black : AppTheme.onTint(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: color.withOpacity(filled ? 0.9 : (light ? 0.10 : 0.16)),
        borderRadius: BorderRadius.circular(round ? 30 : 8),
        border: Border.all(color: color.withOpacity(light ? 0.35 : 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: filled ? Colors.black : color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(text,
              style: TextStyle(
                  color: fg, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
        ),
      ]),
    );
  }
}

/// Big-number tile. Numbers are intentionally large and high-contrast.
/// [compact] is for three tiles in one row; [height] keeps tiles in a row equally tall.
class KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool compact;
  final double? height;
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.compact = false,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final light = AppTheme.isLight;
    final box = compact ? 34.0 : 40.0;
    final fg = AppTheme.onTint(color);
    final tile = Container(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, compact ? 12 : 14, compact ? 10 : 14, compact ? 12 : 14),
      decoration: BoxDecoration(
        color: light ? color.withOpacity(0.08) : null,
        gradient: light
            ? null
            : LinearGradient(
                colors: [color.withOpacity(0.22), AppTheme.surfaceCard],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(light ? 0.30 : 0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: box,
            height: box,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(light ? 0.16 : 0.24),
              borderRadius: BorderRadius.circular(box * 0.3),
            ),
            child: Icon(icon, size: box * 0.55, color: color),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: AppTheme.numStyle(
                    size: compact ? 36 : 46, color: fg, height: 1.0, letterSpacing: -1.5)),
          ),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: light ? fg : AppTheme.textPrimary,
                  fontSize: compact ? 12.5 : 14,
                  height: 1.2,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return height == null ? tile : SizedBox(height: height, child: tile);
  }
}

/// Robot badge used wherever the assistant's analysis is shown.
const IconData kAiIcon = Icons.smart_toy_rounded;

class AiBadge extends StatelessWidget {
  final double size;
  const AiBadge({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.aiColor.withOpacity(AppTheme.isLight ? 0.10 : 0.18),
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: AppTheme.aiColor.withOpacity(AppTheme.isLight ? 0.35 : 0.55)),
        ),
        child: Icon(kAiIcon, color: AppTheme.aiColor, size: size * 0.6),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.surfaceElev,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.border),
              ),
              child: Icon(icon, size: 38, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13.5, height: 1.45)),
            ],
          ]),
        ),
      );
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.amber.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.cloud_off_rounded, size: 30, color: AppTheme.amber),
              ),
              const SizedBox(height: 14),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14.5, height: 1.45)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('TRY AGAIN'),
              ),
            ]),
          ),
        ),
      );
}

/// Avatar (profile picture) + account menu: change photo, connection check, log out.
class ProfileMenu extends StatelessWidget {
  final int userId;
  final String initials;
  final String name;
  final String role;
  final VoidCallback onLogout;
  const ProfileMenu({
    super.key,
    required this.userId,
    required this.initials,
    required this.name,
    required this.role,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Account',
        offset: const Offset(0, 46),
        onSelected: (v) {
          if (v == 'photo') changeProfilePhoto(context, userId, name);
          if (v == 'theme') {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Theme')),
                      body: const ThemeTab(),
                    )));
          }
          if (v == 'check') {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServerCheckScreen()));
          }
          if (v == 'logout') {
            AvatarService.clear();
            SiteStatusService.clearCache();
            onLogout();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            enabled: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
              Text(role, style: TextStyle(color: AppTheme.accent, fontSize: 12)),
            ]),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'photo',
            child: Row(children: [
              Icon(Icons.account_circle_rounded, color: AppTheme.accent, size: 18),
              SizedBox(width: 10),
              Text('Change profile photo'),
            ]),
          ),
          PopupMenuItem(
            value: 'theme',
            child: Row(children: [
              Icon(Icons.palette_rounded, color: AppTheme.accent, size: 18),
              SizedBox(width: 10),
              Text('Theme'),
            ]),
          ),
          PopupMenuItem(
            value: 'check',
            child: Row(children: [
              Icon(Icons.network_check_rounded, color: AppTheme.accent, size: 18),
              SizedBox(width: 10),
              Text('Connection check'),
            ]),
          ),
          PopupMenuItem(
            value: 'logout',
            child: Row(children: [
              Icon(Icons.logout_rounded, color: AppTheme.accentRed, size: 18),
              SizedBox(width: 10),
              Text('Log out'),
            ]),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: UserAvatar(userId: userId, name: name, size: 44, square: true),
        ),
      );
}

/// Circular percent ring.
class PercentRing extends StatelessWidget {
  final double percent; // 0-100
  final Color color;
  final double size;
  final String? label;
  const PercentRing({
    super.key,
    required this.percent,
    required this.color,
    this.size = 92,
    this.label,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0).toDouble(),
              strokeWidth: size * 0.1 < 7 ? 7 : size * 0.1,
              backgroundColor: AppTheme.border,
              color: color,
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${percent.round()}%',
                style: AppTheme.numStyle(size: size * 0.27, letterSpacing: -0.5)),
            if (label != null)
              Text(label!,
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 10.5, letterSpacing: 0.6)),
          ]),
        ]),
      );
}


/// One destination of [AppBottomNav].
class AppNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool dot;
  const AppNavItem(this.icon, this.selectedIcon, this.label, {this.dot = false});
}

/// Bottom bar from the clean design: hairline on top, a soft rounded highlight behind the
/// active icon, 11 pt labels, and tap targets of at least 56 px (glove friendly).
class AppBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<AppNavItem> items;
  const AppBottomNav({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        border: Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: AppTheme.isLight
            ? const [BoxShadow(color: Color(0x0D0F172A), blurRadius: 14, offset: Offset(0, -3))]
            : const [],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(child: _navButton(i)),
          ]),
        ),
      ),
    );
  }

  Widget _navButton(int i) {
    final item = items[i];
    final selected = i == index;
    final color = selected ? AppTheme.accent : AppTheme.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onTap(i),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 54,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              Icon(selected ? item.selectedIcon : item.icon, size: 23, color: color),
              if (item.dot)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.surfaceCard, width: 1.5),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 3),
          Text(item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: color)),
        ]),
      ),
    );
  }
}


/// Segmented control from the clean design: a soft grey track with a white "thumb" on the
/// active option. Items are (key, label); [colors] tints the active label per key.
class SegmentBar extends StatelessWidget {
  final List<(String, String)> items;
  final String value;
  final ValueChanged<String> onChanged;
  final bool scrollable;
  final Map<String, Color> colors;
  const SegmentBar({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.scrollable = false,
    this.colors = const {},
  });

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final it in items)
        scrollable ? _segment(it) : Expanded(child: _segment(it)),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElev,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: scrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: Row(children: children))
          : Row(children: children),
    );
  }

  Widget _segment((String, String) it) {
    final selected = it.$1 == value;
    final tint = colors[it.$1];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(it.$1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.surfaceCard : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: AppTheme.border) : null,
          boxShadow: selected ? AppTheme.cardShadow : null,
        ),
        child: Text(it.$2,
            maxLines: 1,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected
                    ? (tint == null ? AppTheme.textPrimary : AppTheme.onTint(tint))
                    : AppTheme.textSecondary)),
      ),
    );
  }
}
