import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';

/// Design tokens of the app.
///
/// Colours are read from the ACTIVE palette every time they are used (they are getters, not
/// constants), so choosing another theme on the Theme tab changes the whole app after one rebuild.
/// Light = "Clean White", Regular = the original navy/orange look, Dark = neutral charcoal.
class AppTheme {
  AppTheme._();

  static Color _c(int slot) => AppPalette.current.color(slot);

  // Brand
  static Color get primary => _c(Slot.primary); // buttons, selected states
  static Color get primaryLight => _c(Slot.primaryLight);
  static Color get accent => _c(Slot.accent); // icons, rings, links
  static Color get onPrimary => _c(Slot.onPrimary); // text on the brand colour

  // Status
  static Color get accentGreen => _c(Slot.accentGreen);
  static Color get onGreen => _c(Slot.onGreen); // text on solid green
  static Color get accentRed => _c(Slot.accentRed);
  static Color get amber => _c(Slot.amber);
  static Color get aiColor => _c(Slot.aiColor); // the assistant (robot)

  // Surfaces
  static Color get surface => _c(Slot.surface);
  static Color get surfaceCard => _c(Slot.surfaceCard);
  static Color get surfaceElev => _c(Slot.surfaceElev);
  static Color get border => _c(Slot.border);

  // Text
  static Color get textPrimary => _c(Slot.textPrimary);
  static Color get textSecondary => _c(Slot.textSecondary);
  static Color get textMuted => _c(Slot.textMuted);

  // Always-dark "hero" card (clock): text on it is always light.
  static Color get heroText => _c(Slot.heroText);
  static Color get heroMuted => _c(Slot.heroMuted);

  static LinearGradient get primaryGradient => LinearGradient(
        colors: [primary, primaryLight],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );

  /// Dark header card (clock). Dark in every theme.
  static LinearGradient get heroGradient => LinearGradient(
        colors: [_c(Slot.heroA), _c(Slot.heroB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // Fonts: text in Plus Jakarta Sans, numbers in JetBrains Mono.
  static const String fontText = 'PlusJakartaSans';
  static const String fontMono = 'JetBrainsMono';

  /// Number style: tabular, tight, easy to read at a glance.
  static TextStyle numStyle({
    double size = 16,
    FontWeight weight = FontWeight.w800,
    Color? color,
    double? height,
    double letterSpacing = -0.5,
  }) =>
      TextStyle(
        fontFamily: fontMono,
        fontSize: size,
        fontWeight: weight,
        color: color ?? textPrimary,
        height: height,
        letterSpacing: letterSpacing,
      );

  static bool get isLight => AppPalette.current.isLight;

  /// Text colour that stays readable on a tint of [c]: darker on white themes, as-is on dark ones.
  static Color onTint(Color c) =>
      isLight ? Color.lerp(c, const Color(0xFF0F172A), 0.5)! : c;

  /// Soft shadow of cards on the white theme (none on dark themes).
  static List<BoxShadow> get cardShadow => isLight
      ? const [
          BoxShadow(color: Color(0x0F0F172A), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0A0F172A), blurRadius: 14, offset: Offset(0, 5)),
        ]
      : const [];

  static SystemUiOverlayStyle get overlayStyle => overlayFor(AppPalette.current);

  static SystemUiOverlayStyle overlayFor(AppPalette p) {
    final light = p.isLight;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: p.color(Slot.surfaceCard),
      systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
      systemNavigationBarDividerColor: p.color(Slot.border),
    );
  }

  /// Backwards-compatible entry point (the active palette).
  static ThemeData get dark => themeFor(AppPalette.current.mode);

  /// Full Material theme for a mode. Built from real colours so Flutter sees a
  /// different theme when the mode changes.
  static ThemeData themeFor(AppThemeMode mode) {
    final p = AppPalette.of(mode);
    Color c(int slot) => p.color(slot);
    final light = p.isLight;

    final scheme = (light ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
      primary: c(Slot.primary),
      onPrimary: c(Slot.onPrimary),
      secondary: c(Slot.accent),
      onSecondary: c(Slot.onPrimary),
      tertiary: c(Slot.aiColor),
      error: c(Slot.accentRed),
      surface: c(Slot.surfaceCard),
      onSurface: c(Slot.textPrimary),
      onSurfaceVariant: c(Slot.textSecondary),
      secondaryContainer: c(Slot.primary).withOpacity(0.16),
      onSecondaryContainer: c(Slot.accent),
      outline: c(Slot.border),
      outlineVariant: c(Slot.border),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c(Slot.surface),
      fontFamily: fontText,
      splashFactory: InkRipple.splashFactory,
    );

    final border = c(Slot.border);
    final text = c(Slot.textPrimary);
    final muted = c(Slot.textMuted);
    final secondary = c(Slot.textSecondary);
    final card = c(Slot.surfaceCard);
    final elev = c(Slot.surfaceElev);
    final primary = c(Slot.primary);
    final accent = c(Slot.accent);

    OutlineInputBorder field(Color color, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: w),
        );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
        fontFamily: fontText,
      ),
      iconTheme: IconThemeData(color: secondary),
      appBarTheme: AppBarTheme(
        backgroundColor: c(Slot.surface),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontText,
          color: text,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: secondary),
        systemOverlayStyle: overlayFor(p),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        height: 70,
        indicatorColor: primary.withOpacity(0.14),
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 24,
              color: s.contains(WidgetState.selected) ? accent : muted,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontFamily: fontText,
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
              color: s.contains(WidgetState.selected) ? accent : muted,
            )),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: c(Slot.onPrimary),
          disabledBackgroundColor: elev,
          disabledForegroundColor: muted,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(
              fontFamily: fontText, fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: 0.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: c(Slot.onPrimary),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontFamily: fontText, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border, width: 1.2),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontFamily: fontText, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(
              fontFamily: fontText, fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: primary.withOpacity(0.14),
        disabledColor: card,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        checkmarkColor: accent,
        labelStyle: TextStyle(
            fontFamily: fontText, color: secondary, fontWeight: FontWeight.w700, fontSize: 13),
        secondaryLabelStyle: TextStyle(
            fontFamily: fontText, color: text, fontWeight: FontWeight.w800, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: light ? elev : card,
          foregroundColor: secondary,
          selectedBackgroundColor: light ? card : elev,
          selectedForegroundColor: text,
          side: BorderSide(color: light ? elev : border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: fontText, fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: accent,
        inactiveTrackColor: border,
        thumbColor: primary,
        overlayColor: primary.withOpacity(0.14),
        valueIndicatorColor: primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elev,
        border: field(border),
        enabledBorder: field(border),
        focusedBorder: field(accent, 2),
        errorBorder: field(c(Slot.accentRed)),
        focusedErrorBorder: field(c(Slot.accentRed), 2),
        labelStyle: TextStyle(color: muted, fontSize: 14),
        hintStyle: TextStyle(color: muted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 0),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: light ? 6 : 2,
        shadowColor: const Color(0x330F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
        textStyle: TextStyle(fontFamily: fontText, color: text, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: light ? const Color(0xFF0F172A) : elev,
        contentTextStyle: TextStyle(
            fontFamily: fontText,
            color: light ? Colors.white : text,
            fontSize: 14,
            fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: border,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: accent,
        textColor: text,
      ),
      dividerColor: border,
    );
  }
}
