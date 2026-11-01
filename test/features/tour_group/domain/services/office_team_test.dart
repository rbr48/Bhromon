import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _circle({String? kind, String? preset}) => {
      'name': 'Sales team',
      'ownerEmail': 'boss@example.com',
      'inviteCode': 'ABCDEFGH',
      if (kind != null) 'kind': kind,
      if (preset != null) 'preset': preset,
    };

void main() {
  group('office and team preset', () {
    test('an office is a family-style circle with the office preset', () {
      final office =
          TourGroup.fromMap('g1', _circle(kind: 'family', preset: 'office'));

      expect(office.isOffice, isTrue);
      expect(office.isFamily, isTrue);
    });

    test('a family circle without a preset is not an office', () {
      final family = TourGroup.fromMap('g2', _circle(kind: 'family'));

      expect(family.isOffice, isFalse);
      expect(family.preset, isNull);
    });

    test('an unknown preset is read as no preset', () {
      final group =
          TourGroup.fromMap('g3', _circle(kind: 'family', preset: 'school'));

      expect(group.isOffice, isFalse);
      expect(group.preset, isNull);
    });

    test('the preset is written only when there is one', () {
      final office =
          TourGroup.fromMap('g1', _circle(kind: 'family', preset: 'office'));
      final family = TourGroup.fromMap('g2', _circle(kind: 'family'));

      expect(office.toMap()['preset'], 'office');
      expect(family.toMap().containsKey('preset'), isFalse);
    });

    test('an office offers its own categories; circles and trips keep theirs',
        () {
      final office =
          TourGroup.fromMap('g1', _circle(kind: 'family', preset: 'office'));
      final family = TourGroup.fromMap('g2', _circle(kind: 'family'));
      final trip = TourGroup.fromMap('g4', _circle());

      expect(expenseCategoriesForGroup(office), kOfficeExpenseCategories);
      expect(expenseCategoriesForGroup(office), contains('Dining'));
      expect(expenseCategoriesForGroup(office), isNot(contains('Rent')));
      expect(expenseCategoriesForGroup(family), contains('Rent'));
      expect(expenseCategoriesForGroup(trip), kExpenseCategories);
      expect(expenseCategoriesForGroup(null), kExpenseCategories);
    });
  });
}
