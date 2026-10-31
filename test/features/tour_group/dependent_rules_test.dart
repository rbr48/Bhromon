import 'package:bhromon/features/tour_group/domain/models/dependent_models.dart';
import 'package:bhromon/features/tour_group/domain/services/dependent_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('family size with dependents', () {
    test('adding a dependent raises the size by one and is counted', () {
      final r = familySizeWithDependent(3);
      expect(r.size, 4);
      expect(r.counted, isTrue);
    });

    test('a member already at the largest size is not raised', () {
      final r = familySizeWithDependent(kMaxFamilySize);
      expect(r.size, kMaxFamilySize);
      expect(r.counted, isFalse);
    });

    test('removing a counted dependent lowers the size by one', () {
      expect(familySizeWithoutDependent(4, counted: true), 3);
    });

    test('removing a dependent that was not counted changes nothing', () {
      expect(familySizeWithoutDependent(kMaxFamilySize, counted: false),
          kMaxFamilySize);
    });

    test('the size never falls below one', () {
      expect(familySizeWithoutDependent(1, counted: true), 1);
    });

    test('an add and its remove leave the size where it started', () {
      final added = familySizeWithDependent(5);
      expect(familySizeWithoutDependent(added.size, counted: added.counted), 5);
    });
  });

  group('Dependent', () {
    test('reads a stored entry, trimming the name and the relation', () {
      final d = Dependent.fromMap('d1', {
        'name': '  Rafi ',
        'relation': ' son ',
        'parentEmail': 'asha@x.com',
        'countedInFamily': true,
      });
      expect(d, isNotNull);
      expect(d!.name, 'Rafi');
      expect(d.relation, 'son');
      expect(d.parentEmail, 'asha@x.com');
      expect(d.countedInFamily, isTrue);
    });

    test('an entry with no name or no parent is left out', () {
      expect(Dependent.fromMap('x', {'name': '  ', 'parentEmail': 'a@x.com'}),
          isNull);
      expect(Dependent.fromMap('x', {'name': 'Rafi'}), isNull);
    });

    test('writes the fields the rules check', () {
      const d = Dependent(id: 'd2', name: 'Nani', parentEmail: 'asha@x.com');
      expect(d.toFields().keys.toSet(),
          {'name', 'relation', 'parentEmail', 'countedInFamily'});
    });
  });
}
