// ComparisonSlider.dart
//
// Draggable cover / container comparison. Because a 1-bit LSB edit moves a
// channel by at most ±1/255, dragging this slider produces *no visible change* —
// which is exactly the point of the widget.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/CyberTheme.dart';
import 'CyberWidgets.dart';

class ComparisonSlider extends StatefulWidget {
  const ComparisonSlider({
    super.key,
    required this.coverBytes,
    required this.stegoBytes,
    this.aspectRatio = 4 / 3,
    this.leftLabel = 'cover',
    this.rightLabel = 'stego',
  });

  final Uint8List coverBytes;
  final Uint8List stegoBytes;
  final double aspectRatio;
  final String leftLabel;
  final String rightLabel;

  @override
  State<ComparisonSlider> createState() => _ComparisonSliderState();
}

class _ComparisonSliderState extends State<ComparisonSlider> {
  double _fraction = 0.5;

  void _update(Offset localPosition, double width) {
    setState(() => _fraction = (localPosition.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _update(details.localPosition, width),
          onHorizontalDragUpdate: (details) => _update(details.localPosition, width),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: Container(
                color: const Color(0xFF05070A),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.memory(
                      widget.coverBytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                    ClipRect(
                      clipper: _RevealClipper(_fraction),
                      child: Image.memory(
                        widget.stegoBytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: width * _fraction - 1,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.transparent,
                              CyberColors.tealBright.withValues(alpha: 0.95),
                              Colors.transparent,
                            ],
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: CyberColors.tealBright.withValues(alpha: 0.7),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: width * _fraction - 15,
                      child: Center(
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xE6060C0E),
                            border: Border.all(
                              color: CyberColors.tealBright.withValues(alpha: 0.8),
                            ),
                          ),
                          child: const Icon(
                            Icons.code,
                            size: 14,
                            color: CyberColors.tealBright,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: CyberChip(widget.leftLabel, color: CyberColors.textMuted),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: CyberChip(
                        widget.rightLabel,
                        color: CyberColors.tealBright,
                        filled: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(size.width * fraction, 0, size.width, size.height);

  @override
  bool shouldReclip(covariant _RevealClipper oldClipper) => oldClipper.fraction != fraction;
}
