import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../theme/app_theme.dart';

/// Round profile picture (loaded from the database) with an initials fallback.
class UserAvatar extends StatelessWidget {
  final int userId;
  final String name;
  final double size;
  final Color? ringColor;

  /// Rounded square (profile header) instead of a circle (lists, map pins).
  final bool square;

  const UserAvatar({
    super.key,
    required this.userId,
    required this.name,
    this.size = 44,
    this.ringColor,
    this.square = false,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return ValueListenableBuilder<int>(
      valueListenable: AvatarService.revision,
      builder: (_, __, ___) => FutureBuilder<Uint8List?>(
        future: AvatarService.load(auth, userId),
        initialData: AvatarService.cached(userId),
        builder: (_, snap) {
          final bytes = snap.data;
          final inner = bytes != null
              ? Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true)
              : Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryLight, AppTheme.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Text(_initials,
                      style: TextStyle(
                          color: AppTheme.onPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: size * 0.36)),
                );
          if (square) {
            // Profile header: rounded square with a soft ring (clean design).
            final r = size * 0.3;
            return Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(r + 2.5),
                color: ringColor ?? AppTheme.primary.withOpacity(0.18),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(r), child: inner),
            );
          }
          final circle = ClipOval(child: inner);
          if (ringColor == null) return circle;
          return Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(shape: BoxShape.circle, color: ringColor),
            child: circle,
          );
        },
      ),
    );
  }
}
