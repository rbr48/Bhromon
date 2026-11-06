import 'package:bhromon/core/localization/tour_translation_keys.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

TourGroup _circle(String preset) => TourGroup.fromMap('g1', {
      'name': 'Group',
      'ownerEmail': 'owner@example.com',
      'inviteCode': 'ABCDEFGH',
      'kind': 'family',
      'preset': preset,
    });

void main() {
  final en = TourTranslationKeys.localizedValues['en']!;
  final bn = TourTranslationKeys.localizedValues['bn']!;

  group('friends, school, sports, study and committee groups', () {
    test('each type is recognised by its own preset', () {
      expect(_circle('friends').isFriends, isTrue);
      expect(_circle('school').isSchool, isTrue);
      expect(_circle('sports').isSports, isTrue);
      expect(_circle('study').isStudy, isTrue);
      expect(_circle('committee').isCommittee, isTrue);
    });

    test('each type starts with the shared channel set, not the family one',
        () {
      final familyChannels = builtInChannelIdsFor(family: true);
      final perType = {
        'friends': builtInChannelIdsFor(family: true, friends: true),
        'school': builtInChannelIdsFor(family: true, school: true),
        'sports': builtInChannelIdsFor(family: true, sports: true),
        'study': builtInChannelIdsFor(family: true, study: true),
        'committee': builtInChannelIdsFor(family: true, committee: true),
      };
      for (final entry in perType.entries) {
        expect(entry.value, containsAll(['general', 'food', 'sightseeing']),
            reason: entry.key);
        expect(entry.value, contains(kBuiltInVoiceChannelId),
            reason: entry.key);
        expect(entry.value, isNot(equals(familyChannels)), reason: entry.key);
      }
    });

    test('each type offers its own ledger categories, and not the family list',
        () {
      expect(expenseCategoriesForGroup(_circle('friends')),
          kFriendsExpenseCategories);
      expect(expenseCategoriesForGroup(_circle('school')),
          kSchoolExpenseCategories);
      expect(expenseCategoriesForGroup(_circle('sports')),
          kSportsExpenseCategories);
      expect(
          expenseCategoriesForGroup(_circle('study')), kStudyExpenseCategories);
      expect(expenseCategoriesForGroup(_circle('committee')),
          kCommitteeExpenseCategories);
      expect(kSchoolExpenseCategories,
          isNot(equals(expenseCategoriesFor(family: true))));
    });

    test('every category offered has a label in both languages', () {
      final lists = [
        kFriendsExpenseCategories,
        kSchoolExpenseCategories,
        kSportsExpenseCategories,
        kStudyExpenseCategories,
        kCommitteeExpenseCategories,
      ];
      for (final list in lists) {
        expect(list, contains('Others'));
        expect(list.toSet().length, list.length, reason: 'duplicate in $list');
        for (final category in list) {
          final key = 'fund_cat_${category.toLowerCase()}';
          expect(en.containsKey(key), isTrue, reason: 'no English for $key');
          expect(bn.containsKey(key), isTrue, reason: 'no Bengali for $key');
        }
      }
    });

    test(
        'a chat split in the food channel books under a category the type offers',
        () {
      expect(
          kFriendsExpenseCategories,
          contains(splitCategoryFor(
              family: true, channelId: 'food', friends: true)));
      expect(
          kSchoolExpenseCategories,
          contains(
              splitCategoryFor(family: true, channelId: 'food', school: true)));
      expect(
          kSportsExpenseCategories,
          contains(
              splitCategoryFor(family: true, channelId: 'food', sports: true)));
      expect(
          kStudyExpenseCategories,
          contains(
              splitCategoryFor(family: true, channelId: 'food', study: true)));
      expect(
          kCommitteeExpenseCategories,
          contains(splitCategoryFor(
              family: true, channelId: 'food', committee: true)));
    });
  });
}
