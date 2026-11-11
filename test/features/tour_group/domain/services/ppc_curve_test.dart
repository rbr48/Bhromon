import 'package:bhromon/features/tour_group/domain/services/ppc_curve.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('frontier', () {
    const bowed = PpcSpec(xMax: 100, yMax: 80);

    test('meets both axes at its intercepts', () {
      expect(bowed.frontierY(0), closeTo(80, 1e-9));
      expect(bowed.frontierY(100), closeTo(0, 1e-9));
    });

    test('is undefined beyond the X intercept and below zero', () {
      expect(bowed.frontierY(101), isNull);
      expect(bowed.frontierY(-1), isNull);
    });

    test('bows out for shape 2: y = 80 * sqrt(1 - (x / 100)^2)', () {
      expect(bowed.frontierY(60), closeTo(64, 1e-9));
    });

    test('is a straight line for shape 1', () {
      const straight = PpcSpec(xMax: 100, yMax: 80, shape: 1);
      expect(straight.frontierY(25), closeTo(60, 1e-9));
      expect(straight.frontierY(50), closeTo(40, 1e-9));
    });

    test('has a constant opportunity cost for shape 1', () {
      const straight = PpcSpec(xMax: 100, yMax: 80, shape: 1);
      expect(straight.opportunityCost(10), closeTo(0.8, 1e-9));
      expect(straight.opportunityCost(90), closeTo(0.8, 1e-9));
    });

    test('has a rising opportunity cost for shape 2', () {
      expect(bowed.opportunityCost(0), closeTo(0, 1e-9));
      expect(bowed.opportunityCost(60), closeTo(0.6, 1e-9));
      expect(bowed.opportunityCost(50), lessThan(bowed.opportunityCost(80)));
    });
  });

  group('position of a production mix', () {
    const spec = PpcSpec(xMax: 100, yMax: 80);

    test('on the frontier is efficient', () {
      expect(spec.positionOf(60, 64), PpcPosition.efficient);
      expect(spec.positionOf(100, 0), PpcPosition.efficient);
    });

    test('a little below the frontier still counts as on it', () {
      // The tolerance is 2% of the Y intercept: 1.6 units here.
      expect(spec.positionOf(60, 63), PpcPosition.efficient);
    });

    test('well inside the frontier is inefficient', () {
      expect(spec.positionOf(60, 60), PpcPosition.inside);
      expect(spec.positionOf(0, 0), PpcPosition.inside);
    });

    test('beyond the frontier is unattainable', () {
      expect(spec.positionOf(60, 70), PpcPosition.outside);
      expect(spec.positionOf(101, 0), PpcPosition.outside);
    });
  });

  group('parse', () {
    test('reads a full fence, with Bengali digits and a colon in the title',
        () {
      final spec = PpcSpec.parse('''
title: শিরোনাম: উৎপাদন
x: কৃষিপণ্য (টন)
y: শিল্পপণ্য (টন)
xmax: ১০০
ymax: 80
shape: 2
growth: 1.2
point A: 20 70
point B: 60, 50
''');

      expect(spec, isNotNull);
      expect(spec!.title, 'শিরোনাম: উৎপাদন');
      expect(spec.xLabel, 'কৃষিপণ্য (টন)');
      expect(spec.yLabel, 'শিল্পপণ্য (টন)');
      expect(spec.xMax, 100);
      expect(spec.yMax, 80);
      expect(spec.shape, 2);
      expect(spec.growth, 1.2);
      expect(spec.points.map((p) => p.label), ['A', 'B']);
      expect(spec.points[1].x, 60);
      expect(spec.points[1].y, 50);
    });

    test('takes the defaults, skips comments and ignores unknown keys', () {
      final spec = PpcSpec.parse('''
# a comment
// another comment

xmax: 100
ymax: 80
colour: red
''');

      expect(spec, isNotNull);
      expect(spec!.title, isNull);
      expect(spec.xLabel, 'X');
      expect(spec.yLabel, 'Y');
      expect(spec.shape, 2);
      expect(spec.growth, isNull);
      expect(spec.points, isEmpty);
    });

    test('refuses a body that is not a usable curve', () {
      const bodies = [
        'ymax: 80', // no X intercept
        'xmax: 100', // no Y intercept
        'xmax: 0\nymax: 80',
        'xmax: abc\nymax: 80',
        'xmax: Infinity\nymax: 80',
        'xmax: 100\nymax: 80\nshape: 0.5',
        'xmax: 100\nymax: 80\nshape: 9',
        'xmax: 100\nymax: 80\ngrowth: 1',
        'xmax: 100\nymax: 80\ngrowth: 3.5',
        'xmax: 100\nymax: 80\njust some words',
        'xmax: 100\nymax: 80\npoint A: 20',
        'xmax: 100\nymax: 80\npoint : 20 30',
        'xmax: 100\nymax: 80\npoint Z: 200 10', // beyond the plot
      ];
      for (final body in bodies) {
        expect(PpcSpec.parse(body), isNull, reason: body);
      }
    });

    test('refuses more points than a chart can mark', () {
      final buffer = StringBuffer('xmax: 100\nymax: 80\n');
      for (var i = 0; i <= PpcSpec.maxPoints; i++) {
        buffer.writeln('point P$i: 10 10');
      }
      expect(PpcSpec.parse(buffer.toString()), isNull);
    });

    test('refuses a body longer than the limit', () {
      final long = 'xmax: 100\nymax: 80\n# ${'x' * PpcSpec.maxSourceLength}';
      expect(PpcSpec.parse(long), isNull);
    });
  });

  group('scene', () {
    test('scales the frontier onto 0 to 1 on both axes', () {
      const spec = PpcSpec(xMax: 100, yMax: 80);
      final scene = spec.scene();

      // The plot runs 10% past each intercept: 110 by 88.
      expect(scene.frontier, hasLength(120));
      expect(scene.frontier.first.x, closeTo(0, 1e-9));
      expect(scene.frontier.first.y, closeTo(80 / 88, 1e-9));
      expect(scene.frontier.last.x, closeTo(100 / 110, 1e-9));
      expect(scene.frontier.last.y, closeTo(0, 1e-9));
      expect(scene.growthFrontier, isEmpty);
      expect(scene.ticks.map((t) => t.text), ['100', '80']);
    });

    test('draws the shifted frontier and its intercepts after growth', () {
      const spec = PpcSpec(xMax: 100, yMax: 80, growth: 1.2);
      final scene = spec.scene();

      // The plot runs to 1.2 * 1.1 of the intercepts: 132 by 105.6.
      expect(scene.growthFrontier, hasLength(120));
      expect(scene.growthFrontier.first.y, closeTo(96 / 105.6, 1e-9));
      expect(scene.growthFrontier.last.x, closeTo(120 / 132, 1e-9));
      expect(
        scene.ticks.where((t) => t.afterGrowth).map((t) => t.text),
        ['120', '96'],
      );
      for (final point in [...scene.frontier, ...scene.growthFrontier]) {
        expect(point.x, inInclusiveRange(0, 1));
        expect(point.y, inInclusiveRange(0, 1));
      }
    });

    test('places and classifies each marked point', () {
      const spec = PpcSpec(
        xMax: 100,
        yMax: 80,
        points: [
          PpcPoint(label: 'A', x: 60, y: 64),
          PpcPoint(label: 'B', x: 60, y: 40),
        ],
      );
      final marks = spec.scene().marks;

      expect(marks[0].label, 'A');
      expect(marks[0].at.x, closeTo(60 / 110, 1e-9));
      expect(marks[0].at.y, closeTo(64 / 88, 1e-9));
      expect(marks[0].position, PpcPosition.efficient);
      expect(marks[1].position, PpcPosition.inside);
    });
  });

  group('formatPpcNumber', () {
    test('writes whole numbers without decimals', () {
      expect(formatPpcNumber(100), '100');
      expect(formatPpcNumber(96), '96');
    });

    test('keeps the decimals that are there', () {
      expect(formatPpcNumber(12.5), '12.5');
      expect(formatPpcNumber(1.234), '1.2');
      expect(formatPpcNumber(1.234, decimals: 2), '1.23');
      expect(formatPpcNumber(2, decimals: 2), '2');
    });
  });
}
