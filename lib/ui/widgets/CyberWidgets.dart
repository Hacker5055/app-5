// CyberWidgets.dart — the visual vocabulary of the app: frosted glass cards,
// neon buttons, dashed drop zones, pills, capacity meters and the scan beam.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/CyberTheme.dart';

/// Frosted, blurred container used by every card.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(18),
    this.tint,
    this.strong = false,
    this.onTap,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;
  final Color? tint;
  final bool strong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(title!.toUpperCase(), style: CyberTypography.sectionLabel)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(CyberTheme.radius),
      child: BackdropFilter(
        filter: CyberTheme.blur,
        child: DecoratedBox(
          decoration: CyberTheme.glassDecoration(tint: tint, strong: strong),
          child: onTap == null
              ? content
              : Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onTap, child: content),
                ),
        ),
      ),
    );
  }
}

/// Small monospace pill used for statuses and counters.
class CyberChip extends StatelessWidget {
  const CyberChip(
    this.label, {
    super.key,
    this.color = CyberColors.textMuted,
    this.filled = false,
    this.icon,
  });

  final String label;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: filled ? 0.42 : 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: CyberTypography.mono,
              fontSize: 10,
              letterSpacing: 0.3,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient primary button with the neon glow from the design language.
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CyberTheme.radiusSmall),
          gradient: CyberTheme.tealGlow,
          boxShadow: enabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: CyberColors.teal.withValues(alpha: 0.42),
                    blurRadius: 26,
                    spreadRadius: -6,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(CyberTheme.radiusSmall),
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: dense ? 11 : 15),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 17, color: const Color(0xFF04211D)),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: const Color(0xFF04211D),
                        fontWeight: FontWeight.w700,
                        fontSize: dense ? 12.5 : 13.5,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: onPressed == null ? CyberColors.textDim : CyberColors.tealBright,
        side: BorderSide(
          color: onPressed == null ? CyberColors.stroke : CyberColors.teal.withValues(alpha: 0.36),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

/// Dashed-border drop area with the animated scan beam.
class DropZone extends StatelessWidget {
  const DropZone({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.actions = const <Widget>[],
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyberTheme.radius),
      child: BackdropFilter(
        filter: CyberTheme.blur,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: CustomPaint(
              painter: _DashedBorderPainter(),
              child: Container(
                padding: EdgeInsets.all(compact ? 14 : 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CyberTheme.radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      CyberColors.teal.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0.014),
                    ],
                  ),
                ),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: IgnorePointer(child: ScanBeam(height: compact ? 64 : 96))),
                    Row(
                      children: <Widget>[
                        Icon(icon, color: CyberColors.tealBright, size: compact ? 24 : 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                title,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: const TextStyle(fontSize: 11, color: CyberColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        if (actions.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 8),
                          Wrap(spacing: 8, children: actions),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = CyberColors.teal.withValues(alpha: 0.42);
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(CyberTheme.radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 7.0;
      const gap = 5.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Slow diagonal light sweep, the app's sign of "engine ready".
class ScanBeam extends StatefulWidget {
  const ScanBeam({super.key, required this.height});

  final double height;

  @override
  State<ScanBeam> createState() => _ScanBeamState();
}

class _ScanBeamState extends State<ScanBeam> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Stack(
              children: <Widget>[
                Positioned(
                  top: (constraints.maxHeight + widget.height) * t - widget.height,
                  left: 0,
                  right: 0,
                  height: widget.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.transparent,
                          CyberColors.tealBright.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Thin meter with teal→amber gradient used by the capacity calculator.
class CapacityMeter extends StatelessWidget {
  const CapacityMeter({super.key, required this.fraction, this.height = 8});

  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: CyberColors.stroke),
          borderRadius: BorderRadius.circular(99),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[CyberColors.teal, CyberColors.tealBright, CyberColors.amber],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(color: CyberColors.teal.withValues(alpha: 0.6), blurRadius: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// key: value row in monospace, used across all three screens.
class DataRow extends StatelessWidget {
  const DataRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 11.5, color: CyberColors.textMuted)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: CyberTypography.data.copyWith(color: valueColor ?? CyberColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header with an ambient teal underline.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: CyberTypography.title),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 3),
          Text(subtitle!, style: const TextStyle(fontSize: 11.5, color: CyberColors.textMuted)),
        ],
      ],
    );
  }
}

/// Ambient background: obsidian gradient + faint grid + two colour glows.
class CyberBackground extends StatelessWidget {
  const CyberBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.6, -1.0),
                radius: 1.3,
                colors: <Color>[Color(0xFF101A1E), CyberColors.obsidian, CyberColors.obsidianDeep],
                stops: <double>[0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(painter: _GridPainter()),
        ),
        Positioned(
          top: -180,
          left: -140,
          child: _Glow(color: CyberColors.teal.withValues(alpha: 0.34), size: 420),
        ),
        Positioned(
          bottom: -200,
          right: -140,
          child: _Glow(color: CyberColors.amber.withValues(alpha: 0.16), size: 380),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: <Color>[color, color.withValues(alpha: 0)]),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.022)
      ..strokeWidth = 1;
    const step = 46.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
