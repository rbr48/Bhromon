import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter_test/flutter_test.dart';

// The shared fund is opt-in per group type (TourGroup.hasFund). The rules
// (fundAllowedTour in firestore.rules) and the VPS (fund_policy.py) apply the
// same rule, so these cases are the app's side of that agreement.
TourGroup _group({GroupKind kind = GroupKind.tour, String? preset}) {
  return TourGroup(
    id: 'g',
    name: 'G',
    ownerEmail: 'a@b.c',
    inviteCode: 'ABCDEFGH',
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 11, 4),
    createdAt: DateTime(2026, 10, 1),
    kind: kind,
    preset: preset,
  );
}

void main() {
  group('TourGroup.hasFund', () {
    test('a trip and a household keep the fund', () {
      expect(_group().hasFund, isTrue, reason: 'a trip');
      expect(_group(kind: GroupKind.family).hasFund, isTrue,
          reason: 'a household');
    });

    test(
        'a mess, a housing society, a campus and the other funded circles keep it',
        () {
      for (final preset in [
        TourGroup.messPreset,
        TourGroup.societyPreset,
        TourGroup.campusPreset,
        TourGroup.schoolPreset,
        TourGroup.sportsPreset,
        TourGroup.committeePreset,
        TourGroup.friendsPreset,
      ]) {
        expect(_group(kind: GroupKind.family, preset: preset).hasFund, isTrue,
            reason: preset);
      }
    });

    test('an office, a samity and a study circle keep none', () {
      for (final preset in [
        TourGroup.officePreset,
        TourGroup.samityPreset,
        TourGroup.studyPreset,
      ]) {
        expect(_group(kind: GroupKind.family, preset: preset).hasFund, isFalse,
            reason: preset);
      }
    });

    test('a preset the app does not name keeps no fund until it is listed', () {
      expect(
        _group(kind: GroupKind.family, preset: 'something-new').hasFund,
        isFalse,
      );
    });
  });
}
