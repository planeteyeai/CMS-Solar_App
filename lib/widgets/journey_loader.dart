import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The project timeline: the 12 milestones of a solar site (same stages as the website).
const List<String> kJourneyMilestones = [
  'Project Information',
  'Pre-Construction',
  'Site Mobilization',
  'Land Development',
  'Pile Work',
  'Inverter Work',
  'Electrical Foundations',
  'ICR Yard',
  'Road & Drain Work',
  'Module Cleaning / Plumbing',
  'Fencing & Gate Work',
  'MMS Erection',
];

/// Loading animation shown while signing in: a glowing line draws an "S" and passes through all
/// 12 milestones one by one. Each milestone pops when the line reaches it, the current stage name
/// is shown underneath, and the finished route pulses before the loop starts again.
/// Colours follow the active theme. With "reduce motion" on, a finished static route is shown.
class JourneyLoader extends StatefulWidget {
  final double height;
  final Duration cycle;
  const JourneyLoader({
    super.key,
    this.height = 300,
    this.cycle = const Duration(milliseconds: 5600),
  });

  @override
  State<JourneyLoader> createState() => _JourneyLoaderState();
}

class _JourneyLoaderState extends State<JourneyLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.cycle);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
      _c.value = 0.86; // finished route, no motion
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0..1: how much of the line is drawn (first 82% of the cycle).
  static double drawn(double v) => Curves.easeInOutCubic.transform((v / 0.82).clamp(0.0, 1.0).toDouble());

  /// 1 while visible, fades to 0 at the very end of the cycle.
  static double fade(double v) => v < 0.93 ? 1.0 : (1.0 - (v - 0.93) / 0.07).clamp(0.0, 1.0).toDouble();

  /// A pulse (0..1..0) once the route is complete.
  static double pulse(double v) =>
      (v > 0.82 && v < 0.93) ? math.sin((v - 0.82) / 0.11 * math.pi) : 0.0;

  @override
  Widget build(BuildContext context) {
    final lineA = AppTheme.primary;
    final lineB = AppTheme.primaryLight;
    return Semantics(
      label: 'Signing in. Loading your project timeline.',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _JourneyPainter(
                progress: drawn(_c.value),
                fade: fade(_c.value),
                pulse: pulse(_c.value),
                track: AppTheme.border,
                lineA: lineA,
                lineB: lineB,
                dotFill: AppTheme.surfaceCard,
                dotBorder: AppTheme.textMuted.withOpacity(0.55),
                numberMuted: AppTheme.textMuted,
                numberOn: AppTheme.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final line = (drawn(_c.value) * _lead).clamp(0.0, 1.0).toDouble();
            final idx = (line * 11 + 0.0001).floor().clamp(0, 11).toInt();
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: Row(
                key: ValueKey(idx),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text((idx + 1).toString().padLeft(2, '0'),
                      style: AppTheme.numStyle(size: 14, color: AppTheme.accent, letterSpacing: 0)),
                  const SizedBox(width: 8),
                  Text(kJourneyMilestones[idx],
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            );
          },
        ),
      ]),
    );
  }
}

const double _lead = 1.06;

class _JourneyPainter extends CustomPainter {
  final double progress;
  final double fade;
  final double pulse;
  final Color track;
  final Color lineA;
  final Color lineB;
  final Color dotFill;
  final Color dotBorder;
  final Color numberMuted;
  final Color numberOn;

  _JourneyPainter({
    required this.progress,
    required this.fade,
    required this.pulse,
    required this.track,
    required this.lineA,
    required this.lineB,
    required this.dotFill,
    required this.dotBorder,
    required this.numberMuted,
    required this.numberOn,
  });

  /// An "S": starts top-left, swings right, crosses the middle, swings left, ends bottom-right.
  Path _sPath(Size size) {
    const pad = 26.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    Offset p(double x, double y) => Offset(pad + x * w, pad + y * h);
    return Path()
      ..moveTo(p(0.06, 0.02).dx, p(0.06, 0.02).dy)
      ..cubicTo(p(1.02, -0.02).dx, p(1.02, -0.02).dy, p(1.02, 0.50).dx, p(1.02, 0.50).dy,
          p(0.50, 0.50).dx, p(0.50, 0.50).dy)
      ..cubicTo(p(-0.02, 0.50).dx, p(-0.02, 0.50).dy, p(-0.02, 1.02).dx, p(-0.02, 1.02).dy,
          p(0.94, 0.98).dx, p(0.94, 0.98).dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _sPath(size);
    final metric = path.computeMetrics().first;
    final len = metric.length;
    // The line reaches the end of the route a little before the draw phase ends, so the last
    // milestone has time to finish its pop (otherwise milestone 12 would never fill in).
    final line = (progress * _lead).clamp(0.0, 1.0).toDouble();

    // 1. The empty route
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    // 2. The glowing line that is drawn so far
    final drawnLen = len * line;
    if (drawnLen > 0.5) {
      final drawn = metric.extractPath(0, drawnLen);
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..color = lineA.withOpacity(0.22 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.5
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(size.width, size.height),
            [lineA.withOpacity(fade), lineB.withOpacity(fade)],
          ),
      );
    }

    // 3. The 12 milestones: they pop when the line reaches them
    for (var i = 0; i < 12; i++) {
      final t = i / 11;
      final pos = metric.getTangentForOffset(len * t)!.position;
      final reached = ((((progress * _lead) - t) / 0.055).clamp(0.0, 1.0) * fade).toDouble();
      final pop = Curves.easeOutBack.transform(reached.clamp(0.0, 1.0).toDouble());
      final r = ui.lerpDouble(9.0, 13.5, pop)!;

      if (reached > 0) {
        canvas.drawCircle(pos, r + 5, Paint()..color = lineA.withOpacity(0.16 * reached));
      }
      canvas.drawCircle(pos, r, Paint()..color = Color.lerp(dotFill, lineA, reached)!);
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = Color.lerp(dotBorder, dotFill, reached)!,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color.lerp(numberMuted, numberOn, reached),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    // 4. Celebration ring on the last milestone when the route is complete
    if (pulse > 0) {
      final end = metric.getTangentForOffset(len)!.position;
      canvas.drawCircle(
        end,
        14 + 16 * pulse,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = lineB.withOpacity((1 - pulse) * 0.55),
      );
    }

    // 5. The bright head of the line
    if (line > 0 && line < 1) {
      final head = metric.getTangentForOffset(drawnLen)!.position;
      canvas.drawCircle(
        head,
        13,
        Paint()
          ..color = lineB.withOpacity(0.38)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(head, 6.5, Paint()..color = lineA);
      canvas.drawCircle(head, 3.2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_JourneyPainter old) =>
      old.progress != progress ||
      old.fade != fade ||
      old.pulse != pulse ||
      old.lineA != lineA ||
      old.track != track ||
      old.dotFill != dotFill;
}
