import 'dart:math' as math;

/// A production possibility curve (PPC) written in a `chart:ppc` code fence.
///
/// Each line of the fence is `key: value`. A line that starts with `#` or `//`
/// is a comment, and an unknown key is ignored, so a newer note still reads:
///
///     title: উৎপাদন সম্ভাবনা সীমা
///     x: কৃষিপণ্য (টন)
///     y: শিল্পপণ্য (টন)
///     xmax: 100
///     ymax: 80
///     shape: 2
///     growth: 1.2
///     point A: 20 70
///
/// `xmax` and `ymax` are the intercepts of the frontier: the most of each good
/// that can be made when no resource goes to the other. `shape` is 1 for a
/// straight frontier (every extra unit of X costs the same Y) and 2 by default,
/// a bowed-out frontier (the cost rises as more X is made). `growth` draws the
/// frontier again, scaled outwards, as after more resources or better
/// technology. A `point` is a production mix: on the frontier it is efficient,
/// inside it is inefficient, and beyond it the mix is unattainable.
///
/// The model is pure Dart. The in-app simulator and the printed booklet both
/// draw from [PpcSpec.scene], so the two always show the same curve.
class PpcSpec {
  const PpcSpec({
    this.title,
    this.xLabel = 'X',
    this.yLabel = 'Y',
    required this.xMax,
    required this.yMax,
    this.shape = 2,
    this.growth,
    this.points = const [],
  })  : assert(xMax > 0),
        assert(yMax > 0),
        assert(shape >= 1 && shape <= maxShape),
        assert(growth == null || (growth > 1 && growth <= maxGrowth));

  /// The most points one chart can mark.
  static const int maxPoints = 8;

  /// The largest allowed [shape]. Above it the curve is nearly an L.
  static const double maxShape = 8;

  /// The largest allowed [growth] factor.
  static const double maxGrowth = 3;

  /// Longer fences are not charts; they stay as plain text.
  static const int maxSourceLength = 2000;

  /// The plot runs this far past the largest intercept, so the ends of the
  /// curve and their labels stay inside it.
  static const double _axisPadding = 1.1;

  /// A mix within this share of the Y intercept of the frontier counts as on it.
  static const double _onFrontierShare = 0.02;

  static const int _samples = 120;

  final String? title;
  final String xLabel;
  final String yLabel;

  /// The most X that can be made when no resource goes to Y.
  final double xMax;

  /// The most Y that can be made when no resource goes to X.
  final double yMax;

  /// 1 for a straight frontier, 2 for a bowed-out one, larger bends harder.
  final double shape;

  /// The factor by which the frontier is shifted outwards, or null for none.
  final double? growth;

  final List<PpcPoint> points;

  double get _growthFactor => growth ?? 1;

  /// The X extent of the plot, in data units.
  double get axisMaxX => xMax * _growthFactor * _axisPadding;

  /// The Y extent of the plot, in data units.
  double get axisMaxY => yMax * _growthFactor * _axisPadding;

  /// The most Y that can be made with [x] of X, or null beyond the X intercept.
  double? frontierY(double x) {
    if (x < 0 || x > xMax) return null;
    return _frontierAt(x, xMax, yMax, shape);
  }

  /// The slope of the frontier at [x] (dY/dX, negative). It is -infinity at
  /// the X intercept when [shape] is above 1.
  double slopeAt(double x) => _frontierSlope(x, xMax, yMax, shape);

  /// The units of Y given up for one more unit of X, at [x].
  double opportunityCost(double x) => -slopeAt(x);

  /// Where the production mix (x, y) sits against the frontier.
  PpcPosition positionOf(double x, double y) {
    final frontier = frontierY(x);
    if (frontier == null) return PpcPosition.outside;
    final gap = y - frontier;
    if (gap.abs() <= yMax * _onFrontierShare) return PpcPosition.efficient;
    return gap < 0 ? PpcPosition.inside : PpcPosition.outside;
  }

