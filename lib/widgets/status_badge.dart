import 'package:flutter/material.dart';

class StatusBadge extends StatefulWidget {
  final String label;
  final Color color;

  /// Animate the dot (use when ONLINE / CHECKED IN)
  final bool pulse;

  /// Compact variant for the app bar
  final bool compact;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.pulse   = false,
    this.compact = false,
  });

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StatusBadge old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotSize = widget.compact ? 5.0 : 7.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 8  : 12,
        vertical:   widget.compact ? 4  : 6,
      ),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.pulse
              ? AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => Container(
                    width:  dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color
                          .withOpacity(0.45 + _ctrl.value * 0.55),
                    ),
                  ),
                )
              : Container(
                  width:  dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                ),
          SizedBox(width: widget.compact ? 5 : 6),
          Text(
            widget.label,
            style: TextStyle(
              color:       widget.color,
              fontSize:    widget.compact ? 10 : 12,
              fontWeight:  FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
