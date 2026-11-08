import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/group_search_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupSearchEngine', () {
    final now = DateTime(2026, 11, 7);

    final messGroup = TourGroup(
      id: 'mess_1',
      name: 'Brothers Hall',
      destination: '',
      preset: TourGroup.messPreset,
      kind: GroupKind.family,
      ownerEmail: 'mess@test.com',
      inviteCode: 'MESSH123',
      startDate: now,
      endDate: now,
      createdAt: now,
    );

    final friendsGroup = TourGroup(
      id: 'friends_1',
      name: 'দোস্ত হ্যাংআউট',
      destination: '',
      preset: TourGroup.friendsPreset,
      kind: GroupKind.family,
      ownerEmail: 'friends@test.com',
      inviteCode: 'DOST9999',
      startDate: now,
      endDate: now,
      createdAt: now,
    );

    final tourGroup = TourGroup(
      id: 'tour_1',
      name: 'Cox Trip 2026',
      destination: "Cox's Bazar",
      kind: GroupKind.tour,
      ownerEmail: 'tour@test.com',
      inviteCode: 'COX2026X',
      startDate: now,
      endDate: now,
      createdAt: now,
    );

    final officeGroup = TourGroup(
      id: 'office_1',
      name: 'Dhaka Tech Team',
      destination: '',
      preset: TourGroup.officePreset,
      kind: GroupKind.family,
      ownerEmail: 'tech@test.com',
      inviteCode: 'TECH5555',
      startDate: now,
      endDate: now,
      createdAt: now,
    );

    final all = [messGroup, friendsGroup, tourGroup, officeGroup];

    test('returns all groups when query is empty or whitespace', () {
      expect(GroupSearchEngine.filter(groups: all, rawQuery: ''), all);
      expect(GroupSearchEngine.filter(groups: all, rawQuery: '   '), all);
    });

    test('filters by English group name case-insensitively', () {
      final res = GroupSearchEngine.filter(groups: all, rawQuery: 'brothers');
      expect(res.map((g) => g.id), ['mess_1']);
    });

    test('filters by Bengali group name', () {
      final res = GroupSearchEngine.filter(groups: all, rawQuery: 'দোস্ত');
      expect(res.map((g) => g.id), ['friends_1']);
    });

    test('filters by preset identifier or category alias (mess / মেস)', () {
      final resEn = GroupSearchEngine.filter(groups: all, rawQuery: 'mess');
      expect(resEn.map((g) => g.id), ['mess_1']);

      final resBn = GroupSearchEngine.filter(groups: all, rawQuery: 'মেস');
      expect(resBn.map((g) => g.id), ['mess_1']);
    });

    test('filters by office / টিম', () {
      final resOffice =
          GroupSearchEngine.filter(groups: all, rawQuery: 'office');
      expect(resOffice.map((g) => g.id), ['office_1']);

      final resTeamBn = GroupSearchEngine.filter(groups: all, rawQuery: 'টিম');
      expect(resTeamBn.map((g) => g.id), ['office_1']);
    });

    test('filters by trip destination (English and Bengali)', () {
      final resEn = GroupSearchEngine.filter(groups: all, rawQuery: 'bazar');
      expect(resEn.map((g) => g.id), ['tour_1']);

      final resBn =
          GroupSearchEngine.filter(groups: all, rawQuery: 'কক্সবাজার');
      expect(resBn.map((g) => g.id), ['tour_1']);
    });

    test('filters by invite code', () {
      final res = GroupSearchEngine.filter(groups: all, rawQuery: 'MESSH123');
      expect(res.map((g) => g.id), ['mess_1']);

      final partial = GroupSearchEngine.filter(groups: all, rawQuery: 'dost99');
      expect(partial.map((g) => g.id), ['friends_1']);
    });

    test('returns empty list when no group matches', () {
      final res =
          GroupSearchEngine.filter(groups: all, rawQuery: 'nonexistent-xyz');
      expect(res, isEmpty);
    });
  });
}
