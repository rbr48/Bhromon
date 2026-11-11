import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/forest_palette.dart';
import '../../../../core/theme/theme_context.dart';
import '../../../tour_group/domain/services/ppc_curve.dart';

/// A production possibility curve from a `chart:ppc` fence, as an interactive
/// simulator. The reader drags or taps the chart to place a production mix.
/// The readings say whether the mix is efficient, inefficient or unattainable,
/// the most of Y possible with that much X, and what one more unit of X costs
/// in Y. The model is in `ppc_curve.dart`; the booklet draws the same curve.
class PpcChartWidget extends StatefulWidget {
  const PpcChartWidget({super.key, required this.spec});

  final PpcSpec spec;

  @override
  State<PpcChartWidget> createState() => _PpcChartWidgetState();
}

class _PpcChartWidgetState extends State<PpcChartWidget> {
  /// A touch this close (in pixels) to the frontier lands exactly on it.
  static const double _snapPixels = 14;

  /// The production mix the reader has placed, in data units.
  late PpcXY _chosen;

  @override
  void initState() {
    super.initState();
    _chosen = _startingMix(widget.spec);
  }

  @override
  void didUpdateWidget(PpcChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.spec, widget.spec)) {
      _chosen = _startingMix(widget.spec);
    }
  }

  /// The first marked point, or the middle of the frontier when there is none.
  static PpcXY _startingMix(PpcSpec spec) {
    if (spec.points.isNotEmpty) {
      final first = spec.points.first;
      return PpcXY(first.x, first.y);
    }
    final x = spec.xMax / 2;
    return PpcXY(x, spec.frontierY(x) ?? 0);
  }

  /// Moves the chosen mix to the touch at [local], inside a plot of [size].
  void _moveTo(Offset local, Size size, PpcSpec spec) {
    final plot = _plotRect(size);
    final x = _clampTo(
      (local.dx - plot.left) / plot.width * spec.axisMaxX,
      spec.axisMaxX,
    );
    var y = _clampTo(
      (plot.bottom - local.dy) / plot.height * spec.axisMaxY,
      spec.axisMaxY,
    );
    final curve = spec.frontierY(x);
    if (curve != null) {
      final curvePixel = plot.bottom - curve / spec.axisMaxY * plot.height;
      if ((local.dy - curvePixel).abs() <= _snapPixels) y = curve;
    }
    setState(() => _chosen = PpcXY(x, y));
  }

  static double _clampTo(double value, double max) {
    if (value < 0) return 0;
    if (value > max) return max;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final forest = context.forest;
    final l10n = context.l10n;
    final scene = spec.scene();
    // The app's text style, so the labels drawn on the chart carry its fonts,
    // including the Bengali fallback.
    final labelBase =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle();
    final position = spec.positionOf(_chosen.x, _chosen.y);
    final frontierY = spec.frontierY(_chosen.x);
    final ink = _PpcInk(
      axis: forest.text54,
      text: forest.text,
      frontier: forest.accentText,
      growth: forest.readable(Colors.orangeAccent),
      inside: forest.text70,
      outside: forest.text38,
      chosen: forest.text,
    );
    final readout = l10n.translate('ppc_point_readout', args: {
      'x': spec.xLabel,
      'xv': l10n.number(formatPpcNumber(_chosen.x)),
      'y': spec.yLabel,
      'yv': l10n.number(formatPpcNumber(_chosen.y)),
    });
    final statusKey = switch (position) {
      PpcPosition.efficient => 'ppc_status_efficient',
      PpcPosition.inside => 'ppc_status_inside',
      PpcPosition.outside => 'ppc_status_outside',
    };
    final statusColor = switch (position) {
      PpcPosition.efficient => forest.accentText,
      PpcPosition.inside => forest.text70,
      PpcPosition.outside => forest.text54,
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: forest.feedSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.title != null) ...[
            Text(
              spec.title!,
              style: TextStyle(
                color: forest.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = math.min(320.0, math.max(200.0, width / 1.5));
              final size = Size(width, height);
              return Semantics(
                container: true,
                label: readout,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      _moveTo(details.localPosition, size, spec),
                  onPanStart: (details) =>
                      _moveTo(details.localPosition, size, spec),
                  onPanUpdate: (details) =>
                      _moveTo(details.localPosition, size, spec),
                  child: CustomPaint(
                    size: size,
                    painter: _PpcPainter(
                      scene: scene,
                      chosen: PpcXY(
                        _chosen.x / spec.axisMaxX,
                        _chosen.y / spec.axisMaxY,
                      ),
                      xLabel: spec.xLabel,
                      yLabel: spec.yLabel,
                      ink: ink,
                      labelStyle: labelBase.copyWith(
                        color: forest.text70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (spec.growth != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _LegendLine(color: ink.frontier),
                const SizedBox(width: 6),
                Text(
                  l10n.translate('ppc_legend_frontier'),
                  style: TextStyle(color: forest.text70, fontSize: 11.5),
                ),
                const SizedBox(width: 16),
                _LegendLine(color: ink.growth, dashed: true),
                const SizedBox(width: 6),
                Text(
                  l10n.translate('ppc_legend_growth'),
                  style: TextStyle(color: forest.text70, fontSize: 11.5),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.translate(statusKey),
            style: TextStyle(
              color: statusColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            readout,
            style: TextStyle(color: forest.text70, fontSize: 12.5),
          ),
          if (frontierY != null) ...[
            const SizedBox(height: 2),
            Text(
              l10n.translate('ppc_max_at_x', args: {
                'x': spec.xLabel,
                'y': spec.yLabel,
                'value': l10n.number(formatPpcNumber(frontierY)),
              }),
              style: TextStyle(color: forest.text70, fontSize: 12.5),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.translate('ppc_opportunity_cost', args: {
                'x': spec.xLabel,
                'y': spec.yLabel,
                'value': _costText(spec.opportunityCost(_chosen.x), l10n),
              }),
              style: TextStyle(color: forest.text70, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            l10n.translate('ppc_hint'),
            style: TextStyle(color: forest.text54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// The cost of one more unit of X, in Y: infinite at the X intercept of a
  /// bowed-out frontier, where the curve is vertical.
  static String _costText(double cost, AppLocalizations l10n) {
    if (!cost.isFinite) return '∞';
    return l10n.number(formatPpcNumber(cost, decimals: 2));
  }
}

/// The plot area inside a chart of [size]: room on the left for the Y values,
/// above it for the Y label, and below for the X values and label.
Rect _plotRect(Size size) {
  return Rect.fromLTRB(44, 26, size.width - 14, size.height - 32);
}

/// The colours the chart draws with, taken from the reader's theme.
class _PpcInk {
  const _PpcInk({
    required this.axis,
    required this.text,
    required this.frontier,
    required this.growth,
    required this.inside,
    required this.outside,
    required this.chosen,
  });

  final Color axis;
  final Color text;
  final Color frontier;
  final Color growth;
  final Color inside;
  final Color outside;
  final Color chosen;
}

class _PpcPainter extends CustomPainter {
  _PpcPainter({
    required this.scene,
    required this.chosen,
    required this.xLabel,
    required this.yLabel,
    required this.ink,
    required this.labelStyle,
  });

  final PpcScene scene;

  /// The reader's production mix, from 0 to 1 on both axes.
  final PpcXY chosen;
  final String xLabel;
  final String yLabel;
  final _PpcInk ink;
  final TextStyle labelStyle;

  static const double _markRadius = 4.2;

  Offset _at(Rect plot, PpcXY point) {
    return Offset(
      plot.left + point.x * plot.width,
      plot.bottom - point.y * plot.height,
    );
  }

  Path _path(Rect plot, List<PpcXY> samples) {
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final at = _at(plot, samples[i]);
      if (i == 0) {
        path.moveTo(at.dx, at.dy);
      } else {
        path.lineTo(at.dx, at.dy);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _plotRect(size);

    // The attainable area, under the frontier.
    final area = Path()..moveTo(plot.left, plot.bottom);
    for (final point in scene.frontier) {
      final at = _at(plot, point);
      area.lineTo(at.dx, at.dy);
    }
    area.close();
    canvas.drawPath(
      area,
      Paint()..color = ink.frontier.withValues(alpha: 0.12),
    );

    final axis = Paint()
      ..color = ink.axis
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axis);

    if (scene.growthFrontier.isNotEmpty) {
      final growth = Paint()
        ..color = ink.growth
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      _drawDashed(
        canvas,
        [for (final point in scene.growthFrontier) _at(plot, point)],
        growth,
      );
    }

    canvas.drawPath(
      _path(plot, scene.frontier),
      Paint()
        ..color = ink.frontier
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    for (final tick in scene.ticks) {
      final color = tick.afterGrowth ? ink.growth : ink.text;
      final style = labelStyle.copyWith(color: color, fontSize: 11);
      final at = _at(plot, tick.at);
      if (tick.onXAxis) {
        canvas.drawLine(
          Offset(at.dx, plot.bottom),
          Offset(at.dx, plot.bottom + 4),
          axis,
        );
        _text(canvas, tick.text, style, Offset(at.dx, plot.bottom + 5),
            align: _Align.centerTop);
      } else {
        canvas.drawLine(
          Offset(plot.left - 4, at.dy),
          Offset(plot.left, at.dy),
          axis,
        );
        _text(canvas, tick.text, style, Offset(plot.left - 6, at.dy),
            align: _Align.rightMiddle);
      }
    }

    _text(canvas, yLabel, labelStyle.copyWith(color: ink.text),
        Offset(plot.left - 4, 4));
    _text(canvas, xLabel, labelStyle.copyWith(color: ink.text),
        Offset(plot.right, plot.bottom + 16),
        align: _Align.rightTop);

    for (final mark in scene.marks) {
      final at = _at(plot, mark.at);
      final dot = Paint();
      switch (mark.position) {
        case PpcPosition.efficient:
          dot.color = ink.frontier;
        case PpcPosition.inside:
          dot.color = ink.inside;
        case PpcPosition.outside:
          dot
            ..color = ink.outside
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6;
      }
      canvas.drawCircle(at, _markRadius, dot);
      _text(
        canvas,
        mark.label,
        labelStyle.copyWith(color: ink.text, fontWeight: FontWeight.w700),
        Offset(at.dx + 6, at.dy - 14),
      );
    }

    final at = _at(plot, chosen);
    final guide = Paint()
      ..color = ink.axis
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    _drawDashed(canvas, [Offset(at.dx, plot.bottom), at], guide);
    _drawDashed(canvas, [Offset(plot.left, at.dy), at], guide);
    canvas.drawCircle(at, 7, Paint()..color = ink.frontier);
    canvas.drawCircle(
      at,
      7,
      Paint()
        ..color = ink.chosen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _text(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset anchor, {
    _Align align = _Align.leftTop,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    final height = painter.height;
    final origin = switch (align) {
      _Align.leftTop => anchor,
      _Align.centerTop => Offset(anchor.dx - width / 2, anchor.dy),
      _Align.rightTop => Offset(anchor.dx - width, anchor.dy),
      _Align.rightMiddle => Offset(anchor.dx - width, anchor.dy - height / 2),
    };
    painter.paint(canvas, origin);
    painter.dispose();
  }

  @override
  bool shouldRepaint(_PpcPainter oldDelegate) => true;
}

enum _Align { leftTop, centerTop, rightTop, rightMiddle }

/// Draws a dashed polyline through [points].
void _drawDashed(Canvas canvas, List<Offset> points, Paint paint) {
  const dash = 6.0;
  const gap = 4.0;
  var drawing = true;
  var remaining = dash;
  for (var i = 1; i < points.length; i++) {
    var from = points[i - 1];
    final to = points[i];
    var length = (to - from).distance;
    if (length == 0) continue;
    final direction = (to - from) / length;
    while (length > 0) {
      final step = math.min(length, remaining);
      final end = from + direction * step;
      if (drawing) canvas.drawLine(from, end, paint);
      from = end;
      length -= step;
      remaining -= step;
      if (remaining <= 0) {
        drawing = !drawing;
        remaining = drawing ? dash : gap;
      }
    }
  }
}

/// A short solid or dashed line, to explain the two curves in the legend.
class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.color, this.dashed = false});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 4),
      painter: _LegendLinePainter(color: color, dashed: dashed),
    );
  }
}

class _LegendLinePainter extends CustomPainter {
  _LegendLinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = dashed ? 1.8 : 2.4
      ..style = PaintingStyle.stroke;
    final middle = size.height / 2;
    final line = [Offset(0, middle), Offset(size.width, middle)];
    if (dashed) {
      _drawDashed(canvas, line, paint);
    } else {
      canvas.drawLine(line[0], line[1], paint);
    }
  }

  @override
  bool shouldRepaint(_LegendLinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.dashed != dashed;
  }
}
