import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/ppc_chart_widget.dart';
import 'package:bhromon/features/tour_group/domain/services/ppc_curve.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _spec = PpcSpec(
  title: 'Frontier',
  xLabel: 'Food',
  yLabel: 'Cloth',
  xMax: 100,
  yMax: 80,
  points: [PpcPoint(label: 'A', x: 20, y: 70)],
);

Future<void> _pump(
  WidgetTester tester,
  PpcSpec spec, {
  String locale = 'en',
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: Locale(locale),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(width: 400, child: PpcChartWidget(spec: spec)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _drawing() => find
    .descendant(
      of: find.byType(PpcChartWidget),
      matching: find.byType(CustomPaint),
    )
    .first;

/// The top left of the drawing, in global coordinates.
Offset _canvasOrigin(WidgetTester tester) => tester.getTopLeft(_drawing());

/// The size the drawing was laid out at.
Size _drawingSize(WidgetTester tester) => tester.getSize(_drawing());

/// The drawing position of the data point (x, y), as the painter places it:
/// the plot is 44 to the right of the left edge, 26 down from the top, and
/// ends 14 short of the right edge and 32 short of the bottom.
Offset _pixelOf(double x, double y, PpcSpec spec, Size size) {
  const left = 44.0;
  const top = 26.0;
  final plotWidth = size.width - left - 14;
  final plotHeight = size.height - top - 32;
  return Offset(
    left + x / spec.axisMaxX * plotWidth,
    top + plotHeight - y / spec.axisMaxY * plotHeight,
  );
}

void main() {
  testWidgets('reads the point, its status, the most Y and the cost of X',
      (tester) async {
    await _pump(tester, _spec);

    expect(find.text('Frontier'), findsOneWidget);
    expect(
      find.text('Inefficient: inside the frontier, some resource is idle'),
      findsOneWidget,
    );
    expect(find.text('Your point: Food 20, Cloth 70'), findsOneWidget);
    expect(
      find.text('The most Cloth with this much Food: 78.4'),
      findsOneWidget,
    );
    expect(
      find.text('One more unit of Food costs 0.16 units of Cloth'),
      findsOneWidget,
    );
  });

  testWidgets('a tap on the frontier lands exactly on it', (tester) async {
    await _pump(tester, _spec);

    final origin = _canvasOrigin(tester);
    await tester.tapAt(origin + _pixelOf(60, 64, _spec, _drawingSize(tester)));
    await tester.pump();

    expect(
      find.text('Efficient: on the frontier, no resource is idle'),
      findsOneWidget,
    );
    expect(find.text('Your point: Food 60, Cloth 64'), findsOneWidget);
  });

  testWidgets('a tap beyond the frontier is unattainable', (tester) async {
    await _pump(tester, _spec);

    final origin = _canvasOrigin(tester);
    // Past the X intercept (100), so there is no frontier to read.
    await tester.tapAt(origin + _pixelOf(105, 80, _spec, _drawingSize(tester)));
    await tester.pump();

    expect(
      find.text('Unattainable: beyond the frontier with current resources'),
      findsOneWidget,
    );
    // Beyond the X intercept there is no most-Y reading to show.
    expect(find.textContaining('The most'), findsNothing);
  });

  testWidgets('a drag moves the point and the readings follow', (tester) async {
    await _pump(tester, _spec);
    final before = find.textContaining('Your point:');
    expect(before, findsOneWidget);

    await tester.drag(
      find
          .descendant(
            of: find.byType(PpcChartWidget),
            matching: find.byType(CustomPaint),
          )
          .first,
      const Offset(60, 0),
    );
    await tester.pump();

    expect(find.textContaining('Your point:'), findsOneWidget);
    expect(find.text('Your point: Food 20, Cloth 70'), findsNothing);
  });

  testWidgets('a chart with growth explains its two lines', (tester) async {
    await _pump(
      tester,
      const PpcSpec(xMax: 100, yMax: 80, growth: 1.2),
    );

    expect(find.textContaining('Frontier'), findsOneWidget);
    expect(find.textContaining('After growth'), findsOneWidget);
  });

  testWidgets('the Bengali reader shows Bengali status and digits',
      (tester) async {
    await _pump(
      tester,
      const PpcSpec(
        xLabel: 'কৃষি',
        yLabel: 'শিল্প',
        xMax: 100,
        yMax: 80,
        points: [PpcPoint(label: 'A', x: 60, y: 64)],
      ),
      locale: 'bn',
    );

    expect(
      find.text('দক্ষ: সীমার উপরে, কোনো সম্পদ অব্যবহৃত নেই'),
      findsOneWidget,
    );
    expect(find.text('আপনার বিন্দু: কৃষি ৬০, শিল্প ৬৪'), findsOneWidget);
  });
}
