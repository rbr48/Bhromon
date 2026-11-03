import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/widgets/swipe_step.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox.expand(child: child)),
  );
}

void main() {
  testWidgets(
      'a flick to the left steps to the next item, and right to the previous',
      (tester) async {
    final steps = <int>[];
    await tester.pumpWidget(_wrap(SwipeStep(
      onStep: steps.add,
      child: const ColoredBox(key: ValueKey('body'), color: Colors.white),
    )));

    await tester.fling(
        find.byKey(const ValueKey('body')), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.fling(
        find.byKey(const ValueKey('body')), const Offset(300, 0), 1000);
    await tester.pump();

    expect(steps, [1, -1]);
  });

  testWidgets('a short, slow movement steps nothing', (tester) async {
    final steps = <int>[];
    await tester.pumpWidget(_wrap(SwipeStep(
      onStep: steps.add,
      child: const ColoredBox(key: ValueKey('body'), color: Colors.white),
    )));

    await tester.drag(find.byKey(const ValueKey('body')), const Offset(-20, 0));
    await tester.pump();

    expect(steps, isEmpty);
  });

  testWidgets('a drag that starts in an edge zone is left to the system',
      (tester) async {
    final steps = <int>[];
    await tester.pumpWidget(_wrap(SwipeStep(
      onStep: steps.add,
      child: const ColoredBox(key: ValueKey('body'), color: Colors.white),
    )));

    final gesture = await tester.startGesture(const Offset(10, 300));
    await tester.pump();
    await gesture.moveBy(const Offset(-400, 0));
    await gesture.up();
    await tester.pump();

    expect(steps, isEmpty);
  });

  testWidgets('a disabled step ignores flicks', (tester) async {
    final steps = <int>[];
    await tester.pumpWidget(_wrap(SwipeStep(
      enabled: false,
      onStep: steps.add,
      child: const ColoredBox(key: ValueKey('body'), color: Colors.white),
    )));

    await tester.fling(
        find.byKey(const ValueKey('body')), const Offset(-300, 0), 1000);
    await tester.pump();

    expect(steps, isEmpty);
  });

  testWidgets('a vertical scroll of the child scrolls it and steps nothing',
      (tester) async {
    final steps = <int>[];
    final controller = ScrollController();
    await tester.pumpWidget(_wrap(SwipeStep(
      onStep: steps.add,
      child: ListView.builder(
        controller: controller,
        itemCount: 60,
        itemBuilder: (context, i) =>
            SizedBox(height: 80, child: Text('row $i')),
      ),
    )));

    await tester.fling(find.byType(ListView), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    expect(steps, isEmpty);
  });

  testWidgets('screen reader actions step one item at a time', (tester) async {
    final handle = tester.ensureSemantics();
    final steps = <int>[];
    await tester.pumpWidget(_wrap(SwipeStep(
      onStep: steps.add,
      nextLabel: 'Next day',
      previousLabel: 'Previous day',
      child: const ColoredBox(color: Colors.white),
    )));

    final node = tester.getSemantics(find.byType(SwipeStep));
    final ids =
        node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
    final labels = [
      for (final id in ids) CustomSemanticsAction.getAction(id)?.label
    ];
    expect(labels, containsAll(['Previous day', 'Next day']));

    final next = ids.singleWhere(
        (id) => CustomSemanticsAction.getAction(id)?.label == 'Next day');
    node.owner!.performAction(node.id, SemanticsAction.customAction, next);
    await tester.pump();
    expect(steps, [1]);

    handle.dispose();
  });
}
