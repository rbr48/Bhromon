import 'dart:math';
import 'package:flutter/material.dart';

/// Renders a casino-grade 3D clay poker chip with edge spots, concentric rings,
/// and metallic foil denomination badge.
class PokerChipView extends StatelessWidget {
  final int value;
  final double size;
  final Color? baseColor;

  const PokerChipView({
    super.key,
    required this.value,
    this.size = 36.0,
    this.baseColor,
  });

  Color _chipColor(int val) {
    if (baseColor != null) return baseColor!;
    if (val >= 500) return const Color(0xFF6A1B9A); // Royal Purple
    if (val >= 100) return const Color(0xFF212121); // Onyx Black
    if (val >= 50) return const Color(0xFF00695C);  // Emerald Teal
    if (val >= 20) return const Color(0xFF1565C0);  // Cobalt Blue
    return const Color(0xFFC62828);                 // Ruby Red
  }

  @override
  Widget build(BuildContext context) {
    final color = _chipColor(value);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: size * 0.15,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: _PokerChipPainter(
          value: value,
          baseColor: color,
        ),
      ),
    );
  }
}

class _PokerChipPainter extends CustomPainter {
  final int value;
  final Color baseColor;

  const _PokerChipPainter({
    required this.value,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    // 1. Base Clay Body with subtle radial gradient
    final basePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 0.85,
        colors: [
          Color.lerp(baseColor, Colors.white, 0.25)!,
          baseColor,
          Color.lerp(baseColor, Colors.black, 0.35)!,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, r, basePaint);

    // 2. Outer Edge Spots (6 white stripes)
    final stripePaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3;
      final startAngle = angle - 0.14;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        startAngle,
        0.28,
        true,
        stripePaint,
      );
    }

    // 3. Inner Rim separating the edge stripes
    canvas.drawCircle(
      center,
      r * 0.78,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          radius: 0.85,
          colors: [
            Color.lerp(baseColor, Colors.white, 0.18)!,
            baseColor,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r * 0.78)),
    );

    // 4. Textured Dashed Stitch Ring
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, r * 0.04);
    for (int i = 0; i < 18; i++) {
      final a = i * 2 * pi / 18;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * 0.68),
        a,
        0.16,
        false,
        dashPaint,
      );
    }

    // 5. Inset Center Foil Insert
    final innerR = r * 0.55;
    final inlayPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFFFF9E6),
          Color(0xFFE6C875),
          Color(0xFFB8860B),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: innerR));
    canvas.drawCircle(center, innerR, inlayPaint);

    // Gold Foil Ring
    canvas.drawCircle(
      center,
      innerR,
      Paint()
        ..color = const Color(0xFF7A5700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, r * 0.035),
    );

    // 6. Value Label / Emblem
    final text = value > 0 ? '$value' : '★';
    final fontSize = (innerR * 0.9).clamp(7.0, 18.0);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF2C1E00),
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    // 7. Top-left Specular Glass Glare
    final glarePath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: r * 0.92),
        -pi * 0.85,
        pi * 0.7,
      );
    canvas.drawPath(
      glarePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.08)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PokerChipPainter old) =>
      old.value != value || old.baseColor != baseColor;
}

/// Renders a 3D visual stack of casino chips for displaying pots and bets.
class PokerChipStackView extends StatelessWidget {
  final int totalAmount;
  final double chipSize;

  const PokerChipStackView({
    super.key,
    required this.totalAmount,
    this.chipSize = 28.0,
  });

  @override
  Widget build(BuildContext context) {
    if (totalAmount <= 0) return const SizedBox.shrink();

    // Determine representative chip values in the stack
    final chips = <int>[];
    int rem = totalAmount;
    if (rem >= 100) {
      chips.add(100);
      rem -= 100;
    }
    if (rem >= 50) {
      chips.add(50);
      rem -= 50;
    }
    if (rem >= 20) {
      chips.add(20);
      rem -= 20;
    }
    if (chips.isEmpty || rem > 0) {
      chips.add(rem > 0 ? rem : 10);
    }

    final displayChips = chips.take(4).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: chipSize + (displayChips.length - 1) * 6.0,
          height: chipSize + (displayChips.length - 1) * 2.0,
          child: Stack(
            children: [
              for (int i = 0; i < displayChips.length; i++)
                Positioned(
                  left: i * 6.0,
                  bottom: i * 2.0,
                  child: PokerChipView(
                    value: displayChips[i],
                    size: chipSize,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '৳$totalAmount',
          style: const TextStyle(
            color: Colors.amberAccent,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
