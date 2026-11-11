// Which groups have the SOS feature. Only a trip, a household, a mess and a housing
// society have it. The rules and the VPS apply the same rule, so these cases are the
// contract for all three.

import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/hub_modules.dart';
import 'package:flutter_test/flutter_test.dart';

TourGroup _group({bool family = false, String? preset}) {
  return TourGroup(
    id: 'g',
    name: 'G',
    ownerEmail: 'a@b.c',
    inviteCode: 'ABCDEFGH',
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 11, 4),
    createdAt: DateTime(2026, 10, 1),
    kind: family ? GroupKind.family : GroupKind.tour,
    preset: preset,
  );
}

Map<String, dynamic> _map({String? preset}) => {
      'name': 'G',
      'ownerEmail': 'a@b.c',
      'inviteCode': 'ABCDEFGH',
      'kind': 'family',
      'preset': preset,
      'startDate': DateTime(2026, 11, 1),
      'endDate': DateTime(2026, 11, 4),
      'createdAt': DateTime(2026, 10, 1),
    };

const _allowed = [
  TourGroup.messPreset,
  TourGroup.societyPreset,
];

const _denied = [
  TourGroup.officePreset,
  TourGroup.campusPreset,
  TourGroup.samityPreset,
  TourGroup.studyPreset,
  TourGroup.committeePreset,
  TourGroup.schoolPreset,
  TourGroup.sportsPreset,
  TourGroup.friendsPreset,
];

void main() {
  group('supportsSafetyAlerts', () {
    test('a trip has SOS', () {
      expect(_group().supportsSafetyAlerts, isTrue);
    });

    test('a household (a plain family circle) has SOS', () {
      expect(_group(family: true).supportsSafetyAlerts, isTrue);
    });

    for (final preset in _allowed) {
      test('a group with the "$preset" preset has SOS', () {
        expect(
            _group(family: true, preset: preset).supportsSafetyAlerts, isTrue);
      });
    }

    for (final preset in _denied) {
      test('a group with the "$preset" preset has no SOS', () {
        expect(
            _group(family: true, preset: preset).supportsSafetyAlerts, isFalse);
      });
    }

    test('an unknown preset has no SOS, as the rules say', () {
      expect(
        _group(family: true, preset: 'something-new').supportsSafetyAlerts,
        isFalse,
      );
    });

    test(
        'a stored unknown preset is kept, so the group is not read as a household',
        () {
      final group = TourGroup.fromMap('g', _map(preset: 'something-new'));
      expect(group.preset, 'something-new');
      expect(group.isHousehold, isFalse);
      expect(group.supportsSafetyAlerts, isFalse);
    });

    test('a stored preset with the wrong case is not read as allowed', () {
      final group = TourGroup.fromMap('g', _map(preset: 'Society'));
      expect(group.supportsSafetyAlerts, isFalse);
    });

    test('a stored household (no preset) reads as allowed', () {
      final group = TourGroup.fromMap('g', _map());
      expect(group.preset, isNull);
      expect(group.supportsSafetyAlerts, isTrue);
    });
  });

  group('the Family Safety hub tile follows the same rule', () {
    test('the tile is listed for a trip, a household, a mess and a society',
        () {
      expect(hubModulesFor(_group()), contains('safety'));
      expect(hubModulesFor(_group(family: true)), contains('safety'));
      for (final preset in _allowed) {
        expect(hubModulesFor(_group(family: true, preset: preset)),
            contains('safety'));
      }
    });

    for (final preset in _denied) {
      test('the tile is not listed for the "$preset" preset', () {
        expect(
          hubModulesFor(_group(family: true, preset: preset)),
          isNot(contains('safety')),
        );
      });
    }
  });
}
