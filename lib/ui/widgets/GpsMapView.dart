// GpsMapView.dart
//
// Custom-painted "offline canvas map": graticule, synthetic terrain, radar rings
// and a pulsing pin at the embedded coordinates. No tile server is contacted —
// the app has no INTERNET permission, so the map is drawn, not downloaded.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/JpegMeta.dart';
import '../../theme/CyberTheme.dart';
import 'CyberWidgets.dart';

class GpsMapView extends StatefulWidget {
  const GpsMapView({
    super.key,
    required this.gps,
    required this.destroyed,
    this.height = 200,
  });

  final GpsPoint? gps;

  /// True once the metadata has been stripped: the pin becomes a destroyed marker.
  final bool destroyed;
  final double height;

  @override
  State<GpsMapView> createState() => _GpsMapViewState();
}

class _GpsMapViewState extends State<GpsMapView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF05080B),
          border: Border.all(color: CyberColors.stroke),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _GpsMapPainter(
                    gps: widget.gps,
                    destroyed: widget.destroyed,
                    t: _pulse.value,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: CyberChip(
                'offline canvas map',
                color: CyberColors.tealBright.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GpsMapPainter extends CustomPainter {
  _GpsMapPainter({required this.gps, required this.destroyed, required this.t});

  final GpsPoint? gps;
  final bool destroyed;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // backdrop
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0xFF0A1519), Color(0xFF05080B)],
        ).createShader(rect),
    );

    // graticule
    final grid = Paint()
      ..color = CyberColors.tealBright.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // synthetic terrain (deterministic, seeded by the coordinates)
    final seed = gps == null
        ? 42
        : ((gps!.latitude * 1000).round().abs() + (gps!.longitude * 1000).round().abs()).abs();
    final rnd = math.Random(seed);
    for (var i = 0; i < 4; i++) {
      final cx = rnd.nextDouble() * size.width;
      final cy = rnd.nextDouble() * size.height;
      final path = Path()..moveTo(cx, cy);
      var px = cx;
      var py = cy;
      for (var s = 0; s < 5; s++) {
        final nx = cx + (rnd.nextDouble() - 0.5) * 260;
        final ny = cy + (rnd.nextDouble() - 0.5) * 190;
        path.quadraticBezierTo(
          px + (rnd.nextDouble() - 0.5) * 170,
          py + (rnd.nextDouble() - 0.5) * 130,
          nx,
          ny,
        );
        px = nx;
        py = ny;
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = (i.isEven ? CyberColors.teal : CyberColors.blue).withValues(alpha: 0.05),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = CyberColors.tealBright.withValues(alpha: 0.10),
      );
    }

    final center = Offset(size.width / 2, size.height * 0.52);
    final radius = math.min(size.width, size.height);

    // radar rings
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        center,
        radius * (0.16 + i * 0.12),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = CyberColors.tealBright.withValues(alpha: 0.14 - i * 0.035),
      );
    }

    // crosshair
    final cross = Paint()
      ..color = CyberColors.tealBright.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(center.translate(-14, 0), center.translate(14, 0), cross);
    canvas.drawLine(center.translate(0, -14), center.translate(0, 14), cross);

    if (gps == null) {
      _label(canvas, size, 'NO GPS METADATA', 'this image carries no location fix', center);
      return;
    }

    // sweeping wedge
    if (!destroyed) {
      final angle = t * math.pi * 2;
      final wedge = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: radius * 0.42), angle, 0.5, false)
        ..close();
      canvas.drawPath(
        wedge,
        Paint()
          ..shader = SweepGradient(
            startAngle: angle,
            endAngle: angle + 0.5,
            colors: <Color>[
              CyberColors.tealBright.withValues(alpha: 0.22),
              CyberColors.tealBright.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius * 0.42)),
      );
    }

    if (destroyed) {
      final dashed = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = CyberColors.tealBright.withValues(alpha: 0.75);
      const dashCount = 10;
      for (var i = 0; i < dashCount; i++) {
        final a0 = i * (math.pi * 2 / dashCount);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: 26),
          a0,
          0.36,
          false,
          dashed,
        );
      }
      final crossOut = Paint()
        ..color = CyberColors.tealBright.withValues(alpha: 0.92)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center.translate(-12, -12), center.translate(12, 12), crossOut);
      canvas.drawLine(center.translate(12, -12), center.translate(-12, 12), crossOut);
      _label(canvas, size, 'GPS TAGS DESTROYED', 'no coordinates remain in the file', center);
      return;
    }

    // pulsing pin
    final pulse = 1 + math.sin(t * math.pi * 2) * 0.18;
    canvas.drawCircle(
      center,
      44 * pulse,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            CyberColors.amber.withValues(alpha: 0.55),
            CyberColors.amber.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 44 * pulse)),
    );
    canvas.drawCircle(center, 9, Paint()..color = CyberColors.amber);
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = CyberColors.obsidian.withValues(alpha: 0.9),
    );
    canvas.drawCircle(center, 3.2, Paint()..color = CyberColors.obsidian);

    // coordinate label
    final label =
        '${gps!.latitude.toStringAsFixed(4)}°${gps!.latitude >= 0 ? 'N' : 'S'}   '
        '${gps!.longitude.abs().toStringAsFixed(4)}°${gps!.longitude >= 0 ? 'E' : 'W'}';
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: CyberTypography.mono,
          fontSize: 11,
          color: CyberColors.amberSoft,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final boxRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, -52),
        width: painter.width + 22,
        height: 26,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(boxRect, Paint()..color = const Color(0xD1060A0E));
    canvas.drawRRect(
      boxRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = CyberColors.amber.withValues(alpha: 0.5),
    );
    painter.paint(canvas, center.translate(-painter.width / 2, -52 - painter.height / 2));
  }

  void _label(Canvas canvas, Size size, String title, String subtitle, Offset center) {
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          fontFamily: CyberTypography.mono,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xBF8B98A7),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final subPainter = TextPainter(
      text: TextSpan(
        text: subtitle,
        style: const TextStyle(
          fontFamily: CyberTypography.mono,
          fontSize: 10.5,
          color: Color(0x995F6B79),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titlePainter.paint(canvas, center.translate(-titlePainter.width / 2, 46));
    subPainter.paint(canvas, center.translate(-subPainter.width / 2, 66));
  }

  @override
  bool shouldRepaint(covariant _GpsMapPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.gps != gps || oldDelegate.destroyed != destroyed;
}
