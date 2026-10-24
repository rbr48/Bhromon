import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';

void main() {
  group('TourGroup & TourMember Models', () {
    test('TourGroup serialization includes ownerUid and default values', () {
      final now = DateTime.now();
      final group = TourGroup(
        id: 'tour_123',
        name: 'Cox Bazar Retreat',
        description: 'Family holiday tour',
        destination: "Cox's Bazar",
        ownerEmail: 'owner@example.com',
        ownerUid: 'uid_999',
        inviteCode: 'A1B2C3',
        startDate: now,
        endDate: now.add(const Duration(days: 4)),
        createdAt: now,
      );

      final map = group.toMap();
      expect(map['id'], 'tour_123');
      expect(map['name'], 'Cox Bazar Retreat');
      expect(map['ownerEmail'], 'owner@example.com');
      expect(map['ownerUid'], 'uid_999');
      expect(map['inviteCode'], 'A1B2C3');
      expect(map['schemaVersion'], 2);

      final deserialized = TourGroup.fromMap('tour_123', map);
      expect(deserialized.id, 'tour_123');
      expect(deserialized.name, 'Cox Bazar Retreat');
      expect(deserialized.ownerEmail, 'owner@example.com');
      expect(deserialized.ownerUid, 'uid_999');
      expect(deserialized.inviteCode, 'A1B2C3');
    });

    test('TourMember serializes role owner as admin for Firestore rule compliance', () {
      final now = DateTime.now();
      final member = TourMember(
        tourId: 'tour_123',
        tourName: 'Cox Bazar Retreat',
        email: 'Owner@Example.Com',
        displayName: 'Tour Admin',
        role: TourRole.owner,
        status: TourMemberStatus.active,
        joinedAt: now,
      );

      final map = member.toMap();
      expect(map['tourId'], 'tour_123');
      expect(map['tourName'], 'Cox Bazar Retreat');
      expect(map['email'], 'owner@example.com');
      expect(map['role'], 'admin'); // Mapped to admin for rule compliance
      expect(map['status'], 'active');

      final deserialized = TourMember.fromMap(map);
      expect(deserialized.tourId, 'tour_123');
      expect(deserialized.tourName, 'Cox Bazar Retreat');
      expect(deserialized.email, 'owner@example.com');
      expect(deserialized.role, TourRole.admin);
      expect(deserialized.status, TourMemberStatus.active);
    });

    test('TourModules parses correctly from map', () {
      const modules = TourModules(
        seatsRooms: true,
        tideSafety: false,
        games: true,
        chat: true,
      );

      final map = modules.toMap();
      expect(map['seatsRooms'], isTrue);
      expect(map['tideSafety'], isFalse);
      expect(map['games'], isTrue);
      expect(map['chat'], isTrue);

      final parsed = TourModules.fromMap(map);
      expect(parsed.seatsRooms, isTrue);
      expect(parsed.tideSafety, isFalse);
      expect(parsed.games, isTrue);
      expect(parsed.chat, isTrue);
    });
  });
}
