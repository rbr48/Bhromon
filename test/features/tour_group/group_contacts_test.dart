import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/group_contacts.dart';

TourMember _member(
  String tourId,
  String email, {
  String? uid,
  String name = 'Member',
  TourMemberStatus status = TourMemberStatus.active,
}) {
  return TourMember(
    tourId: tourId,
    tourName: tourId,
    email: email,
    displayName: name,
    role: TourRole.member,
    status: status,
    joinedAt: DateTime(2026, 10, 1),
    uid: uid,
  );
}

void main() {
  const me = 'me@x.com';
  const myUid = 'uid-me';

  group('groupContacts', () {
    test('lists the members of my tours, and not me', () {
      final contacts = groupContacts(myUid: myUid, myEmail: me, tours: [
        (
          id: 'sajek',
          name: 'Sajek trip',
          members: [
            _member('sajek', me, uid: myUid, name: 'Me'),
            _member('sajek', 'rahim@x.com', uid: 'uid-rahim', name: 'Rahim'),
          ],
        ),
      ]);

      expect(contacts.map((c) => c.uid), ['uid-rahim']);
      expect(contacts.single.sharedTourId, 'sajek');
    });

    test('a person in two of my tours appears once, with both tours', () {
      final contacts = groupContacts(myUid: myUid, myEmail: me, tours: [
        (
          id: 'sajek',
          name: 'Sajek trip',
          members: [
            _member('sajek', 'rahim@x.com', uid: 'uid-rahim', name: 'Rahim')
          ],
        ),
        (
          id: 'family',
          name: 'Family',
          members: [
            _member('family', 'rahim@x.com', uid: 'uid-rahim', name: 'Rahim')
          ],
        ),
      ]);

      expect(contacts, hasLength(1));
      expect(contacts.single.tours.map((t) => t.id), ['sajek', 'family']);
    });

    test('invited members and people who never signed in are not listed', () {
      final contacts = groupContacts(myUid: myUid, myEmail: me, tours: [
        (
          id: 'sajek',
          name: 'Sajek trip',
          members: [
            _member('sajek', 'invited@x.com',
                uid: 'uid-invited', status: TourMemberStatus.invited),
            _member('sajek', 'nouid@x.com'),
          ],
        ),
      ]);

      expect(contacts, isEmpty);
    });

    test('someone outside my tours is never listed', () {
      final contacts =
          groupContacts(myUid: myUid, myEmail: me, tours: const []);
      expect(contacts, isEmpty);
    });

    test('contacts are sorted by name, and a blank name reads as Traveler', () {
      final contacts = groupContacts(myUid: myUid, myEmail: me, tours: [
        (
          id: 'sajek',
          name: 'Sajek trip',
          members: [
            _member('sajek', 'zed@x.com', uid: 'uid-zed', name: 'Zed'),
            _member('sajek', 'ann@x.com', uid: 'uid-ann', name: 'ann'),
            _member('sajek', 'blank@x.com', uid: 'uid-blank', name: '  '),
          ],
        ),
      ]);

      expect(contacts.map((c) => c.name), ['ann', 'Traveler', 'Zed']);
    });
  });

  group('isInMyTours', () {
    test('a chat or call in one of my tours counts', () {
      expect(isInMyTours({'sharedTourId': 'sajek'}, {'sajek'}), isTrue);
    });

    test('a chat from another tour, or from before tours, does not', () {
      expect(isInMyTours({'sharedTourId': 'other'}, {'sajek'}), isFalse);
      expect(
          isInMyTours({
            'participants': ['a', 'b']
          }, {
            'sajek'
          }),
          isFalse);
      expect(isInMyTours(null, {'sajek'}), isFalse);
    });

    test('the AI Guide chat is the user\'s own, so it counts', () {
      expect(
          isInMyTours({
            'participants': ['a', 'bhromon_ai_advisor']
          }, {
            'sajek'
          }),
          isTrue);
    });
  });
}