  /// The drawing of this curve, with every coordinate scaled to 0 to 1 on
  /// both axes.
  PpcScene scene() {
    PpcXY plot(double x, double y) => PpcXY(x / axisMaxX, y / axisMaxY);
    final growthXMax = xMax * _growthFactor;
    final growthYMax = yMax * _growthFactor;
    return PpcScene(
      frontier: [for (final p in _samplesOf(xMax, yMax)) plot(p.x, p.y)],
      growthFrontier: growth == null
          ? const []
          : [
              for (final p in _samplesOf(growthXMax, growthYMax))
                plot(p.x, p.y),
            ],
      marks: [
        for (final p in points)
          PpcMark(
            at: plot(p.x, p.y),
            label: p.label,
            position: positionOf(p.x, p.y),
          ),
      ],
      ticks: [
        PpcTick(at: plot(xMax, 0), text: formatPpcNumber(xMax), onXAxis: true),
        PpcTick(at: plot(0, yMax), text: formatPpcNumber(yMax), onXAxis: false),
        if (growth != null) ...[
          PpcTick(
            at: plot(growthXMax, 0),
            text: formatPpcNumber(growthXMax),
            onXAxis: true,
            afterGrowth: true,
          ),
          PpcTick(
            at: plot(0, growthYMax),
            text: formatPpcNumber(growthYMax),
            onXAxis: false,
            afterGrowth: true,
          ),
        ],
      ],
    );
  }

  /// Samples of the frontier from the Y intercept to the X intercept. The
  /// samples are denser near the X intercept, where the curve is steepest.
  List<PpcXY> _samplesOf(double maxX, double maxY) {
    final samples = <PpcXY>[];
    for (var i = 0; i < _samples; i++) {
      final t = i / (_samples - 1);
      final x = maxX * (1 - (1 - t) * (1 - t));
      samples.add(PpcXY(x, _frontierAt(x, maxX, maxY, shape)));
    }
    return samples;
  }

  /// Reads a fence body. Returns null when the body is not a usable curve: a
  /// missing or invalid intercept, a bad shape or growth, a point that is not
  /// on the plot, or more than [maxPoints] points. The reader then shows the
  /// fence as plain text, so a mistake is visible rather than silently lost.
  static PpcSpec? parse(String source) {
    if (source.length > maxSourceLength) return null;
    String? title;
    var xLabel = 'X';
    var yLabel = 'Y';
    double? xMax;
    double? yMax;
    double? shape;
    double? growth;
    final points = <PpcPoint>[];

    for (final rawLine in source.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
        continue;
      }
      final colon = line.indexOf(':');
      if (colon <= 0) return null;
      final key = line.substring(0, colon).trim();
      final value = _asciiDigits(line.substring(colon + 1).trim());

      final lowerKey = key.toLowerCase();
      if (lowerKey == 'point' || lowerKey.startsWith('point ')) {
        final label = key.length > 'point'.length
            ? key.substring('point'.length).trim()
            : '';
        final pair = _pair(value);
        if (label.isEmpty || pair == null) return null;
        points.add(PpcPoint(label: label, x: pair.$1, y: pair.$2));
        continue;
      }

      switch (lowerKey) {
        case 'title':
          title = value.isEmpty ? null : value;
          break;
        case 'x':
          if (value.isNotEmpty) xLabel = value;
          break;
        case 'y':
          if (value.isNotEmpty) yLabel = value;
          break;
        case 'xmax':
          xMax = _number(value);
          if (xMax == null || xMax <= 0) return null;
          break;
        case 'ymax':
          yMax = _number(value);
          if (yMax == null || yMax <= 0) return null;
          break;
        case 'shape':
          shape = _number(value);
          if (shape == null || shape < 1 || shape > maxShape) return null;
          break;
        case 'growth':
          growth = _number(value);
          if (growth == null || growth <= 1 || growth > maxGrowth) return null;
          break;
        default:
          break;
      }
    }

