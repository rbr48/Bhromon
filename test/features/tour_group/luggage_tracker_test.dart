import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bhromon/features/tour_group/domain/models/logistics_models.dart';

void main() {
  group('LuggageItem', () {
    test('parses from map and normalizes emails', () {
      final item = LuggageItem.fromMap('luggage_1', {
        'tourId': 'tour_123',
        'title': 'Red Trolley Bag',
        'tagColor': '0xFFEF5350',
        'ownerEmail': 'Owner@Test.com ',
        'ownerName': 'Rahim',
        'custodianEmail': 'CUSTODIAN@Test.com',
        'custodianName': 'Karim',
        'locationNotes': 'Bus boot',
        'isLoaded': true,
      });

      expect(item.id, equals('luggage_1'));
      expect(item.tourId, equals('tour_123'));
      expect(item.title, equals('Red Trolley Bag'));
      expect(item.tagColor, equals('0xFFEF5350'));
      expect(item.ownerEmail, equals('owner@test.com'));
      expect(item.ownerName, equals('Rahim'));
      expect(item.custodianEmail, equals('custodian@test.com'));
      expect(item.custodianName, equals('Karim'));
      expect(item.locationNotes, equals('Bus boot'));
      expect(item.isLoaded, isTrue);
    });

    test('serializes to Map correctly', () {
      final now = DateTime(2026, 10, 27, 14, 30);
      final item = LuggageItem(
        id: 'luggage_2',
        tourId: 'tour_abc',
        title: 'Blue Rucksack',
        tagColor: '0xFF42A5F5',
        ownerEmail: 'user@test.com',
        ownerName: 'Tanvir',
        isLoaded: false,
        updatedAt: now,
      );

      final map = item.toMap();
      expect(map['id'], equals('luggage_2'));
      expect(map['tourId'], equals('tour_abc'));
      expect(map['title'], equals('Blue Rucksack'));
      expect(map['tagColor'], equals('0xFF42A5F5'));
      expect(map['ownerEmail'], equals('user@test.com'));
      expect(map['isLoaded'], isFalse);
      expect(map['updatedAt'], isA<Timestamp>());
      expect(map.containsKey('custodianEmail'), isFalse);
    });

    test('copyWith updates specified fields and preserves others', () {
      final item = LuggageItem(
        id: 'luggage_3',
        tourId: 'tour_xyz',
        title: 'Camera Bag',
        ownerEmail: 'cam@test.com',
        ownerName: 'Cam Owner',
        locationNotes: 'Seat A1',
        isLoaded: false,
      );

      final updated = item.copyWith(
        isLoaded: true,
        locationNotes: 'In Hotel Room 204',
      );

      expect(updated.id, equals('luggage_3'));
      expect(updated.title, equals('Camera Bag'));
      expect(updated.isLoaded, isTrue);
      expect(updated.locationNotes, equals('In Hotel Room 204'));
      expect(updated.ownerEmail, equals('cam@test.com'));
    });
  });
}
