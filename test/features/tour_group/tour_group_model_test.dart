import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';

void main() {
  group('TourGroup & TourMember Models', () {
    test('TourGroup serialization includes ownerUid and default values', () {
      final now = DateTime(2026, 10, 25);
      final group = TourGroup(
        id: 'tour_123',
        name: 'Cox Bazar Retreat',
        description: 'Family holiday tour',
        destination: "Cox's Bazar",
        originCity: 'ঢাকা',
        tourType: TourType.beach,
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
      expect(map['destination'], "Cox's Bazar");
      expect(map['originCity'], 'ঢাকা');
      expect(map['tourType'], 'beach');
      expect(map['schemaVersion'], 4);

      final deserialized = TourGroup.fromMap('tour_123', map);
      expect(deserialized.id, 'tour_123');
      expect(deserialized.name, 'Cox Bazar Retreat');
      expect(deserialized.ownerEmail, 'owner@example.com');
      expect(deserialized.ownerUid, 'uid_999');
      expect(deserialized.inviteCode, 'A1B2C3');
      expect(deserialized.totalDays, 5);
      expect(deserialized.totalNights, 4);
      expect(deserialized.durationText, '৫ দিন ৪ রাত');
    });

    test('Universal Tour calculates 1-day day-tour accurately', () {
      final day = DateTime(2026, 11, 10);
      final group = TourGroup(
        id: 'tour_day_1',
        name: 'Sreemangal Day Tour',
        destination: 'Sreemangal',
        originCity: 'সিলেট',
        tourType: TourType.nature,
        ownerEmail: 'explorer@example.com',
        inviteCode: 'SRM001',
        startDate: day,
        endDate: day, // Single day
        createdAt: day,
      );

      expect(group.totalDays, 1);
      expect(group.totalNights, 0);
      expect(group.durationText, '১ দিন (ডে-ট্যুর)');
      expect(group.daysList.length, 1);
      expect(group.daysList.first.id, 'day1');
      expect(group.daysList.first.label, contains('ডে ১'));
    });

    test('Universal Tour calculates 7-day Sajek-to-Bandarban tour accurately',
        () {
      final start = DateTime(2026, 12, 1);
      final end = DateTime(2026, 12, 7);
      final group = TourGroup(
        id: 'tour_7days',
        name: 'Hill Odyssey',
        destination: 'Sajek Valley',
        originCity: 'ঢাকা',
        tourType: TourType.hill,
        ownerEmail: 'traveler@example.com',
        inviteCode: 'HLL007',
        startDate: start,
        endDate: end,
        customSpots: ['লুসাই হেরিটেজ ভিউ', 'মেঘের কটেজ'],
        createdAt: start,
      );

      expect(group.totalDays, 7);
      expect(group.totalNights, 6);
      expect(group.durationText, '৭ দিন ৬ রাত');
      expect(group.daysList.length, 7);
      expect(group.daysList.last.id, 'day7');
      expect(group.allSpots, contains('লুসাই হেরিটেজ ভিউ'));
      expect(group.allSpots, contains('কংলাক পাহাড় চূড়া (Konglak Peak)'));
    });

    test('TourMember serializes the owner role as owner, matching the rules',
        () {
      final now = DateTime.now();
      final member = TourMember(
        tourId: 'tour_123',
        tourName: 'Cox Bazar Retreat',
        email: 'Owner@Example.Com',
        displayName: 'Tour Admin',
        role: TourRole.owner,
        status: TourMemberStatus.active,
        joinedAt: now,
        uid: 'firebase_uid_123',
      );

      final map = member.toMap();
      expect(map['tourId'], 'tour_123');
      expect(map['tourName'], 'Cox Bazar Retreat');
      expect(map['email'], 'owner@example.com');
      expect(map['role'], 'owner');
      expect(map['status'], 'active');
      expect(map['uid'], 'firebase_uid_123');

      final deserialized = TourMember.fromMap(map);
      expect(deserialized.tourId, 'tour_123');
      expect(deserialized.tourName, 'Cox Bazar Retreat');
      expect(deserialized.email, 'owner@example.com');
      expect(deserialized.role, TourRole.owner);
      expect(deserialized.status, TourMemberStatus.active);
      expect(deserialized.uid, 'firebase_uid_123');
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
