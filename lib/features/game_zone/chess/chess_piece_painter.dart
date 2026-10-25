import 'dart:math';
import 'package:flutter/material.dart';
import 'chess_engine.dart';

/// Luxury tournament-grade vector Staunton chess piece painter.
/// Features authentic silhouettes, soft directional lighting, material depth,
/// and ground drop shadows for a tactile physical chess set feel.
class ChessPiecePainter extends CustomPainter {
  final PieceType type;
  final bool isWhite;
  final double size;

  const ChessPiecePainter({
    required this.type,
    required this.isWhite,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final s = canvasSize.width;
    final cx = s * 0.5;
    final strokeWidth = max(1.2, s * 0.045);

    // ── 1. Soft Ground Contact Shadow ───────────────────────────────────────
    final shadowPaint = Paint()
      ..color = const Color(0x3A000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.04);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, s * 0.86),
        width: s * 0.62,
        height: s * 0.12,
      ),
      shadowPaint,
    );

    // ── 2. Realistic Material Shaders ───────────────────────────────────────
    // White pieces: Warm ivory / polished porcelain with soft ambient sheen
    // Black pieces: Rich obsidian / tournament ebony with sleek slate edge
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isWhite
            ? const [
                Color(0xFFFFFFFF),
                Color(0xFFF9F8F5),
                Color(0xFFEBE6DC),
                Color(0xFFDED8CD),
              ]
            : const [
                Color(0xFF3E454E),
                Color(0xFF282D34),
                Color(0xFF1E2227),
                Color(0xFF14171A),
              ],
        stops: const [0.0, 0.35, 0.75, 1.0],
      ).createShader(Offset.zero & canvasSize);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = isWhite ? const Color(0xFF4A443A) : const Color(0xFF23282E);

    final highlightStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, strokeWidth * 0.6)
      ..strokeCap = StrokeCap.round
      ..color = isWhite
          ? Colors.white.withValues(alpha: 0.7)
          : Colors.white.withValues(alpha: 0.18);

    switch (type) {
      case PieceType.pawn:
        _paintPawn(canvas, s, cx, fillPaint, strokePaint, highlightStroke);
        break;
      case PieceType.knight:
        _paintKnight(canvas, s, cx, fillPaint, strokePaint, highlightStroke);
        break;
      case PieceType.bishop:
        _paintBishop(canvas, s, cx, fillPaint, strokePaint, highlightStroke);
        break;
      case PieceType.rook:
        _paintRook(canvas, s, cx, fillPaint, strokePaint, highlightStroke);
        break;
      case PieceType.queen:
        _paintQueen(canvas, s, cx, fillPaint, strokePaint, highlightStroke);
        break;
      case PieceType.king:
        _paintKing(canvas, s, cx, fillPaint, strokePaint, highlightStroke);
        break;
    }
  }

  // ── PAWN ──────────────────────────────────────────────────────────────────
  void _paintPawn(Canvas canvas, double s, double cx, Paint fill, Paint stroke,
      Paint highlight) {
    final body = Path();
    // Weighted pedestal base
    body.moveTo(cx - s * 0.23, s * 0.83);
    body.lineTo(cx + s * 0.23, s * 0.83);
    body.quadraticBezierTo(cx + s * 0.22, s * 0.77, cx + s * 0.17, s * 0.75);
    body.lineTo(cx + s * 0.15, s * 0.70);
    // Tapered neck
    body.quadraticBezierTo(cx + s * 0.08, s * 0.57, cx + s * 0.07, s * 0.49);
    // Collar flange
    body.lineTo(cx + s * 0.13, s * 0.47);
    body.quadraticBezierTo(cx + s * 0.13, s * 0.44, cx + s * 0.08, s * 0.44);
    body.lineTo(cx - s * 0.08, s * 0.44);
    body.quadraticBezierTo(cx - s * 0.13, s * 0.44, cx - s * 0.13, s * 0.47);
    body.lineTo(cx - s * 0.07, s * 0.49);
    body.quadraticBezierTo(cx - s * 0.08, s * 0.57, cx - s * 0.15, s * 0.70);
    body.lineTo(cx - s * 0.17, s * 0.75);
    body.quadraticBezierTo(cx - s * 0.22, s * 0.77, cx - s * 0.23, s * 0.83);
    body.close();

    final headCenter = Offset(cx, s * 0.33);
    final headRadius = s * 0.125;

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    canvas.drawCircle(headCenter, headRadius, fill);
    canvas.drawCircle(headCenter, headRadius, stroke);

    // Collar ring
    final collar = Path()
      ..moveTo(cx - s * 0.11, s * 0.46)
      ..lineTo(cx + s * 0.11, s * 0.46);
    canvas.drawPath(collar, stroke);

    // Head specular highlight
    canvas.drawArc(
      Rect.fromCircle(center: headCenter, radius: headRadius * 0.75),
      -pi * 0.85,
      pi * 0.45,
      false,
      highlight,
    );
  }

  // ── KNIGHT ────────────────────────────────────────────────────────────────
  void _paintKnight(Canvas canvas, double s, double cx, Paint fill,
      Paint stroke, Paint highlight) {
    final path = Path();
    // Base pedestal
    path.moveTo(cx - s * 0.25, s * 0.83);
    path.lineTo(cx + s * 0.25, s * 0.83);
    path.quadraticBezierTo(cx + s * 0.24, s * 0.77, cx + s * 0.18, s * 0.75);
    // Back of neck curving up with arched mane
    path.quadraticBezierTo(cx + s * 0.26, s * 0.50, cx + s * 0.12, s * 0.26);
    // Ear
    path.lineTo(cx + s * 0.07, s * 0.17);
    path.lineTo(cx + s * 0.01, s * 0.23);
    // Forehead and snout
    path.lineTo(cx - s * 0.14, s * 0.32);
    path.quadraticBezierTo(cx - s * 0.28, s * 0.41, cx - s * 0.25, s * 0.50);
    // Muzzle / mouth
    path.lineTo(cx - s * 0.15, s * 0.52);
    // Jaw / throat curve
    path.quadraticBezierTo(cx - s * 0.05, s * 0.56, cx - s * 0.10, s * 0.68);
    // Chest down to base
    path.lineTo(cx - s * 0.18, s * 0.75);
    path.quadraticBezierTo(cx - s * 0.25, s * 0.77, cx - s * 0.25, s * 0.83);
    path.close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // Eye dot
    final eye = Offset(cx - s * 0.06, s * 0.36);
    canvas.drawCircle(eye, s * 0.024, stroke);

    // Mane details (notched hair curves)
    final mane1 = Path()
      ..moveTo(cx + s * 0.08, s * 0.33)
      ..quadraticBezierTo(cx + s * 0.15, s * 0.44, cx + s * 0.12, s * 0.56);
    canvas.drawPath(mane1, stroke);

    final mane2 = Path()
      ..moveTo(cx + s * 0.13, s * 0.44)
      ..quadraticBezierTo(cx + s * 0.21, s * 0.56, cx + s * 0.15, s * 0.68);
    canvas.drawPath(mane2, stroke);

    // Jaw crease
    final jaw = Path()
      ..moveTo(cx - s * 0.18, s * 0.48)
      ..lineTo(cx - s * 0.09, s * 0.49);
    canvas.drawPath(jaw, stroke);

    // Nostril mark
    final nostril = Path()
      ..moveTo(cx - s * 0.21, s * 0.45)
      ..lineTo(cx - s * 0.18, s * 0.47);
    canvas.drawPath(nostril, stroke);
  }

  // ── BISHOP ────────────────────────────────────────────────────────────────
  void _paintBishop(Canvas canvas, double s, double cx, Paint fill,
      Paint stroke, Paint highlight) {
    // Pedestal and flared miter
    final body = Path();
    body.moveTo(cx - s * 0.24, s * 0.83);
    body.lineTo(cx + s * 0.24, s * 0.83);
    body.quadraticBezierTo(cx + s * 0.22, s * 0.77, cx + s * 0.16, s * 0.75);
    body.lineTo(cx + s * 0.13, s * 0.62);
    // Flared pointed miter body
    body.quadraticBezierTo(cx + s * 0.22, s * 0.42, cx, s * 0.24);
    body.quadraticBezierTo(cx - s * 0.22, s * 0.42, cx - s * 0.13, s * 0.62);
    body.lineTo(cx - s * 0.16, s * 0.75);
    body.quadraticBezierTo(cx - s * 0.22, s * 0.77, cx - s * 0.24, s * 0.83);
    body.close();

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    // Top sphere finial
    final finialCenter = Offset(cx, s * 0.20);
    canvas.drawCircle(finialCenter, s * 0.046, fill);
    canvas.drawCircle(finialCenter, s * 0.046, stroke);

    // Bishop's miter cut/cleft
    final cleft = Path()
      ..moveTo(cx - s * 0.01, s * 0.30)
      ..lineTo(cx + s * 0.10, s * 0.44);
    canvas.drawPath(cleft, stroke);

    // Collar ring
    final collar = Path()
      ..moveTo(cx - s * 0.13, s * 0.60)
      ..lineTo(cx + s * 0.13, s * 0.60);
    canvas.drawPath(collar, stroke);

    // Miter specular curve
    final spec = Path()
      ..moveTo(cx - s * 0.12, s * 0.48)
      ..quadraticBezierTo(cx - s * 0.14, s * 0.38, cx - s * 0.04, s * 0.29);
    canvas.drawPath(spec, highlight);
  }

  // ── ROOK ──────────────────────────────────────────────────────────────────
  void _paintRook(Canvas canvas, double s, double cx, Paint fill, Paint stroke,
      Paint highlight) {
    final body = Path();
    // Base
    body.moveTo(cx - s * 0.25, s * 0.83);
    body.lineTo(cx + s * 0.25, s * 0.83);
    body.quadraticBezierTo(cx + s * 0.23, s * 0.77, cx + s * 0.18, s * 0.75);
    // Tapered tower body
    body.lineTo(cx + s * 0.15, s * 0.44);
    // Turret flare
    body.lineTo(cx + s * 0.22, s * 0.42);
    // Battlements (right crenel)
    body.lineTo(cx + s * 0.22, s * 0.25);
    body.lineTo(cx + s * 0.12, s * 0.25);
    body.lineTo(cx + s * 0.12, s * 0.33);
    body.lineTo(cx + s * 0.05, s * 0.33);
    // Center crenel
    body.lineTo(cx + s * 0.05, s * 0.25);
    body.lineTo(cx - s * 0.05, s * 0.25);
    body.lineTo(cx - s * 0.05, s * 0.33);
    body.lineTo(cx - s * 0.12, s * 0.33);
    // Left crenel
    body.lineTo(cx - s * 0.12, s * 0.25);
    body.lineTo(cx - s * 0.22, s * 0.25);
    body.lineTo(cx - s * 0.22, s * 0.42);
    body.lineTo(cx - s * 0.15, s * 0.44);
    // Left tower wall down to base
    body.lineTo(cx - s * 0.18, s * 0.75);
    body.quadraticBezierTo(cx - s * 0.23, s * 0.77, cx - s * 0.25, s * 0.83);
    body.close();

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    // Parapet trim line
    final trim = Path()
      ..moveTo(cx - s * 0.20, s * 0.43)
      ..lineTo(cx + s * 0.20, s * 0.43);
    canvas.drawPath(trim, stroke);

    // Tower specular gleam
    final wallSpec = Path()
      ..moveTo(cx - s * 0.12, s * 0.70)
      ..lineTo(cx - s * 0.10, s * 0.46);
    canvas.drawPath(wallSpec, highlight);
  }

  // ── QUEEN ─────────────────────────────────────────────────────────────────
  void _paintQueen(Canvas canvas, double s, double cx, Paint fill, Paint stroke,
      Paint highlight) {
    // Base and royal gown
    final body = Path();
    body.moveTo(cx - s * 0.26, s * 0.83);
    body.lineTo(cx + s * 0.26, s * 0.83);
    body.quadraticBezierTo(cx + s * 0.24, s * 0.77, cx + s * 0.18, s * 0.75);
    body.lineTo(cx + s * 0.14, s * 0.58);
    body.quadraticBezierTo(cx + s * 0.10, s * 0.48, cx + s * 0.22, s * 0.32);
    // Coronet 5 peaks
    body.lineTo(cx + s * 0.13, s * 0.39);
    body.lineTo(cx + s * 0.08, s * 0.29);
    body.lineTo(cx, s * 0.38);
    body.lineTo(cx - s * 0.08, s * 0.29);
    body.lineTo(cx - s * 0.13, s * 0.39);
    body.lineTo(cx - s * 0.22, s * 0.32);
    // Left gown down to base
    body.quadraticBezierTo(cx - s * 0.10, s * 0.48, cx - s * 0.14, s * 0.58);
    body.lineTo(cx - s * 0.18, s * 0.75);
    body.quadraticBezierTo(cx - s * 0.24, s * 0.77, cx - s * 0.26, s * 0.83);
    body.close();

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    // 5 jewels / pearls on coronet peaks
    final pearlRadius = s * 0.026;
    final peaks = [
      Offset(cx - s * 0.22, s * 0.31),
      Offset(cx - s * 0.08, s * 0.28),
      Offset(cx, s * 0.23),
      Offset(cx + s * 0.08, s * 0.28),
      Offset(cx + s * 0.22, s * 0.31),
    ];
    for (final p in peaks) {
      canvas.drawCircle(p, pearlRadius, fill);
      canvas.drawCircle(p, pearlRadius, stroke);
    }

    // Waist belt
    final belt = Path()
      ..moveTo(cx - s * 0.13, s * 0.56)
      ..lineTo(cx + s * 0.13, s * 0.56);
    canvas.drawPath(belt, stroke);
  }

  // ── KING ──────────────────────────────────────────────────────────────────
  void _paintKing(Canvas canvas, double s, double cx, Paint fill, Paint stroke,
      Paint highlight) {
    // Base and royal robe
    final body = Path();
    body.moveTo(cx - s * 0.26, s * 0.83);
    body.lineTo(cx + s * 0.26, s * 0.83);
    body.quadraticBezierTo(cx + s * 0.24, s * 0.77, cx + s * 0.18, s * 0.75);
    body.lineTo(cx + s * 0.14, s * 0.54);
    // Arched domed crown
    body.quadraticBezierTo(cx + s * 0.20, s * 0.42, cx + s * 0.18, s * 0.33);
    body.quadraticBezierTo(cx + s * 0.08, s * 0.30, cx, s * 0.27);
    body.quadraticBezierTo(cx - s * 0.08, s * 0.30, cx - s * 0.18, s * 0.33);
    body.quadraticBezierTo(cx - s * 0.20, s * 0.42, cx - s * 0.14, s * 0.54);
    body.lineTo(cx - s * 0.18, s * 0.75);
    body.quadraticBezierTo(cx - s * 0.24, s * 0.77, cx - s * 0.26, s * 0.83);
    body.close();

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    // Cross Pattée on crown
    final cross = Path();
    final top = s * 0.13;
    final bot = s * 0.26;
    // Vertical stem
    cross.moveTo(cx - s * 0.03, bot);
    cross.lineTo(cx - s * 0.03, top);
    cross.lineTo(cx + s * 0.03, top);
    cross.lineTo(cx + s * 0.03, bot);
    cross.close();
    // Horizontal arms
    cross.moveTo(cx - s * 0.08, s * 0.18);
    cross.lineTo(cx + s * 0.08, s * 0.18);
    cross.lineTo(cx + s * 0.08, s * 0.22);
    cross.lineTo(cx - s * 0.08, s * 0.22);
    cross.close();

    canvas.drawPath(cross, fill);
    canvas.drawPath(cross, stroke);

    // Crown rim
    final rim = Path()
      ..moveTo(cx - s * 0.16, s * 0.44)
      ..lineTo(cx + s * 0.16, s * 0.44);
    canvas.drawPath(rim, stroke);
  }

  @override
  bool shouldRepaint(covariant ChessPiecePainter old) =>
      old.type != type || old.isWhite != isWhite || old.size != size;
}
