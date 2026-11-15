import 'package:bhromon/core/layout/app_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(body: child),
    );

Future<void> _mouseDrag(WidgetTester tester, Offset from, Offset by) async {
  final gesture =
      await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await gesture.moveBy(by);
  await gesture.moveBy(by);
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('a mouse drags a sideways strip', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(SizedBox(
      height: 60,
      child: ListView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(width: 100, child: Text('chip $i')),
        ],
      ),
    )));

    await _mouseDrag(tester, const Offset(400, 30), const Offset(-60, 0));
    expect(controller.offset, 120);

    // It stops at the ends.
    await _mouseDrag(tester, const Offset(400, 30), const Offset(900, 0));
    expect(controller.offset, 0);
  });

  testWidgets('a mouse drag does not move a list that scrolls up and down',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(ListView(
      controller: controller,
      children: [
        for (var i = 0; i < 80; i++)
          SizedBox(height: 50, child: Text('row $i')),
      ],
    )));

    await _mouseDrag(tester, const Offset(400, 300), const Offset(0, -80));
    expect(controller.offset, 0);
  });

  testWidgets('a mouse drag does not turn a page', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(PageView(
      controller: controller,
      children: const [Text('one'), Text('two'), Text('three')],
    )));

    await _mouseDrag(tester, const Offset(400, 300), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('a tap on a chip still works after the strip was dragged',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(
              width: 100,
              child: TextButton(
                onPressed: () => taps++,
                child: Text('chip $i'),
              ),
            ),
        ],
      ),
    )));

    await _mouseDrag(tester, const Offset(400, 30), const Offset(-60, 0));
    expect(taps, 0, reason: 'a drag is not a tap');

    await tester.tap(find.text('chip 3'));
    expect(taps, 1);
  });
}
