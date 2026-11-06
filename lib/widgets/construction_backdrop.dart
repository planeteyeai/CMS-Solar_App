import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Full-screen construction-site picture behind the login and loading screens.
///
/// Light theme: a sunrise scene. Regular and Dark themes: the same site at dusk.
/// A fade of the page colour keeps text readable: strongest at the top (logo and title),
/// lighter at the bottom where the picture shows best.
/// To use your own photo, replace the two files in assets/images (same names, portrait, about 1080 x 2400).
class ConstructionBackdrop extends StatelessWidget {
  final Widget child;
  const ConstructionBackdrop({super.key, required this.child});

  static const String _day = 'assets/images/construction_day.jpg';
  static const String _dusk = 'assets/images/construction_dusk.jpg';

  @override
  Widget build(BuildContext context) {
    final surface = AppTheme.surface;
    return Stack(fit: StackFit.expand, children: [
      Positioned.fill(
        child: Image.asset(
          AppTheme.isLight ? _day : _dusk,
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
          excludeFromSemantics: true,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          frameBuilder: (context, image, frame, wasSynchronouslyLoaded) => AnimatedOpacity(
            opacity: (wasSynchronouslyLoaded || frame != null) ? 1 : 0,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            child: image,
          ),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                surface.withOpacity(0.92),
                surface.withOpacity(0.82),
                surface.withOpacity(0.50),
                surface.withOpacity(0.18),
              ],
              stops: const [0.0, 0.38, 0.6, 1.0],
            ),
          ),
        ),
      ),
      child,
    ]);
  }
}
