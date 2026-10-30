import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';

TourGroup _group({GroupKind kind = GroupKind.tour}) {
  final today = DateTime(2026, 10, 30);
  return TourGroup(
    id: 'fam_1',
    name: 'Rahman Family',
    description: '',
    destination: '',
    tourType: TourType.custom,
    ownerEmail: 'owner@example.com',
    ownerUid: 'uid_1',
    inviteCode: 'FAM00001',
    startDate: today,
    endDate: today,
    createdAt: today,
    kind: kind,
  );
}

void main() {
  group('GroupKind', () {
    test('reads family only for the exact stored value', () {
      expect(GroupKind.fromString('family'), GroupKind.family);
      expect(GroupKind.fromString('tour'), GroupKind.tour);
      expect(GroupKind.fromString(null), GroupKind.tour);
      expect(GroupKind.fromString('Family'), GroupKind.tour);
    });
  });

  group('TourGroup kind', () {
    test('a group is a trip unless it says otherwise', () {
      expect(_group().kind, GroupKind.tour);
      expect(_group().isFamily, isFalse);
    });

    test('a family circle is saved and read back as a family circle', () {
      final map = _group(kind: GroupKind.family).toMap();
      expect(map['kind'], 'family');

      final back = TourGroup.fromMap('fam_1', map);
      expect(back.kind, GroupKind.family);
      expect(back.isFamily, isTrue);
    });

    test('a trip saved before the kind field existed reads as a trip', () {
      final map = _group().toMap()..remove('kind');

      final back = TourGroup.fromMap('fam_1', map);
      expect(back.kind, GroupKind.tour);
      expect(back.isFamily, isFalse);
    });

    test('copyWith keeps the kind unless it is changed', () {
      final family = _group(kind: GroupKind.family);
      expect(family.copyWith(name: 'Renamed').isFamily, isTrue);
      expect(family.copyWith(kind: GroupKind.tour).isFamily, isFalse);
    });
  });
}
