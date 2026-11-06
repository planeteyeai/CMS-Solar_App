import 'package:cms_site_manager/theme/app_palette.dart';
import 'package:cms_site_manager/theme/app_theme.dart';
import 'package:cms_site_manager/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Run with:  flutter test test/theme_test.dart

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AppPalette.current = AppPalette.light);

  test('every palette defines every colour slot', () {
    for (final m in AppThemeMode.values) {
      expect(AppPalette.of(m).colors.length, Slot.count, reason: m.name);
    }
  });

  test('AppTheme colours follow the active palette', () {
    AppPalette.current = AppPalette.light;
    // ignore: deprecated_member_use
    expect(AppTheme.surfaceCard.value, 0xFFFFFFFF);
    AppPalette.current = AppPalette.regular;
    // ignore: deprecated_member_use
    expect(AppTheme.surfaceCard.value, 0xFF131A2E);
    AppPalette.current = AppPalette.dark;
    // ignore: deprecated_member_use
    expect(AppTheme.surface.value, 0xFF0B0F14);
  });

  test('derived colours (withOpacity, lerp) use the active palette', () {
    AppPalette.current = AppPalette.light;
    final light = AppTheme.accent.withOpacity(0.5);
    AppPalette.current = AppPalette.dark;
    final dark = AppTheme.accent.withOpacity(0.5);
    expect(light == dark, isFalse);
    expect(AppTheme.onTint(AppTheme.accentGreen) == AppTheme.accentGreen, isTrue); // dark theme: unchanged
  });

  test('text and buttons are readable in every theme', () {
    for (final m in AppThemeMode.values) {
      final p = AppPalette.of(m);
      Color c(int s) => p.color(s);
      expect(contrast(c(Slot.textPrimary), c(Slot.surface)), greaterThan(7), reason: '${m.name} text');
      expect(contrast(c(Slot.textSecondary), c(Slot.surfaceCard)), greaterThan(4.5), reason: '${m.name} secondary');
      expect(contrast(c(Slot.textMuted), c(Slot.surfaceCard)), greaterThan(4.5), reason: '${m.name} muted');
      expect(contrast(c(Slot.onPrimary), c(Slot.primary)), greaterThan(4.5), reason: '${m.name} primary button');
      expect(contrast(c(Slot.onGreen), c(Slot.accentGreen)), greaterThan(4.5), reason: '${m.name} check-in button');
      expect(contrast(c(Slot.heroText), c(Slot.heroA)), greaterThan(7), reason: '${m.name} clock card');
      final onRed = p.isLight ? Colors.white : c(Slot.onPrimary);
      expect(contrast(onRed, c(Slot.accentRed)), greaterThan(4.5), reason: '${m.name} check-out button');
    }
  });

  test('each mode builds its own Material theme', () {
    expect(AppTheme.themeFor(AppThemeMode.light).brightness, Brightness.light);
    expect(AppTheme.themeFor(AppThemeMode.regular).brightness, Brightness.dark);
    expect(AppTheme.themeFor(AppThemeMode.dark).brightness, Brightness.dark);
    expect(AppTheme.themeFor(AppThemeMode.light).scaffoldBackgroundColor,
        isNot(AppTheme.themeFor(AppThemeMode.dark).scaffoldBackgroundColor));
  });

  test('theme choice is remembered; default is Light', () async {
    SharedPreferences.setMockInitialValues({});
    final fresh = await ThemeController.load();
    expect(fresh.mode, AppThemeMode.light);

    await fresh.setMode(AppThemeMode.dark);
    expect(AppPalette.current.mode, AppThemeMode.dark);

    final again = await ThemeController.load(); // reads what setMode saved
    expect(again.mode, AppThemeMode.dark);
    expect(AppPalette.current.mode, AppThemeMode.dark);
  });
}
