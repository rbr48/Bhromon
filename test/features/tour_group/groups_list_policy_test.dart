import 'package:bhromon/features/tour_group/domain/services/groups_list_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a memberships answer', () {
    test('an empty cache before the server speaks is not "no groups"', () {
      // The browser's data was cleared: the device remembers nothing.
      expect(
        showsMembershipAnswer(
            fromCache: true, empty: true, heardFromServer: false),
        isFalse,
      );
    });

    test('the server saying there are none is shown', () {
      expect(
        showsMembershipAnswer(
            fromCache: false, empty: true, heardFromServer: false),
        isTrue,
      );
    });

    test('cached groups are shown at once', () {
      expect(
        showsMembershipAnswer(
            fromCache: true, empty: false, heardFromServer: false),
        isTrue,
      );
    });

    test('an empty cache after the server spoke is shown (went offline)', () {
      expect(
        showsMembershipAnswer(
            fromCache: true, empty: true, heardFromServer: true),
        isTrue,
      );
    });
  });

  group('the account the list is bound to', () {
    test('an email that arrives after sign-in binds the list again', () {
      final early = groupsBindKey('u1', 'u1@bhromon.app');
      final late = groupsBindKey('u1', 'me@example.com');
      expect(early, isNot(late));
    });

    test('the same account and email is the same binding', () {
      expect(groupsBindKey('u1', 'me@example.com'),
          groupsBindKey('u1', 'me@example.com'));
      expect(groupsBindKey('u1', 'me@example.com'),
          isNot(groupsBindKey('u2', 'me@example.com')));
    });
  });

  group('a failed read', () {
    test('is tried again after 1, 2, 4, 8, 16 and then 30 seconds', () {
      expect(
        [for (var i = 0; i < 7; i++) groupsRetryDelay(i).inSeconds],
        [1, 2, 4, 8, 16, 30, 30],
      );
      expect(groupsRetryDelay(-1).inSeconds, 1);
    });

    test('is tried a fixed number of times, then reported', () {
      expect(retriesGroupsRead(0), isTrue);
      expect(retriesGroupsRead(kGroupsReadRetries - 1), isTrue);
      expect(retriesGroupsRead(kGroupsReadRetries), isFalse);
    });

    test('the wait for the server is bounded, for a phone that is offline', () {
      expect(kGroupsServerWait.inSeconds, inInclusiveRange(5, 15));
    });
  });
}
