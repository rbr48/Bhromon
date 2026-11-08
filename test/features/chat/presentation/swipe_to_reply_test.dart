import 'package:bhromon/features/chat/presentation/widgets/swipe_to_reply.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The swipe gesture of a message bubble. A chat that does not offer replies, such as an
// encrypted chat (E2EE_DESIGN.md, section 11, M4 item 7), turns it off.

void main() {
  Future<int> swipeRight(WidgetTester tester, {required bool enabled}) async {
    var replies = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SwipeToReply(
          enabled: enabled,
          onReply: () => replies++,
          // A coloured box takes the touch, as a message bubble does. A bare SizedBox
          // would not, and the drag would never start.
          child: Container(
            key: const Key('bubble'),
            width: 300,
            height: 60,
            color: Colors.grey,
          ),
        ),
      ),
    ));
    // A finger moves in small steps, and the widget ignores a single step that would
    // pass its maximum drag, so the swipe is sent the same way.
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const Key('bubble'))));
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    return replies;
  }

  testWidgets('a swipe past the threshold replies', (tester) async {
    expect(await swipeRight(tester, enabled: true), 1);
  });

  testWidgets('a disabled swipe does nothing', (tester) async {
    expect(await swipeRight(tester, enabled: false), 0);
  });
}
