import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

import 'ppc_curve.dart';

/// Draws a production possibility curve for the printed booklet.
///
/// The curve, the axes, the dashed shifted frontier and the points are PDF
/// paths, so they print sharp at any size. The values and names are ordinary
/// text laid over the drawing, shaped like the rest of the booklet's text. The
/// coordinates come from the same [PpcScene] the in-app simulator draws.
///
/// [width] and [height] are in points.
pw.Widget ppcPdfFigure(
  PpcSpec spec, {
  required double width,
  double height = 230,
}) {
  final scene = spec.scene();

  // Margins inside the figure: room for the Y values, the Y label above the
  // axis, and the X values and label below it.
  const left = 40.0;
  const top = 26.0;
  const right = 16.0;
  const bottom = 30.0;
  final plotWidth = width - left - right;
  final plotHeight = height - top - bottom;

  // PDF drawing coordinates have their origin at the bottom left.
  PdfPoint toPdf(PpcXY point) {
    return PdfPoint(
      left + point.x * plotWidth,
      bottom + point.y * plotHeight,
    );
  }

  // Positioned children are measured from the top left.
  double fromTop(double pdfY) => height - pdfY;

  const ink = PdfColor(0.08, 0.25, 0.18);
  const growthInk = PdfColor(0.72, 0.36, 0.02);
  const area = PdfColor(0.90, 0.95, 0.92);
  const axisInk = PdfColor(0.35, 0.35, 0.35);

  void paintFigure(PdfGraphics canvas, PdfPoint _) {
    final frontier = [for (final p in scene.frontier) toPdf(p)];

    // The attainable area, under the frontier.
    canvas
      ..setFillColor(area)
      ..moveTo(left, bottom);
    for (final point in frontier) {
      canvas.lineTo(point.x, point.y);
    }
    canvas
      ..closePath()
      ..fillPath();

    // The axes.
    canvas
      ..setStrokeColor(axisInk)
      ..setLineWidth(0.8)
      ..moveTo(left, bottom)
      ..lineTo(left + plotWidth, bottom)
      ..strokePath()
      ..moveTo(left, bottom)
      ..lineTo(left, bottom + plotHeight)
      ..strokePath();

    // The tick marks at the intercepts.
    for (final tick in scene.ticks) {
      final at = toPdf(tick.at);
      canvas.setStrokeColor(axisInk);
      canvas.setLineWidth(0.6);
      if (tick.onXAxis) {
        canvas
          ..moveTo(at.x, bottom)
          ..lineTo(at.x, bottom - 3);
      } else {
        canvas
          ..moveTo(left, at.y)
          ..lineTo(left - 3, at.y);
      }
      canvas.strokePath();
    }

    // The shifted frontier after growth, dashed, so it prints in black and
    // white too.
    if (scene.growthFrontier.isNotEmpty) {
      canvas
        ..setStrokeColor(growthInk)
        ..setLineWidth(1.1)
        ..setLineDashPattern([4, 3]);
      _polyline(canvas, [for (final p in scene.growthFrontier) toPdf(p)]);
      canvas.setLineDashPattern();
    }

    canvas
      ..setStrokeColor(ink)
      ..setLineWidth(1.6);
    _polyline(canvas, frontier);

    // The marked production mixes: filled when efficient or inside, ringed
    // when unattainable.
    for (final mark in scene.marks) {
      final at = toPdf(mark.at);
      switch (mark.position) {
        case PpcPosition.efficient:
          canvas.setFillColor(ink);
          canvas.drawEllipse(at.x, at.y, 2.6, 2.6);
          canvas.fillPath();
        case PpcPosition.inside:
          canvas.setFillColor(axisInk);
          canvas.drawEllipse(at.x, at.y, 2.6, 2.6);
          canvas.fillPath();
        case PpcPosition.outside:
          canvas.setStrokeColor(axisInk);
          canvas.setLineWidth(0.9);
          canvas.drawEllipse(at.x, at.y, 2.6, 2.6);
          canvas.strokePath();
      }
    }
  }

  final labels = <pw.Widget>[
    pw.Positioned(
      left: left - 4,
      top: 2,
      child: pw.Text(spec.yLabel, style: _labelStyle),
    ),
    pw.Positioned(
      right: right,
      top: height - bottom + 13,
      child: pw.Text(spec.xLabel, style: _labelStyle),
    ),
    for (final tick in scene.ticks) _tickLabel(tick, toPdf, fromTop, left),
    for (final mark in scene.marks)
      pw.Positioned(
        left: toPdf(mark.at).x + 4,
        top: fromTop(toPdf(mark.at).y) - 12,
        child: pw.Text(mark.label, style: _markStyle),
      ),
  ];

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      if (spec.title != null) ...[
        pw.Text(
          spec.title!,
          style: const pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey900,
          ),
        ),
        pw.SizedBox(height: 4),
      ],
      pw.SizedBox(
        width: width,
        height: height,
        child: pw.Stack(
          children: [
            pw.CustomPaint(
              size: PdfPoint(width, height),
              painter: paintFigure,
            ),
            ...labels,
          ],
        ),
      ),
      if (spec.growth != null) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          'Solid line: production possibility frontier. '
          'Dashed line: after growth.',
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
        ),
      ],
    ],
  );
}

const _labelStyle = pw.TextStyle(
  fontSize: 8.5,
  fontWeight: pw.FontWeight.bold,
  color: PdfColors.grey900,
);

const _markStyle = pw.TextStyle(
  fontSize: 8.5,
  fontWeight: pw.FontWeight.bold,
  color: PdfColors.grey900,
);

const _tickStyle = pw.TextStyle(fontSize: 8, color: PdfColors.grey800);

const _growthTickStyle = pw.TextStyle(
  fontSize: 8,
  color: PdfColor(0.72, 0.36, 0.02),
);

/// The value at an intercept, set beside its axis. The width of the text is
/// not known until it is laid out, so the offset estimates it from the number
/// of characters; the digits are of equal width, so the estimate is close.
pw.Widget _tickLabel(
  PpcTick tick,
  PdfPoint Function(PpcXY) toPdf,
  double Function(double) fromTop,
  double left,
) {
  final at = toPdf(tick.at);
  final style = tick.afterGrowth ? _growthTickStyle : _tickStyle;
  if (tick.onXAxis) {
    return pw.Positioned(
      left: at.x - tick.text.length * 2.4,
      top: fromTop(at.y) + 3,
      child: pw.Text(tick.text, style: style),
    );
  }
  return pw.Positioned(
    left: left - 6 - tick.text.length * 4.6,
    top: fromTop(at.y) - 5,
    child: pw.Text(tick.text, style: style),
  );
}

/// Joins [points] with straight segments and strokes them.
void _polyline(PdfGraphics canvas, List<PdfPoint> points) {
  for (var i = 0; i < points.length; i++) {
    if (i == 0) {
      canvas.moveTo(points[i].x, points[i].y);
    } else {
      canvas.lineTo(points[i].x, points[i].y);
    }
  }
  canvas.strokePath();
}
