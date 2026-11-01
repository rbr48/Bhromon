import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _circle({String? kind, String? preset}) => {
      'name': 'Green Valley Block B',
      'ownerEmail': 'boss@example.com',
      'inviteCode': 'ABCDEFGH',
      if (kind != null) 'kind': kind,
      if (preset != null) 'preset': preset,
    };

void main() {
  group('housing society preset', () {
    test('a society is a family-style circle with the society preset', () {
      final society =
          TourGroup.fromMap('s1', _circle(kind: 'family', preset: 'society'));

      expect(society.isSociety, isTrue);
      expect(society.isSamity, isFalse);
      expect(society.isMess, isFalse);
      expect(society.isFamily, isTrue);
      expect(society.preset, 'society');
      expect(society.toMap()['preset'], 'society');
    });

    test(
        'the committee posts notices, and the society stays open to SOS and Moments',
        () {
      final society =
          TourGroup.fromMap('s1', _circle(kind: 'family', preset: 'society'));

      expect(society.hasManagedNotices, isTrue);
      expect(society.isManaged, isFalse);
      expect(society.momentsOpen, isTrue);
    });

    test('a society is not a household: no dependents, album or family dates',
        () {
      final society =
          TourGroup.fromMap('s1', _circle(kind: 'family', preset: 'society'));
      final household = TourGroup.fromMap('f1', _circle(kind: 'family'));
      final mess =
          TourGroup.fromMap('m1', _circle(kind: 'family', preset: 'mess'));

      expect(society.isHousehold, isFalse);
      expect(mess.isHousehold, isFalse);
      expect(household.isHousehold, isTrue);
    });

    test('a society offers its own upkeep categories, not the household ones',
        () {
      final society =
          TourGroup.fromMap('s1', _circle(kind: 'family', preset: 'society'));

      expect(expenseCategoriesForGroup(society), kSocietyExpenseCategories);
      expect(expenseCategoriesForGroup(society),
          containsAll(['Utilities', 'Security', 'Lift', 'Generator']));
      expect(expenseCategoriesForGroup(society), isNot(contains('Groceries')));
    });

    test(
        'the maintenance channel splits food under Repairs, with its own channels',
        () {
      expect(
        splitCategoryFor(family: true, channelId: 'food', society: true),
        'Repairs',
      );
      expect(
        splitCategoryFor(family: true, channelId: 'general', society: true),
        'Others',
      );
      expect(
        builtInChannelIdsFor(family: true, society: true),
        kSocietyChannelIds,
      );
      expect(kSocietyChannelIds, contains('food'));
      expect(kSocietyChannelIds, contains(kBuiltInVoiceChannelId));
    });

    test(
        'a plain family circle keeps its household tiles and its own categories',
        () {
      final family = TourGroup.fromMap('f1', _circle(kind: 'family'));

      expect(family.isHousehold, isTrue);
      expect(family.hasManagedNotices, isFalse);
      expect(
        expenseCategoriesForGroup(family),
        expenseCategoriesFor(family: true),
      );
    });

    test('a preset is read only when it is one of the known names', () {
      expect(TourGroup.presetFrom('society'), 'society');
      expect(TourGroup.presetFrom('samity'), 'samity');
      expect(TourGroup.presetFrom('Society'), isNull);

      final unknown =
          TourGroup.fromMap('s2', _circle(kind: 'family', preset: 'hostel'));
      expect(unknown.isSociety, isFalse);
      expect(unknown.preset, isNull);
    });
  });
}
