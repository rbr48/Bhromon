import 'dart:math';
import 'package:flutter/material.dart';

/// Renders a casino-grade playing card with vector-painted court card emblems,
/// linen-textured edges, corner rank indices, and ornate patterned card backs.
class PlayingCardView extends StatelessWidget {
  final String rank;
  final String suitSymbol;
  final bool isRed;
  final bool isFaceUp;
  final double width;
  final double height;
  final bool highlighted;
  final bool dimmed;
  final bool isPlayable;
  final Color backColor;

  const PlayingCardView({
    super.key,
    required this.rank,
    required this.suitSymbol,
    required this.isRed,
    this.isFaceUp = true,
    required this.width,
    required this.height,
    this.highlighted = false,
    this.dimmed = false,
    this.isPlayable = false,
    this.backColor = const Color(0xFF1E3A8A),
  });

  @override
  Widget build(BuildContext context) {
    final activeHighlight = highlighted || isPlayable;
    final borderRadius = BorderRadius.circular(max(4.0, width * 0.1));

    return Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            if (activeHighlight)
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.65),
                blurRadius: 7,
                spreadRadius: 1.5,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: CustomPaint(
            size: Size(width, height),
            painter: _PlayingCardPainter(
              rank: rank,
              suitSymbol: suitSymbol,
              isRed: isRed,
              isFaceUp: isFaceUp,
              highlighted: activeHighlight,
              backColor: backColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayingCardPainter extends CustomPainter {
  final String rank;
  final String suitSymbol;
  final bool isRed;
  final bool isFaceUp;
  final bool highlighted;
  final Color backColor;

  const _PlayingCardPainter({
    required this.rank,
    required this.suitSymbol,
    required this.isRed,
    required this.isFaceUp,
    required this.highlighted,
    required this.backColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    if (!isFaceUp) {
      _paintCardBack(canvas, size);
      return;
    }

    _paintCardFace(canvas, size, w, h);
  }

  void _paintCardBack(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Card stock background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFDFBF7),
    );

    // Outer white margin
    final margin = max(2.0, w * 0.05);
    final innerRect = Rect.fromLTWH(
      margin,
      margin,
      w - margin * 2,
      h - margin * 2,
    );

    // Deep colored pattern panel
    final patternPaint = Paint()..color = backColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, Radius.circular(max(2.0, w * 0.06))),
      patternPaint,
    );

    // Thin inner gold/white border
    final innerBorder = innerRect.deflate(max(1.5, w * 0.04));
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, w * 0.02);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerBorder, Radius.circular(max(1.5, w * 0.04))),
      borderPaint,
    );

    // Ornate diamond lattice pattern
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final step = max(6.0, w * 0.18);
    for (double x = innerBorder.left - h; x < innerBorder.right + h; x += step) {
      canvas.drawLine(
        Offset(x, innerBorder.top),
        Offset(x + innerBorder.height, innerBorder.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(x, innerBorder.bottom),
        Offset(x + innerBorder.height, innerBorder.top),
        gridPaint,
      );
    }

    // Center decorative medallion
    final center = Offset(w / 2, h / 2);
    final medRadius = min(w, h) * 0.22;
    canvas.drawCircle(
      center,
      medRadius,
      Paint()..color = const Color(0xFFFDFBF7),
    );
    canvas.drawCircle(
      center,
      medRadius * 0.85,
      Paint()..color = backColor,
    );
    canvas.drawCircle(
      center,
      medRadius * 0.72,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Center rosette
    final starPaint = Paint()..color = Colors.amber.shade300;
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      final p1 = center + Offset(cos(angle) * medRadius * 0.55, sin(angle) * medRadius * 0.55);
      canvas.drawCircle(p1, medRadius * 0.12, starPaint);
    }
  }

  void _paintCardFace(Canvas canvas, Size size, double w, double h) {
    // Premium ivory card stock with slight radial glow
    final faceRect = Offset.zero & size;
    final cardPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.85,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFFAF7F2),
          Color(0xFFF3EEE6),
        ],
      ).createShader(faceRect);
    canvas.drawRect(faceRect, cardPaint);

    // Card border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = highlighted ? max(2.0, w * 0.045) : max(0.8, w * 0.02)
      ..color = highlighted ? Colors.amber.shade600 : const Color(0x33000000);
    canvas.drawRect(faceRect, borderPaint);

    // Inner embossed border line for authentic card feel
    final innerMargin = max(2.5, w * 0.055);
    final innerLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0x18000000);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(innerMargin, innerMargin, w - innerMargin * 2, h - innerMargin * 2),
        Radius.circular(max(2.0, w * 0.04)),
      ),
      innerLinePaint,
    );

    final suitColor = isRed ? const Color(0xFFC62828) : const Color(0xFF1E242B);
    final cornerFontSize = (w * 0.26).clamp(8.0, 15.0);

    // Top-left rank & suit index
    _paintIndex(
      canvas,
      x: innerMargin + 1,
      y: innerMargin + 1,
      fontSize: cornerFontSize,
      color: suitColor,
    );

    // Bottom-right rotated rank & suit index (for cards with enough room)
    if (w >= 38) {
      canvas.save();
      canvas.translate(w - innerMargin - 1, h - innerMargin - 1);
      canvas.rotate(pi);
      _paintIndex(
        canvas,
        x: 0,
        y: 0,
        fontSize: cornerFontSize * 0.9,
        color: suitColor,
      );
      canvas.restore();
    }

    // Center artwork or pips
    _paintCenterArtwork(canvas, w, h, suitColor);
  }

  void _paintIndex(
    Canvas canvas, {
    required double x,
    required double y,
    required double fontSize,
    required Color color,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$rank\n',
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 0.92,
              fontFamily: 'Roboto',
            ),
          ),
          TextSpan(
            text: suitSymbol,
            style: TextStyle(
              color: color,
              fontSize: fontSize * 0.9,
              height: 0.92,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    textPainter.paint(canvas, Offset(x, y));
  }

  void _paintCenterArtwork(Canvas canvas, double w, double h, Color suitColor) {
    final center = Offset(w / 2, h / 2);
    final isCourt = rank == 'J' || rank == 'Q' || rank == 'K';

    if (isCourt && w >= 36) {
      _paintCourtCard(canvas, w, h, center, suitColor);
    } else if (rank == 'A' && w >= 34) {
      _paintAceArtwork(canvas, center, w, suitColor);
    } else {
      // Standard number card center pips
      final centerFontSize = (w * 0.38).clamp(12.0, 24.0);
      final centerPainter = TextPainter(
        text: TextSpan(
          text: suitSymbol,
          style: TextStyle(
            color: suitColor,
            fontSize: centerFontSize,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      centerPainter.paint(
        canvas,
        center - Offset(centerPainter.width / 2, centerPainter.height / 2),
      );
    }
  }

  void _paintAceArtwork(Canvas canvas, Offset center, double w, Color suitColor) {
    final aceSize = (w * 0.52).clamp(16.0, 32.0);
    final painter = TextPainter(
      text: TextSpan(
        text: suitSymbol,
        style: TextStyle(
          color: suitColor,
          fontSize: aceSize,
          shadows: [
            Shadow(
              color: suitColor.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  void _paintCourtCard(Canvas canvas, double w, double h, Offset center, Color suitColor) {
    final courtBoxSize = min(w * 0.62, h * 0.52);
    final rect = Rect.fromCenter(center: center, width: courtBoxSize, height: courtBoxSize);

    // Ornate gold-tinted court frame
    final framePaint = Paint()
      ..color = const Color(0xFFF3E5AB)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), framePaint);

    final frameBorder = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), frameBorder);

    // Court emblem: King with Crown, Queen with Tiara, Jack with Crest
    final iconData = rank == 'K'
        ? Icons.workspace_premium
        : (rank == 'Q' ? Icons.military_tech : Icons.shield);

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: courtBoxSize * 0.6,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: suitColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _PlayingCardPainter old) =>
      old.rank != rank ||
      old.suitSymbol != suitSymbol ||
      old.isRed != isRed ||
      old.isFaceUp != isFaceUp ||
      old.highlighted != highlighted ||
      old.backColor != backColor;
}
