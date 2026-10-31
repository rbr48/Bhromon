import 'package:bhromon/features/tour_group/domain/services/call_partner.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(
        {String status = 'active', String? uid = 'bob-uid'}) =>
    {
      'status': status,
      if (uid != null) 'uid': uid,
    };

void main() {
  group('callPartnerStatusFor', () {
    test('two active members, with the partner linked, can call', () {
      expect(
        callPartnerStatusFor(
          myRow: _row(uid: 'ann-uid'),
          partnerRow: _row(),
          partnerUid: 'bob-uid',
        ),
        CallPartnerStatus.ready,
      );
    });

    test('a missing row of the signed-in person means they have left', () {
      expect(
        callPartnerStatusFor(
          myRow: null,
          partnerRow: _row(),
          partnerUid: 'bob-uid',
        ),
        CallPartnerStatus.youLeft,
      );
    });

    test('an inactive row of the signed-in person means they have left', () {
      expect(
        callPartnerStatusFor(
          myRow: _row(status: 'removed', uid: 'ann-uid'),
          partnerRow: _row(),
          partnerUid: 'bob-uid',
        ),
        CallPartnerStatus.youLeft,
      );
    });

    test('a partner with no row is no longer in the tour', () {
      expect(
        callPartnerStatusFor(
          myRow: _row(uid: 'ann-uid'),
          partnerRow: null,
          partnerUid: 'bob-uid',
        ),
        CallPartnerStatus.partnerLeft,
      );
    });

    test('an inactive partner row counts as the partner having left', () {
      expect(
        callPartnerStatusFor(
          myRow: _row(uid: 'ann-uid'),
          partnerRow: _row(status: 'left'),
          partnerUid: 'bob-uid',
        ),
        CallPartnerStatus.partnerLeft,
      );
    });

    test('a partner row with no uid has not been linked yet', () {
      expect(
        callPartnerStatusFor(
          myRow: _row(uid: 'ann-uid'),
          partnerRow: _row(uid: null),
          partnerUid: 'bob-uid',
        ),
        CallPartnerStatus.partnerNotLinked,
      );
    });

    test('a partner row linked to another account is not that partner', () {
      expect(
        callPartnerStatusFor(
          myRow: _row(uid: 'ann-uid'),
          partnerRow: _row(uid: 'someone-else'),
          partnerUid: 'bob-uid',
        ),
        CallPartnerStatus.partnerNotLinked,
      );
    });
  });
}
