import 'package:bhromon/core/localization/tour_translation_keys.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:bhromon/features/tour_group/domain/services/notice_engine.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_ledger_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _members = [
  LedgerMemberInput(id: 'a@x.com', name: 'Asha', familyCount: 2),
  LedgerMemberInput(id: 'b@x.com', name: 'Babu'),
];

ExpenseItem _exp(String id, int taka, String category) => ExpenseItem(
      id: id,
      tourId: 'f',
      title: id,
      amountPaisa: taka * 100,
      paidById: 'a@x.com',
      paidByName: 'Asha',
      category: category,
      date: DateTime(2026, 10, 30),
      splitMode: SplitMode.family,
    );

void main() {
  final en = TourTranslationKeys.localizedValues['en']!;
  final bn = TourTranslationKeys.localizedValues['bn']!;

  group('expense categories', () {
    test('a family circle offers household categories, not trip ones', () {
      final family = expenseCategoriesFor(family: true);
      expect(family.first, 'Groceries');
      expect(family, containsAll(['Utilities', 'Rent', 'School', 'Medical']));
      for (final tripOnly in [
        'Hotel',
        'Guide',
        'Tips',
        'Tickets',
        'Activities'
      ]) {
        expect(family, isNot(contains(tripOnly)), reason: tripOnly);
      }
    });

    test('a trip keeps its own list, starting with food', () {
      expect(expenseCategoriesFor(family: false), kExpenseCategories);
      expect(expenseCategoriesFor(family: false).first, 'Food');
    });

    test('a chat split in the kitchen is food, and anything else is Others',
        () {
      expect(splitCategoryFor(family: true, channelId: 'food'), 'Groceries');
      expect(splitCategoryFor(family: false, channelId: 'food'), 'Food');
      expect(splitCategoryFor(family: true, channelId: 'home'), 'Others');
      expect(splitCategoryFor(family: false, channelId: 'general'), 'Others');
    });

    test('every family category has a label in both languages', () {
      for (final c in kFamilyExpenseCategories) {
        final key = 'fund_cat_${c.toLowerCase()}';
        expect(en[key], isNotNull, reason: 'no English for $key');
        expect(bn[key], isNotNull, reason: 'no Bengali for $key');
      }
    });
  });

  group('family fund report', () {
    final family = TourGroup(
      id: 'f',
      name: 'Rahman family',
      ownerEmail: 'a@x.com',
      inviteCode: 'FAM00001',
      startDate: DateTime(2026, 10, 30),
      endDate: DateTime(2026, 10, 30),
      createdAt: DateTime(2026),
      kind: GroupKind.family,
      fundBudget: const FundBudget(
        categoryPaisa: {'Rent': 2000000, 'Groceries': 500000},
      ),
    );

    test(
        'budget lines follow the household categories, and old trip '
        'categories still show as typed', () {
      final report = FundReport.build(
        group: family,
        members: _members,
        expenses: [
          _exp('bazar', 300, 'Groceries'),
          _exp('gas', 120, 'Utilities'),
          _exp('old', 50, 'Hotel'),
        ],
        now: DateTime(2026, 10, 31),
      );
      final categories = report.lines.map((l) => l.category).toList();
      expect(categories, ['Groceries', 'Rent', 'Utilities', 'Hotel']);
    });

    test('spending totals are kept in paisa', () {
      final report = FundReport.build(
        group: family,
        members: _members,
        expenses: [_exp('bazar', 300, 'Groceries')],
        now: DateTime(2026, 10, 31),
      );
      expect(report.lines.first.spentPaisa, 30000);
      expect(report.spentPaisa, 30000);
    });
  });

  group('notice templates', () {
    test('a family circle is offered its own templates', () {
      expect(noticeTemplatesFor(family: true), kFamilyNoticeTemplates);
      expect(noticeTemplatesFor(family: false), kNoticeTemplates);
    });

    test('family template ids are unique and do not reuse trip ids', () {
      final ids = kFamilyNoticeTemplates.map((t) => t.id).toList();
      final trip = kNoticeTemplates.map((t) => t.id).toSet();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.where(trip.contains), isEmpty);
    });

    test('every family template has a title and a body in both languages', () {
      for (final t in kFamilyNoticeTemplates) {
        for (final lang in [en, bn]) {
          expect(lang['notice_tpl_${t.id}_title'], isNotNull,
              reason: 'title for ${t.id}');
          expect(lang['notice_tpl_${t.id}_body'], isNotNull,
              reason: 'body for ${t.id}');
        }
      }
    });

    test('family template text does not talk about trips or buses', () {
      for (final t in kFamilyNoticeTemplates) {
        final text = [
          en['notice_tpl_${t.id}_title']!,
          en['notice_tpl_${t.id}_body']!,
        ].join(' ').toLowerCase();
        for (final word in ['trip', 'tour', 'bus', 'hotel']) {
          expect(text, isNot(contains(word)), reason: '${t.id} mentions $word');
        }
      }
    });

    test('a safety check is urgent and asks everyone to confirm', () {
      final safety =
          kFamilyNoticeTemplates.singleWhere((t) => t.id == 'safety_check');
      expect(safety.kind, NoticeKind.emergency);
      expect(safety.urgent, isTrue);
      expect(safety.requireAck, isTrue);
    });
  });

  group('family channels', () {
    test('a family circle starts with its own built-in channels', () {
      expect(builtInChannelIdsFor(family: true), kFamilyChannelIds);
      expect(builtInChannelIdsFor(family: false), kBuiltInChannelIds);
    });

    test('family channels count as built in, so they cannot be deleted', () {
      for (final id in kFamilyChannelIds) {
        expect(TourChannel(id: id).isBuiltIn, isTrue, reason: id);
      }
    });

    test('the kitchen and outings keep the trip ids, so their history stays',
        () {
      expect(kFamilyChannelIds, containsAll(['food', 'sightseeing']));
    });
  });
}
