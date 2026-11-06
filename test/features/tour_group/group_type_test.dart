import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TourGroup _group({bool family = false, String? preset}) => TourGroup(
      id: 'g',
      name: 'Group',
      ownerEmail: 'tester@bhromon.fun',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      createdAt: DateTime(2026, 10, 1),
      kind: family ? GroupKind.family : GroupKind.tour,
      preset: preset,
    );

/// Every preset is stored as a family-kind circle, which is why the type cannot be
/// read from the kind alone.
const _presets = [
  TourGroup.friendsPreset,
  TourGroup.officePreset,
  TourGroup.campusPreset,
  TourGroup.messPreset,
  TourGroup.societyPreset,
  TourGroup.samityPreset,
  TourGroup.schoolPreset,
  TourGroup.sportsPreset,
  TourGroup.studyPreset,
  TourGroup.committeePreset,
];

void main() {
  group('groupTypeKey', () {
    test('a friends group is named as friends, not as a family', () {
      final friends = _group(family: true, preset: TourGroup.friendsPreset);
      expect(groupTypeKey(friends), 'hub_friends_badge');
    });

    test('a housing society is named as a society, not as a family', () {
      final society = _group(family: true, preset: TourGroup.societyPreset);
      expect(groupTypeKey(society), 'hub_society_badge');
    });

    test('a sports team or gym is named for both', () {
      final gym = _group(family: true, preset: TourGroup.sportsPreset);
      expect(groupTypeKey(gym), 'hub_sports_badge');
    });

    test('every preset has a name of its own', () {
      final keys = {
        for (final p in _presets) groupTypeKey(_group(family: true, preset: p)),
      };
      expect(keys, hasLength(_presets.length));
      expect(keys, isNot(contains('hub_section_family')));
    });

    test('a plain family circle keeps the family name', () {
      expect(groupTypeKey(_group(family: true)), 'hub_section_family');
    });

    test('a trip keeps the trip name', () {
      expect(groupTypeKey(_group()), 'hub_section_trips');
    });
  });

  group('groupTypeIcon', () {
    test('a friends group shows people_alt icon', () {
      final friends = _group(family: true, preset: TourGroup.friendsPreset);
      expect(groupTypeIcon(friends), Icons.people_alt_rounded);
    });

    test('a housing society shows an apartment, not the family icon', () {
      final society = _group(family: true, preset: TourGroup.societyPreset);
      expect(groupTypeIcon(society), Icons.apartment_rounded);
    });

    test('every preset has an icon of its own', () {
      final icons = {
        for (final p in _presets)
          groupTypeIcon(_group(family: true, preset: p)),
      };
      expect(icons, hasLength(_presets.length));
      expect(icons, isNot(contains(Icons.family_restroom_rounded)));
      expect(icons, isNot(contains(Icons.card_travel_rounded)));
    });

    test('a plain family circle and a trip keep their icons', () {
      expect(
          groupTypeIcon(_group(family: true)), Icons.family_restroom_rounded);
      expect(groupTypeIcon(_group()), Icons.card_travel_rounded);
    });
  });
}
