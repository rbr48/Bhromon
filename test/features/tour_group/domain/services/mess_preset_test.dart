import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _circle({String? kind, String? preset}) => {
      'name': 'Block B mess',
      'ownerEmail': 'boss@example.com',
      'inviteCode': 'ABCDEFGH',
      if (kind != null) 'kind': kind,
      if (preset != null) 'preset': preset,
    };

void main() {
  group('mess and shared home preset', () {
    test('a mess is a family-style circle with the mess preset', () {
      final mess =
          TourGroup.fromMap('m1', _circle(kind: 'family', preset: 'mess'));

      expect(mess.isMess, isTrue);
      expect(mess.isFamily, isTrue);
      expect(mess.isOffice, isFalse);
      expect(mess.isCampus, isFalse);
      expect(mess.preset, 'mess');
      expect(mess.toMap()['preset'], 'mess');
    });

    test('a mess is not a workspace, but its owner and admins post notices',
        () {
      final mess =
          TourGroup.fromMap('m1', _circle(kind: 'family', preset: 'mess'));
      final family = TourGroup.fromMap('g2', _circle(kind: 'family'));
      final office =
          TourGroup.fromMap('o1', _circle(kind: 'family', preset: 'office'));

      expect(mess.isManaged, isFalse);
      expect(mess.hasManagedNotices, isTrue);
      expect(office.hasManagedNotices, isTrue);
      expect(family.isManaged, isFalse);
      expect(family.hasManagedNotices, isFalse);
    });

    test('a mess offers its own categories: bazar, bills and rent', () {
      final mess =
          TourGroup.fromMap('m1', _circle(kind: 'family', preset: 'mess'));

      expect(expenseCategoriesForGroup(mess), kMessExpenseCategories);
      expect(expenseCategoriesForGroup(mess), contains('Groceries'));
      expect(expenseCategoriesForGroup(mess), contains('Utilities'));
      expect(expenseCategoriesForGroup(mess), isNot(contains('Dining')));
    });

    test('a mess splits food under Groceries and has its own channels', () {
      expect(
        splitCategoryFor(family: true, channelId: 'food', mess: true),
        'Groceries',
      );
      expect(
        builtInChannelIdsFor(family: true, mess: true),
        kMessChannelIds,
      );
      expect(kMessChannelIds, contains('food'));
      expect(kMessChannelIds, contains(kBuiltInVoiceChannelId));
    });

    test(
        'an unknown preset is kept, so the group is neither a mess nor a household',
        () {
      final group =
          TourGroup.fromMap('m2', _circle(kind: 'family', preset: 'hostel'));

      expect(group.isMess, isFalse);
      expect(group.preset, 'hostel');
      expect(group.isHousehold, isFalse);
    });
  });
}