    if (xMax == null || yMax == null || points.length > maxPoints) return null;
    final spec = PpcSpec(
      title: title,
      xLabel: xLabel,
      yLabel: yLabel,
      xMax: xMax,
      yMax: yMax,
      shape: shape ?? 2,
      growth: growth,
      points: List<PpcPoint>.unmodifiable(points),
    );
    for (final point in spec.points) {
      if (point.x > spec.axisMaxX || point.y > spec.axisMaxY) return null;
    }
    return spec;
  }

  static double _frontierAt(double x, double maxX, double maxY, double shape) {
    final t = (x / maxX).clamp(0.0, 1.0);
    return maxY * math.pow(1 - math.pow(t, shape), 1 / shape).toDouble();
  }

  static double _frontierSlope(
    double x,
    double maxX,
    double maxY,
    double shape,
  ) {
    final t = (x / maxX).clamp(0.0, 1.0);
    final rising = math.pow(t, shape - 1).toDouble();
    final falling = math.pow(1 - math.pow(t, shape), 1 / shape - 1).toDouble();
    return -(maxY / maxX) * rising * falling;
  }

  static double? _number(String text) {
    final value = double.tryParse(text);
    return value != null && value.isFinite ? value : null;
  }

  static (double, double)? _pair(String text) {
    final parts =
        text.split(RegExp(r'[\s,]+')).where((part) => part.isNotEmpty).toList();
    if (parts.length != 2) return null;
    final x = _number(parts[0]);
    final y = _number(parts[1]);
    if (x == null || y == null || x < 0 || y < 0) return null;
    return (x, y);
  }

  /// Bengali digits written as Western ones, so a note may use either.
  static String _asciiDigits(String text) {
    final out = StringBuffer();
    for (final unit in text.codeUnits) {
      final digit = unit - 0x09E6;
      out.writeCharCode(digit >= 0 && digit <= 9 ? 0x30 + digit : unit);
    }
    return out.toString();
  }
}

/// A production mix the chart marks, from a `point` line.
class PpcPoint {
  const PpcPoint({required this.label, required this.x, required this.y});

  final String label;
  final double x;
  final double y;
}

/// A coordinate: data units, or 0 to 1 on each axis inside a [PpcScene].
class PpcXY {
  const PpcXY(this.x, this.y);

  final double x;
  final double y;
}

/// Where a production mix sits against the frontier.
enum PpcPosition {
  /// On the frontier: no resource is idle.
  efficient,

  /// Inside the frontier: some resource is idle.
  inside,

  /// Beyond the frontier: not attainable with the current resources.
  outside,
}

/// A marked production mix, in plot coordinates.
class PpcMark {
  const PpcMark({
    required this.at,
    required this.label,
    required this.position,
  });

  final PpcXY at;
  final String label;
  final PpcPosition position;
}

/// An axis value at an intercept, in plot coordinates.
class PpcTick {
  const PpcTick({
    required this.at,
    required this.text,
    required this.onXAxis,
    this.afterGrowth = false,
  });

  final PpcXY at;
  final String text;

  /// True for the X axis, false for the Y axis.
  final bool onXAxis;

  /// True for an intercept of the shifted frontier.
  final bool afterGrowth;
}

/// The drawing of a [PpcSpec], with every coordinate from 0 to 1 on both axes.
/// The renderers scale it to their own canvas.
class PpcScene {
  const PpcScene({
    required this.frontier,
    required this.growthFrontier,
    required this.marks,
    required this.ticks,
  });

  /// Frontier samples, from the Y intercept to the X intercept.
  final List<PpcXY> frontier;

  /// The shifted frontier after growth, or empty when there is none.
  final List<PpcXY> growthFrontier;

  final List<PpcMark> marks;
  final List<PpcTick> ticks;
}

/// A plot value as text: a whole number with no decimals, otherwise [decimals]
/// places.
String formatPpcNumber(double value, {int decimals = 1}) {
  final text = value.toStringAsFixed(decimals);
  final zeros = '.${'0' * decimals}';
  return decimals > 0 && text.endsWith(zeros)
      ? text.substring(0, text.length - zeros.length)
      : text;
}
