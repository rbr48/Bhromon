import 'package:bhromon/features/tour_group/data/group_stream_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(GroupStreamBudget.reset);

  test('open and close count the held upstreams for each key', () {
    final t1 = GroupStreamBudget.membersKey('t1');
    final t2 = GroupStreamBudget.membersKey('t2');

    GroupStreamBudget.open(GroupStreamBudget.myGroups);
    GroupStreamBudget.open(t1);
    GroupStreamBudget.open(t2);
    expect(GroupStreamBudget.live, 3);
    expect(GroupStreamBudget.opened, 3);

    GroupStreamBudget.close(t1);
    expect(GroupStreamBudget.liveOf(t1), 0);
    expect(GroupStreamBudget.live, 2);
    expect(GroupStreamBudget.opened, 3,
        reason: 'closing an upstream does not count as an open');
  });

  test('a second upstream under one key trips the debug assert', () {
    GroupStreamBudget.open(GroupStreamBudget.myGroups);

    expect(
      () => GroupStreamBudget.open(GroupStreamBudget.myGroups),
      throwsA(isA<AssertionError>()),
    );
  });

  test('a member stream of one tour does not count against another tour', () {
    GroupStreamBudget.open(GroupStreamBudget.membersKey('t1'));
    GroupStreamBudget.open(GroupStreamBudget.membersKey('t2'));

    expect(GroupStreamBudget.liveOf(GroupStreamBudget.membersKey('t1')), 1);
    expect(GroupStreamBudget.liveOf(GroupStreamBudget.membersKey('t2')), 1);
  });

  test('closing a key that was never opened leaves the counts alone', () {
    GroupStreamBudget.close('never-opened');

    expect(GroupStreamBudget.live, 0);
    expect(GroupStreamBudget.liveOf('never-opened'), 0);
  });
}
