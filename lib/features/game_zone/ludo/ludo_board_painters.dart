import 'dart:math';
import 'package:flutter/material.dart';
import 'ludo_engine.dart';

/// 52-step coordinates around the outer track as (col, row) on the 15x15 grid.
const List<List<int>> kLudoTrackCoordinates = [
  [1, 6],
  [2, 6],
  [3, 6],
  [4, 6],
  [5, 6],
  [6, 5],
  [6, 4],
  [6, 3],
  [6, 2],
  [6, 1],
  [6, 0],
  [7, 0],
  [8, 0],
  [8, 1],
  [8, 2],
  [8, 3],
  [8, 4],
  [8, 5],
  [9, 6],
  [10, 6],
  [11, 6],
  [12, 6],
  [13, 6],
  [14, 6],
  [14, 7],
  [14, 8],
  [13, 8],
  [12, 8],
  [11, 8],
  [10, 8],
  [9, 8],
  [8, 9],
  [8, 10],
  [8, 11],
  [8, 12],
  [8, 13],
  [8, 14],
  [7, 14],
  [6, 14],
  [6, 13],
  [6, 12],
  [6, 11],
  [6, 10],
  [6, 9],
  [5, 8],
  [4, 8],
  [3, 8],
  [2, 8],
  [1, 8],
  [0, 8],
  [0, 7],
  [0, 6],
];

/// Realistic 3D dice face with recessed pips.
class LudoDiceFacePainter extends CustomPainter {
  const LudoDiceFacePainter(this.value);

  final int value;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.095;
    double x(double f) => size.width * f;
    double y(double f) => size.height * f;
    const lo = 0.27;
    const mid = 0.5;
    const hi = 0.73;
    final pips = <Offset>[
      if (value.isOdd) Offset(x(mid), y(mid)),
      if (value >= 2) ...[Offset(x(lo), y(lo)), Offset(x(hi), y(hi))],
      if (value >= 4) ...[Offset(x(hi), y(lo)), Offset(x(lo), y(hi))],
      if (value == 6) ...[Offset(x(lo), y(mid)), Offset(x(hi), y(mid))],
    ];

    final pipFill = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.25, -0.25),
        colors: [Color(0xFF374151), Color(0xFF1F2937), Color(0xFF111827)],
      ).createShader(Offset.zero & size);

    for (final p in pips) {
      // Recessed concave drop shadow
      canvas.drawCircle(p + const Offset(0.5, 0.8), r,
          Paint()..color = const Color(0x33000000));
      // Pip cavity
      canvas.drawCircle(p, r, pipFill);
      // Specular glint
      canvas.drawCircle(
        p + Offset(-r * 0.28, -r * 0.28),
        r * 0.26,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LudoDiceFacePainter oldDelegate) =>
      oldDelegate.value != value;
}

/// Central home 3x3 square painter with 4 colored triangles meeting at the center.
class LudoCenterHomePainter extends CustomPainter {
  const LudoCenterHomePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);

    void triangle(Color color, Offset a, Offset b) {
      paint.shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [
          Color.lerp(color, Colors.white, 0.25)!,
          color,
          Color.lerp(color, Colors.black, 0.35)!,
        ],
      ).createShader(Rect.fromPoints(a, b));
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(center.dx, center.dy)
            ..lineTo(b.dx, b.dy)
            ..close(),
          paint);
    }

    triangle(LudoColor.red.color, Offset.zero, Offset(0, size.height));
    triangle(LudoColor.green.color, Offset.zero, Offset(size.width, 0));
    triangle(LudoColor.yellow.color, Offset(size.width, 0),
        Offset(size.width, size.height));
    triangle(LudoColor.blue.color, Offset(0, size.height),
        Offset(size.width, size.height));

    // Central victory star medal
    canvas.drawCircle(
      center,
      size.width * 0.18,
      Paint()
        ..color = const Color(0xFFFFD54F)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      size.width * 0.18,
      Paint()
        ..color = const Color(0xFFB8860B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Full pathway grid painter with authentic home columns, tinted start cells, and safe stars.
class LudoPathwayGridPainter extends CustomPainter {
  final double cellSize;

  const LudoPathwayGridPainter({required this.cellSize});

  Rect _cell(num col, num row) =>
      Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize);

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    // Home columns in each player's colour.
    void homeColumn(LudoColor color, Iterable<Rect> cells) {
      fillPaint.color = color.color.withValues(alpha: 0.45);
      for (final rect in cells) {
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);
      }
    }

    homeColumn(LudoColor.red, [for (int c = 1; c <= 5; c++) _cell(c, 7)]);
    homeColumn(LudoColor.green, [for (int r = 1; r <= 5; r++) _cell(7, r)]);
    homeColumn(LudoColor.yellow, [for (int c = 9; c <= 13; c++) _cell(c, 7)]);
    homeColumn(LudoColor.blue, [for (int r = 9; r <= 13; r++) _cell(7, r)]);

    // Every track square gets an outline; start squares are tinted with
    // their owner's colour and all safe squares carry a star.
    final startColors = {for (final c in LudoColor.values) c.startIndex: c};
    for (int i = 0; i < kLudoTrackCoordinates.length; i++) {
      final rect =
          _cell(kLudoTrackCoordinates[i][0], kLudoTrackCoordinates[i][1]);
      final owner = startColors[i];
      if (owner != null) {
        fillPaint.color = owner.color.withValues(alpha: 0.75);
        canvas.drawRect(rect, fillPaint);
      } else if (LudoEngine.safeIndices.contains(i)) {
        fillPaint.color = const Color(0xFFE8E8E8);
        canvas.drawRect(rect, fillPaint);
      }
      canvas.drawRect(rect, borderPaint);
      if (LudoEngine.safeIndices.contains(i)) {
        _drawStar(
            canvas,
            rect,
            owner == LudoColor.yellow || owner == null
                ? const Color(0x99000000)
                : const Color(0xCCFFFFFF));
      }
    }
  }

  void _drawStar(Canvas canvas, Rect rect, Color color) {
    final center = rect.center;
    final outer = rect.width * 0.32;
    final inner = outer * 0.45;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -pi / 2 + i * pi / 5;
      final point = Offset(
          center.dx + radius * cos(angle), center.dy + radius * sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    // Drop shadow
    canvas.drawPath(path.shift(const Offset(0.5, 0.8)),
        Paint()..color = const Color(0x33000000));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant LudoPathwayGridPainter oldDelegate) =>
      oldDelegate.cellSize != cellSize;
}
