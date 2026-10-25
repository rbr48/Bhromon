import 'dart:math';
import 'package:flutter/material.dart';
import 'chess_engine.dart';

/// Pixel-perfect vector Staunton chess piece painter.
/// Provides authentic tournament silhouettes for all six piece types,
/// guaranteeing crisp rendering immune to Android emoji font fallback.
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
    final strokeWidth = max(1.2, s * 0.055);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isWhite
            ? const [Color(0xFFFFFFFF), Color(0xFFF3F4F6), Color(0xFFE5E7EB)]
            : const [Color(0xFF374151), Color(0xFF1F2937), Color(0xFF111827)],
      ).createShader(Offset.zero & canvasSize);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = isWhite ? const Color(0xFF1F2937) : const Color(0xFFF9FAFB);

    switch (type) {
      case PieceType.pawn:
        _paintPawn(canvas, s, cx, fillPaint, strokePaint);
        break;
      case PieceType.knight:
        _paintKnight(canvas, s, cx, fillPaint, strokePaint);
        break;
      case PieceType.bishop:
        _paintBishop(canvas, s, cx, fillPaint, strokePaint);
        break;
      case PieceType.rook:
        _paintRook(canvas, s, cx, fillPaint, strokePaint);
        break;
      case PieceType.queen:
        _paintQueen(canvas, s, cx, fillPaint, strokePaint);
        break;
      case PieceType.king:
        _paintKing(canvas, s, cx, fillPaint, strokePaint);
        break;
    }
  }

  void _paintPawn(
      Canvas canvas, double s, double cx, Paint fill, Paint stroke) {
    final body = Path();
    body.moveTo(cx - s * 0.22, s * 0.81);
    body.lineTo(cx + s * 0.22, s * 0.81);
    body.quadraticBezierTo(cx + s * 0.22, s * 0.75, cx + s * 0.17, s * 0.74);
    body.lineTo(cx + s * 0.15, s * 0.70);
    body.quadraticBezierTo(cx + s * 0.08, s * 0.57, cx + s * 0.07, s * 0.49);
    body.lineTo(cx + s * 0.12, s * 0.47);
    body.quadraticBezierTo(cx + s * 0.12, s * 0.44, cx + s * 0.08, s * 0.44);
    body.lineTo(cx - s * 0.08, s * 0.44);
    body.quadraticBezierTo(cx - s * 0.12, s * 0.44, cx - s * 0.12, s * 0.47);
    body.lineTo(cx - s * 0.07, s * 0.49);
    body.quadraticBezierTo(cx - s * 0.08, s * 0.57, cx - s * 0.15, s * 0.70);
    body.lineTo(cx - s * 0.17, s * 0.74);
    body.quadraticBezierTo(cx - s * 0.22, s * 0.75, cx - s * 0.22, s * 0.81);
    body.close();

    final headCenter = Offset(cx, s * 0.33);
    final headRadius = s * 0.12;

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    canvas.drawCircle(headCenter, headRadius, fill);
    canvas.drawCircle(headCenter, headRadius, stroke);

    // Collar ring
    final collar = Path()
      ..moveTo(cx - s * 0.11, s * 0.46)
      ..lineTo(cx + s * 0.11, s * 0.46);
    canvas.drawPath(collar, stroke);
  }

  void _paintKnight(
      Canvas canvas, double s, double cx, Paint fill, Paint stroke) {
    final path = Path();
    // Base pedestal
    path.moveTo(cx - s * 0.25, s * 0.84);
    path.lineTo(cx + s * 0.25, s * 0.84);
    path.quadraticBezierTo(cx + s * 0.24, s * 0.77, cx + s * 0.18, s * 0.75);
    // Back of neck curving up with mane notches
    path.quadraticBezierTo(cx + s * 0.26, s * 0.52, cx + s * 0.12, s * 0.26);
    // Ear top
    path.lineTo(cx + s * 0.06, s * 0.18);
    path.lineTo(cx + s * 0.01, s * 0.24);
    // Forehead and snout
    path.lineTo(cx - s * 0.14, s * 0.33);
    path.quadraticBezierTo(cx - s * 0.28, s * 0.42, cx - s * 0.25, s * 0.50);
    // Muzzle / mouth
    path.lineTo(cx - s * 0.15, s * 0.52);
    // Jaw / throat
    path.quadraticBezierTo(cx - s * 0.05, s * 0.56, cx - s * 0.10, s * 0.68);
    // Chest down to base
    path.lineTo(cx - s * 0.18, s * 0.75);
    path.quadraticBezierTo(cx - s * 0.25, s * 0.77, cx - s * 0.25, s * 0.84);
    path.close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // Eye dot
    final eye = Offset(cx - s * 0.06, s * 0.36);
    canvas.drawCircle(eye, s * 0.025, stroke);

    // Mane groove
    final mane = Path()
      ..moveTo(cx + s * 0.08, s * 0.35)
      ..quadraticBezierTo(cx + s * 0.14, s * 0.48, cx + s * 0.12, s * 0.62);
    canvas.drawPath(mane, stroke);

    // Jaw crease
    final jaw = Path()
      ..moveTo(cx - s * 0.18, s * 0.48)
      ..lineTo(cx - s * 0.09, s * 0.49);
    canvas.drawPath(jaw, stroke);
  }

  void _paintBishop(
      Canvas canvas, double s, double cx, Paint fill, Paint stroke) {
    // Pedestal and stem
    final body = Path();
    body.moveTo(cx - s * 0.24, s * 0.84);
    body.lineTo(cx + s * 0.24, s * 0.84);
    body.quadraticBezierTo(cx + s * 0.22, s * 0.77, cx + s * 0.16, s * 0.75);
    body.lineTo(cx + s * 0.13, s * 0.62);
    // Flared miter body
    body.quadraticBezierTo(cx + s * 0.22, s * 0.42, cx, s * 0.24);
    body.quadraticBezierTo(cx - s * 0.22, s * 0.42, cx - s * 0.13, s * 0.62);
    body.lineTo(cx - s * 0.16, s * 0.75);
    body.quadraticBezierTo(cx - s * 0.22, s * 0.77, cx - s * 0.24, s * 0.84);
    body.close();

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    // Top sphere finial
    final finialCenter = Offset(cx, s * 0.20);
    canvas.drawCircle(finialCenter, s * 0.045, fill);
    canvas.drawCircle(finialCenter, s * 0.045, stroke);

    // Bishop's miter cut/cleft
    final cleft = Path()
      ..moveTo(cx - s * 0.01, s * 0.30)
      ..lineTo(cx + s * 0.09, s * 0.44);
    canvas.drawPath(cleft, stroke);

    // Collar line
    final collar = Path()
      ..moveTo(cx - s * 0.13, s * 0.60)
      ..lineTo(cx + s * 0.13, s * 0.60);
    canvas.drawPath(collar, stroke);
  }

  void _paintRook(
      Canvas canvas, double s, double cx, Paint fill, Paint stroke) {
    final body = Path();
    // Base
    body.moveTo(cx - s * 0.25, s * 0.84);
    body.lineTo(cx + s * 0.25, s * 0.84);
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
    body.quadraticBezierTo(cx - s * 0.23, s * 0.77, cx - s * 0.25, s * 0.84);
    body.close();

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    // Parapet trim line
    final trim = Path()
      ..moveTo(cx - s * 0.20, s * 0.43)
      ..lineTo(cx + s * 0.20, s * 0.43);
    canvas.drawPath(trim, stroke);
  }

  void _paintQueen(
      Canvas canvas, double s, double cx, Paint fill, Paint stroke) {
    // Base and gown
    final body = Path();
    body.moveTo(cx - s * 0.26, s * 0.84);
    body.lineTo(cx + s * 0.26, s * 0.84);
    body.quadraticBezierTo(cx + s * 0.24, s * 0.77, cx + s * 0.18, s * 0.75);
    body.lineTo(cx + s * 0.14, s * 0.58);
    body.quadraticBezierTo(cx + s * 0.10, s * 0.48, cx + s * 0.22, s * 0.32);
    // Coronet peaks
    body.lineTo(cx + s * 0.13, s * 0.39);
    body.lineTo(cx + s * 0.08, s * 0.29);
    body.lineTo(cx, s * 0.38);
    body.lineTo(cx - s * 0.08, s * 0.29);
    body.lineTo(cx - s * 0.13, s * 0.39);
    body.lineTo(cx - s * 0.22, s * 0.32);
    // Left gown down to base
    body.quadraticBezierTo(cx - s * 0.10, s * 0.48, cx - s * 0.14, s * 0.58);
    body.lineTo(cx - s * 0.18, s * 0.75);
    body.quadraticBezierTo(cx - s * 0.24, s * 0.77, cx - s * 0.26, s * 0.84);
    body.close();

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    // 5 jewels / pearls on the coronet peaks
    final pearlRadius = s * 0.025;
    final peaks = [
      Offset(cx - s * 0.22, s * 0.31),
      Offset(cx - s * 0.08, s * 0.28),
      Offset(cx, s * 0.24),
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

  void _paintKing(
      Canvas canvas, double s, double cx, Paint fill, Paint stroke) {
    // Base and royal robe
    final body = Path();
    body.moveTo(cx - s * 0.26, s * 0.84);
    body.lineTo(cx + s * 0.26, s * 0.84);
    body.quadraticBezierTo(cx + s * 0.24, s * 0.77, cx + s * 0.18, s * 0.75);
    body.lineTo(cx + s * 0.14, s * 0.54);
    // Arched domed royal crown
    body.quadraticBezierTo(cx + s * 0.20, s * 0.42, cx + s * 0.18, s * 0.33);
    body.quadraticBezierTo(cx + s * 0.08, s * 0.30, cx, s * 0.27);
    body.quadraticBezierTo(cx - s * 0.08, s * 0.30, cx - s * 0.18, s * 0.33);
    body.quadraticBezierTo(cx - s * 0.20, s * 0.42, cx - s * 0.14, s * 0.54);
    body.lineTo(cx - s * 0.18, s * 0.75);
    body.quadraticBezierTo(cx - s * 0.24, s * 0.77, cx - s * 0.26, s * 0.84);
    body.close();

    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    // Cross Pattée on crown
    final cross = Path();
    final top = s * 0.14;
    final bot = s * 0.26;
    // Vertical stem
    cross.moveTo(cx - s * 0.03, bot);
    cross.lineTo(cx - s * 0.03, top);
    cross.lineTo(cx + s * 0.03, top);
    cross.lineTo(cx + s * 0.03, bot);
    cross.close();
    // Horizontal arms
    cross.moveTo(cx - s * 0.08, s * 0.19);
    cross.lineTo(cx + s * 0.08, s * 0.19);
    cross.lineTo(cx + s * 0.08, s * 0.23);
    cross.lineTo(cx - s * 0.08, s * 0.23);
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
