import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/vehicle_models.dart';

void main() {
  group('NoticeKind', () {
    test('isTimed returns true for timed kinds', () {
      expect(NoticeKind.schedule.isTimed, isTrue);
      expect(NoticeKind.meetup.isTimed, isTrue);
      expect(NoticeKind.reminder.isTimed, isTrue);
      expect(NoticeKind.rollcall.isTimed, isTrue);
      expect(NoticeKind.announcement.isTimed, isFalse);
      expect(NoticeKind.rule.isTimed, isFalse);
    });

    test('asksEveryone returns true for required ack kinds', () {
      expect(NoticeKind.rollcall.asksEveryone, isTrue);
      expect(NoticeKind.emergency.asksEveryone, isTrue);
      expect(NoticeKind.rule.asksEveryone, isTrue);
      expect(NoticeKind.announcement.asksEveryone, isFalse);
    });

    test('fromName falls back to announcement', () {
      expect(NoticeKind.fromName('emergency'), NoticeKind.emergency);
      expect(NoticeKind.fromName('unknown'), NoticeKind.announcement);
      expect(NoticeKind.fromName(null), NoticeKind.announcement);
    });
  });

  group('TourNotice', () {
    final now = DateTime(2026, 10, 26, 14, 0);

    test('round-trips through fromMap and toEditableMap', () {
      final notice = TourNotice(
        id: 'n1',
        title: 'Gather at Gate',
        content: 'Please arrive by 2 PM',
        author: 'Admin',
        authorEmail: 'admin@bhromon.fun',
        urgent: true,
        createdAt: now,
        kind: NoticeKind.meetup,
        pinned: true,
        eventAt: now.add(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(hours: 3)),
        place: 'Main Terminal',
        mapUrl: 'https://maps.google.com',
        stopId: 'stop_1',
        requireAck: true,
        ackBy: const ['user1@bhromon.fun', 'user2@bhromon.fun'],
      );

      expect(notice.asksAnswer, isTrue);
      expect(notice.ackedBy('user1@bhromon.fun'), isTrue);
      expect(notice.ackedBy('user3@bhromon.fun'), isFalse);

      final editable = notice.toEditableMap();
      expect(editable['title'], 'Gather at Gate');
      expect(editable['urgent'], isTrue);
      expect(editable['kind'], 'meetup');

      final from = TourNotice.fromMap('n1', {
        ...editable,
        'author': 'Admin',
        'authorEmail': 'admin@bhromon.fun',
        'createdAt': now.toIso8601String(),
        'ackBy': ['user1@bhromon.fun'],
      });

      expect(from.id, 'n1');
      expect(from.title, 'Gather at Gate');
      expect(from.kind, NoticeKind.meetup);
      expect(from.ackedBy('user1@bhromon.fun'), isTrue);
    });
  });

  group('ChecklistItem', () {
    test('handles checking and email normalisation', () {
      final item = ChecklistItem.fromMap('item1', {
        'title': 'Raincoat',
        'category': 'Clothing',
        'checkedBy': ['  TEST@example.com  '],
      });

      expect(item.id, 'item1');
      expect(item.title, 'Raincoat');
      expect(item.isCheckedBy('test@example.com'), isTrue);
      expect(item.isCheckedBy('other@example.com'), isFalse);
    });
  });

  group('RouteCheckpoint', () {
    test('CheckpointKind parses correctly', () {
      expect(CheckpointKind.fromString('prayer'), CheckpointKind.prayer);
      expect(CheckpointKind.fromString('non_existent'), CheckpointKind.custom);
      expect(CheckpointKind.food.emoji, isNotEmpty);
      expect(CheckpointKind.prayer.emoji, isNotEmpty);
    });

    test('RouteCheckpoint round-trips correctly', () {
      final cp = RouteCheckpoint(
        id: 'cp1',
        name: 'Highway Rest Stop',
        highlight: 'Fresh tea',
        kmFromStart: 120,
        lat: 23.81,
        lng: 90.41,
        addedByEmail: 'user@bhromon.fun',
        kind: CheckpointKind.food,
        notes: 'Has clean washrooms',
      );

      expect(cp.hasLocation, isTrue);
      expect(cp.name, 'Highway Rest Stop');
    });
  });

  group('VehicleKind & TourVehicle', () {
    test('VehicleKind properties match requirements', () {
      expect(VehicleKind.fromString('bus'), VehicleKind.bus);
      expect(VehicleKind.fromString('unknown'), VehicleKind.bus);
      expect(VehicleKind.trainCabin.usesCabins, isTrue);
      expect(VehicleKind.bus.hasDriver, isTrue);
      expect(VehicleKind.flight.hasDriver, isFalse);
      expect(VehicleKind.sleeperBus.hasDecks, isTrue);
      expect(VehicleKind.bus.hasDecks, isFalse);
    });

    test('VehicleKindDefaults provides sensible starting layouts', () {
      for (final kind in VehicleKind.values) {
        final d = VehicleKindDefaults.of(kind);
        expect(d.rows, greaterThan(0));
        expect(d.pattern, isNotEmpty);
      }
    });

    test('TourVehicle create, blocks, and normalization', () {
      final now = DateTime(2026, 10, 26);
      final bus = TourVehicle.create(
        id: 'v1',
        kind: VehicleKind.bus,
        name: 'Green Line',
        now: now,
      );

      expect(bus.name, 'Green Line');
      expect(bus.blocks, equals([2, 2]));

      final invalid = TourVehicle(
        id: 'v2',
        kind: VehicleKind.bus,
        name: 'Overloaded',
        rows: 999,
        pattern: 'invalid-pattern',
        createdAt: now,
      );

      final normalized = invalid.normalized();
      expect(normalized.rows, equals(kMaxVehicleRows));
      expect(normalized.pattern, equals('2-2'));
    });
  });
}
