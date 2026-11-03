import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/widgets/swipe_pager.dart';

/// Hosts a [SwipePager] the way a screen does: it keeps the selection, and
/// takes a settled swipe as the new selection.
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.settled,
    this.count = 4,
    this.initial = 0,
    this.enabled = true,
    this.labels = false,
  });

  final List<int> settled;
  final int count;
  final int initial;
  final bool enabled;
  final bool labels;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  // Starts at page 0 on purpose, so a selection that is not 0 must be applied
  // by the pager itself.
  final PageController controller = PageController();
  late int selected = widget.initial;
  late int count = widget.count;

  void select(int index) => setState(() => selected = index);

  void setCount(int value) => setState(() => count = value);

  @override
  Widget build(BuildContext context) {
    return SwipePager(
      controller: controller,
      count: count,
      selectedIndex: selected,
      enabled: widget.enabled,
      nextLabel: widget.labels ? 'Next page' : null,
      previousLabel: widget.labels ? 'Previous page' : null,
      itemBuilder: (context, i) => ColoredBox(
        color: Colors.white,
        child: Center(child: Text('page $i')),
      ),
      onSettled: (i) {
        widget.settled.add(i);
        setState(() => selected = i);
      },
    );
  }
}

Widget _wrap(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: SizedBox.expand(child: child)),
    ),
  );
}

/// Performs the custom semantics action with [label] on the pager's node.
void _performCustom(WidgetTester tester, String label) {
  final node = tester.getSemantics(find.byType(SwipePager));
  final id = node.getSemanticsData().customSemanticsActionIds!.singleWhere(
        (id) => CustomSemanticsAction.getAction(id)?.label == label,
      );
  node.owner!.performAction(node.id, SemanticsAction.customAction, id);
}

List<String> _customLabels(WidgetTester tester) {
  final ids = tester
          .getSemantics(find.byType(SwipePager))
          .getSemanticsData()
          .customSemanticsActionIds ??
      const <int>[];
  return [
    for (final id in ids) CustomSemanticsAction.getAction(id)?.label ?? '',
  ];
}

void main() {
  final settled = <int>[];

  setUp(settled.clear);

  testWidgets('changes page only once the swipe has come to rest',
      (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_wrap(_Host(key: key, settled: settled)));

    final gesture = await tester.startGesture(const Offset(650, 300));
    await gesture.moveBy(const Offset(-500, 0));
    await tester.pump();
    expect(settled, isEmpty, reason: 'nothing commits midway through a drag');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(settled, [1]);
    expect(key.currentState!.selected, 1);
    expect(key.currentState!.controller.page, 1);
  });

  testWidgets('a short swipe snaps back and changes nothing', (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_wrap(_Host(key: key, settled: settled)));

    await tester.drag(find.byType(PageView), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(settled, isEmpty);
    expect(key.currentState!.selected, 0);
    expect(key.currentState!.controller.page, 0);
  });

  testWidgets('the ends clamp: no swipe past the first or last page',
      (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_wrap(_Host(key: key, settled: settled)));

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(settled, isEmpty);

    key.currentState!.select(3);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(settled, isEmpty);
    expect(key.currentState!.controller.page, 3);
  });

  testWidgets('moves to a page selected elsewhere without reporting it',
      (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_wrap(_Host(key: key, settled: settled)));

    key.currentState!.select(2);
    await tester.pumpAndSettle();

    expect(key.currentState!.controller.page, 2);
    expect(settled, isEmpty);
  });

  testWidgets('reduced motion jumps to a page selected elsewhere',
      (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _wrap(_Host(key: key, settled: settled), reduceMotion: true),
    );

    key.currentState!.select(3);
    await tester.pump();

    expect(key.currentState!.controller.page, 3);
    expect(settled, isEmpty);
  });

  testWidgets('places the first build on the selected page', (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _wrap(_Host(key: key, settled: settled, initial: 2)),
    );
    await tester.pumpAndSettle();

    expect(key.currentState!.controller.page, 2);
    expect(settled, isEmpty);
  });

  testWidgets('places the pager when the list arrives after the first frame',
      (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _wrap(_Host(key: key, settled: settled, count: 0, initial: 0)),
    );

    key.currentState!.setCount(4);
    key.currentState!.select(2);
    await tester.pumpAndSettle();

    expect(key.currentState!.controller.page, 2);
    expect(settled, isEmpty);
  });

  testWidgets('a swipe that starts in the left edge zone is left to the system',
      (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_wrap(_Host(key: key, settled: settled)));

    // A frame runs between the pointer going down and moving, as on a phone.
    final gesture = await tester.startGesture(const Offset(10, 300));
    await tester.pump();
    await gesture.moveBy(const Offset(-500, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(settled, isEmpty);
    expect(key.currentState!.controller.page, 0);
  });

  testWidgets(
      'a swipe that starts in the right edge zone is left to the system',
      (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_wrap(_Host(key: key, settled: settled)));
    key.currentState!.select(1);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(790, 300));
    await tester.pump();
    await gesture.moveBy(const Offset(-500, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(settled, isEmpty);
    expect(key.currentState!.controller.page, 1);
  });

  testWidgets('a disabled pager keeps its page and ignores swipes',
      (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _wrap(_Host(key: key, settled: settled, enabled: false)),
    );

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(settled, isEmpty);
    expect(key.currentState!.controller.page, 0);
  });

  testWidgets('screen reader actions step one page and stop at the ends',
      (tester) async {
    final handle = tester.ensureSemantics();
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _wrap(_Host(key: key, settled: settled, labels: true)),
    );

    expect(_customLabels(tester), containsAll(['Previous page', 'Next page']));

    _performCustom(tester, 'Previous page');
    await tester.pumpAndSettle();
    expect(settled, isEmpty, reason: 'there is no page before the first');

    _performCustom(tester, 'Next page');
    await tester.pumpAndSettle();
    expect(settled, [1]);
    expect(key.currentState!.controller.page, 1);

    key.currentState!.select(3);
    await tester.pumpAndSettle();
    _performCustom(tester, 'Next page');
    await tester.pumpAndSettle();
    expect(settled, [1], reason: 'the last page does not step further');

    handle.dispose();
  });

  testWidgets('no screen reader actions without labels, or while disabled',
      (tester) async {
    final handle = tester.ensureSemantics();
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_wrap(_Host(key: key, settled: settled)));
    expect(_customLabels(tester), isEmpty);

    await tester.pumpWidget(
      _wrap(_Host(key: key, settled: settled, labels: true, enabled: false)),
    );
    expect(_customLabels(tester), isEmpty);

    handle.dispose();
  });

  test('a page window keeps the selected page and one page either side', () {
    expect(isWithinPageWindow(2, 2), isTrue);
    expect(isWithinPageWindow(1, 2), isTrue);
    expect(isWithinPageWindow(3, 2), isTrue);
    expect(isWithinPageWindow(0, 2), isFalse);
    expect(isWithinPageWindow(4, 2), isFalse);
    expect(isWithinPageWindow(0, 2, radius: 2), isTrue);
  });
}
