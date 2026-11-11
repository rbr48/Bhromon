// The SOS button switches the alert only after a two-second hold. A short press shows a
// hint instead, and assistive technology can switch it at once.

import 'package:bhromon/features/tour_group/presentation/widgets/hold_to_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int toggles;
  late int hints;

  Widget host() {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: HoldToToggleButton(
              active: false,
              label: 'Turn on the alert',
              onToggle: () => toggles++,
              onTapHint: () => hints++,
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    toggles = 0;
    hints = 0;
  });

  testWidgets('a short tap switches nothing and shows the hint',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Turn on the alert'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(toggles, 0);
    expect(hints, 1);
  });

  testWidgets('holding for two seconds switches the alert once',
      (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Turn on the alert')),
    );
    // The hold starts on the first frame after the press, so one frame runs first.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    expect(toggles, 1);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(toggles, 1,
        reason: 'releasing after the switch does not switch again');
    expect(hints, 0, reason: 'a completed hold shows no hint');
  });

  testWidgets('releasing before two seconds switches nothing', (tester) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Turn on the alert')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 2500));

    expect(toggles, 0);
    expect(hints, 1);
  });

  testWidgets('a screen reader can switch it at once, without a hold',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host());

    tester.semantics.tap(find.semantics.byLabel('Turn on the alert'));
    await tester.pump();

    expect(toggles, 1);
    handle.dispose();
  });
}
