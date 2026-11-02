import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/explorer/domain/profile_view.dart';

void main() {
  group('profileHandle', () {
    test('uses the part of the email before the @', () {
      expect(profileHandle(email: 'rishatul.f@gmail.com', displayName: 'X'),
          'rishatul.f');
    });

    test('falls back to the name when the email is not known', () {
      expect(profileHandle(email: '', displayName: 'Rishatul Ferdaus'),
          'rishatul_ferdaus');
    });

    test('drops characters a handle cannot hold', () {
      expect(profileHandle(email: '', displayName: 'রিশাতুল'), 'member');
      expect(profileHandle(email: 'a+b@x.com', displayName: ''), 'ab');
    });
  });

  group('profileGroups', () {
    const mine = ['g1', 'g2', 'g3'];
    String id(String g) => g;

    test('your own profile lists all your groups', () {
      expect(
        profileGroups(
            isOwnProfile: true, myGroups: mine, sharedIds: null, idOf: id),
        mine,
      );
    });

    test("someone else's profile lists only shared groups", () {
      expect(
        profileGroups(
            isOwnProfile: false,
            myGroups: mine,
            sharedIds: {'g2', 'other'},
            idOf: id),
        ['g2'],
      );
    });

    test("someone else's profile lists nothing until shared groups are known",
        () {
      expect(
        profileGroups(
            isOwnProfile: false, myGroups: mine, sharedIds: null, idOf: id),
        isEmpty,
      );
    });
  });
}
