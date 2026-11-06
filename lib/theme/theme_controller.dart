import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_palette.dart';
import 'app_theme.dart';

/// Holds the chosen theme (Dark / Regular / Light) and remembers it on the phone.
class ThemeController extends ChangeNotifier {
  static const _key = 'app_theme_mode';

  /// The "Clean White" design is the default.
  static const AppThemeMode defaultMode = AppThemeMode.light;

  AppThemeMode _mode = defaultMode;
  AppThemeMode get mode => _mode;

  AppPalette get palette => AppPalette.of(_mode);

  /// Reads the saved choice. Call once before `runApp`.
  static Future<ThemeController> load() async {
    final c = ThemeController();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      for (final m in AppThemeMode.values) {
        if (m.name == saved) c._mode = m;
      }
    } catch (_) {/* keep the default */}
    AppPalette.current = AppPalette.of(c._mode);
    return c;
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    // 1. switch the colours every `AppTheme.xxx` resolves to ...
    AppPalette.current = AppPalette.of(mode);
    // 2. ... update the status / navigation bar icons ...
    SystemChrome.setSystemUIOverlayStyle(AppTheme.overlayStyle);
    // 3. ... then let the app rebuild.
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }
}

/// Rebuilds every widget below [context]. Widgets read `AppTheme` colours when they are
/// built, so after a theme change the whole tree is rebuilt once. Screens, tabs, scroll
/// positions and entered text are kept.
void rebuildAllChildren(BuildContext context) {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}
