import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/widgets/adaptive_columns.dart';

Future<void> _pump(WidgetTester tester, double width, int count) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: AdaptiveColumns(
              spacing: 10,
              children: [
                for (var i = 0; i < count; i++)
                  SizedBox(
                      key: ValueKey(i), height: 40, child: Text('card $i')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a phone width stacks the cards in one column', (tester) async {
    await _pump(tester, 400, 3);

    final first = tester.getRect(find.byKey(const ValueKey(0)));
    final second = tester.getRect(find.byKey(const ValueKey(1)));
    expect(first.width, 400);
    expect(second.top, first.bottom + 10);
    expect(second.left, first.left);
  });

  testWidgets('a tablet width puts the cards side by side in pairs',
      (tester) async {
    await _pump(tester, 700, 4);

    final first = tester.getRect(find.byKey(const ValueKey(0)));
    final second = tester.getRect(find.byKey(const ValueKey(1)));
    final third = tester.getRect(find.byKey(const ValueKey(2)));
    expect(first.width, 345);
    expect(second.top, first.top);
    expect(second.left, first.right + 10);
    expect(third.top, first.bottom + 10);
    expect(third.left, first.left);
  });

  testWidgets('an odd last card keeps half the row', (tester) async {
    await _pump(tester, 700, 3);

    final last = tester.getRect(find.byKey(const ValueKey(2)));
    expect(last.width, 345);
    expect(last.left, 0);
  });
}
