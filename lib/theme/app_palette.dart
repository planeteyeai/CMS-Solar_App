import 'package:flutter/material.dart';

/// The three looks of the app. Chosen on the Theme tab and remembered on the phone.
///
///  * [light]   – "Clean White": daylight-friendly white canvas, slate text, amber / emerald accents.
///  * [regular] – the app's original look (deep navy with a sunrise-orange accent).
///  * [dark]    – a neutral charcoal dark version of the clean design.
enum AppThemeMode { dark, regular, light }

/// Positions of the colours inside a palette (AppTheme reads colours by these numbers).
class Slot {
  Slot._();
  static const primary = 0;
  static const primaryLight = 1;
  static const accent = 2;
  static const onPrimary = 3;
  static const accentGreen = 4;
  static const onGreen = 5;
  static const accentRed = 6;
  static const amber = 7;
  static const aiColor = 8;
  static const surface = 9;
  static const surfaceCard = 10;
  static const surfaceElev = 11;
  static const border = 12;
  static const textPrimary = 13;
  static const textSecondary = 14;
  static const textMuted = 15;
  static const heroA = 16;
  static const heroB = 17;
  static const heroText = 18;
  static const heroMuted = 19;
  static const count = 20;
}

/// Every colour of one theme.
class AppPalette {
  final AppThemeMode mode;
  final String label;
  final String blurb;
  final Brightness brightness;
  final List<int> colors;

  AppPalette({
    required this.mode,
    required this.label,
    required this.blurb,
    required this.brightness,
    required int primary,
    required int primaryLight,
    required int accent,
    required int onPrimary,
    required int accentGreen,
    required int onGreen,
    required int accentRed,
    required int amber,
    required int aiColor,
    required int surface,
    required int surfaceCard,
    required int surfaceElev,
    required int border,
    required int textPrimary,
    required int textSecondary,
    required int textMuted,
    required int heroA,
    required int heroB,
    required int heroText,
    required int heroMuted,
  }) : colors = List<int>.unmodifiable([
          primary,
          primaryLight,
          accent,
          onPrimary,
          accentGreen,
          onGreen,
          accentRed,
          amber,
          aiColor,
          surface,
          surfaceCard,
          surfaceElev,
          border,
          textPrimary,
          textSecondary,
          textMuted,
          heroA,
          heroB,
          heroText,
          heroMuted,
        ]);

  bool get isLight => brightness == Brightness.light;

  Color color(int slot) => Color(colors[slot]);

  // ── Light: "Clean White" (from the reference design) ─────────────────────
  static final AppPalette light = AppPalette(
    mode: AppThemeMode.light,
    label: 'Light',
    blurb: 'Clean white. Best in bright daylight.',
    brightness: Brightness.light,
    primary: 0xFFD1450B, // burnt solar orange: buttons and active states (4.6:1 with white text)
    primaryLight: 0xFFF59E0B,
    accent: 0xFFD97706, // amber 600: icons, rings, links
    onPrimary: 0xFFFFFFFF,
    accentGreen: 0xFF047857, // emerald 700 (5.5:1 with white text)
    onGreen: 0xFFFFFFFF,
    accentRed: 0xFFE11D48, // rose 600
    amber: 0xFFD97706,
    aiColor: 0xFF0284C7, // sky 600: the assistant
    surface: 0xFFF8FAFC, // slate 50: page background
    surfaceCard: 0xFFFFFFFF,
    surfaceElev: 0xFFF1F5F9, // slate 100: inputs, segmented controls
    border: 0xFFE2E8F0, // slate 200: hairlines
    textPrimary: 0xFF0F172A, // slate 900
    textSecondary: 0xFF475569, // slate 600
    textMuted: 0xFF64748B, // slate 500
    heroA: 0xFF1E293B, // dark clock card
    heroB: 0xFF020617,
    heroText: 0xFFFFFFFF,
    heroMuted: 0xFFCBD5E1,
  );

  // ── Regular: the original look ───────────────────────────────────────────
  static final AppPalette regular = AppPalette(
    mode: AppThemeMode.regular,
    label: 'Regular',
    blurb: 'The original look: deep navy with an orange accent.',
    brightness: Brightness.dark,
    primary: 0xFFFF7A1A,
    primaryLight: 0xFFFFB347,
    accent: 0xFFFFA43B,
    onPrimary: 0xFF1F1203,
    accentGreen: 0xFF2BD97C,
    onGreen: 0xFF1F1203,
    accentRed: 0xFFFF5470,
    amber: 0xFFFFD23F,
    aiColor: 0xFF4CC9F0,
    surface: 0xFF090D1A,
    surfaceCard: 0xFF131A2E,
    surfaceElev: 0xFF1C2542,
    border: 0xFF263056,
    textPrimary: 0xFFF7F8FF,
    textSecondary: 0xFFBCC5E3,
    textMuted: 0xFF8590B5,
    heroA: 0xFF2B3566,
    heroB: 0xFF131A38,
    heroText: 0xFFFFFFFF,
    heroMuted: 0xFFCBD5E1,
  );

  // ── Dark: neutral charcoal ───────────────────────────────────────────────
  static final AppPalette dark = AppPalette(
    mode: AppThemeMode.dark,
    label: 'Dark',
    blurb: 'Neutral charcoal. Easy on the eyes at night.',
    brightness: Brightness.dark,
    primary: 0xFFF59E0B,
    primaryLight: 0xFFFBBF24,
    accent: 0xFFFBBF24,
    onPrimary: 0xFF1A1203,
    accentGreen: 0xFF34D399,
    onGreen: 0xFF052E1B,
    accentRed: 0xFFFB7185,
    amber: 0xFFFBBF24,
    aiColor: 0xFF38BDF8,
    surface: 0xFF0B0F14,
    surfaceCard: 0xFF151A21,
    surfaceElev: 0xFF1E242D,
    border: 0xFF2A313B,
    textPrimary: 0xFFF1F5F9,
    textSecondary: 0xFFB4BFCD,
    textMuted: 0xFF8693A3,
    heroA: 0xFF1F2937,
    heroB: 0xFF0B1220,
    heroText: 0xFFFFFFFF,
    heroMuted: 0xFFCBD5E1,
  );

  static AppPalette of(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.dark:
        return dark;
      case AppThemeMode.regular:
        return regular;
      case AppThemeMode.light:
        return light;
    }
  }

  /// The palette in use right now. Changed only by ThemeController. `AppTheme.xxx` colours
  /// read from it every time they are used, so widgets pick up a new theme when rebuilt.
  static AppPalette current = light;
}
