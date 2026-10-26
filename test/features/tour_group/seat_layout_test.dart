import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/logistics_models.dart';
import 'package:bhromon/features/tour_group/domain/models/vehicle_models.dart';
import 'package:bhromon/features/tour_group/domain/services/seat_layout_engine.dart';
import 'package:bhromon/features/tour_group/domain/services/seat_planner.dart';

TourVehicle _vehicle(VehicleKind kind,
        {int? rows, String? pattern, int? decks, int? berths}) =>
    TourVehicle.create(
            id: 'v1', kind: kind, name: 'Test', now: DateTime(2026, 10, 25))
        .copyWith(
            rows: rows, pattern: pattern, decks: decks, berthsPerCabin: berths);

BusSeat _taken(String seat, String email, {int slot = 0}) => BusSeat(
    seatNumber: seat,
    assignedMemberEmail: email,
    assignedMemberName: email,
    vehicleId: 'v1',
    familySlot: slot);

void main() {
  group('layouts', () {
    test('the original coach keeps its 36 seats A1 to I4', () {
      final l = legacyCoachLayout();
      expect(l.seatCount, 36);
      expect(l.seatOrder.first, 'A1');
      expect(l.seatOrder.last, 'I4');
      expect(l.windowSeats, containsAll(['A1', 'A4']));
      expect(l.windowSeats, isNot(contains('A2')));
    });

    test('a 2+2 coach gets a five-seat back row', () {
      final l = buildLayout(_vehicle(VehicleKind.bus));
      expect(l.seatCount, 9 * 4 + 5);
      expect(l.seatOrder.last, 'J5');
      expect(l.blocks.last, ['J1', 'J2', 'J3', 'J4', 'J5']);
    });

    test('a business coach is 2+1 with no back row', () {
      final l = buildLayout(_vehicle(VehicleKind.businessBus));
      expect(l.seatCount, 27);
      expect(l.rows.first, ['A1', 'A2', 'A3']);
    });

    test('a sleeper numbers berths per deck', () {
      final l = buildLayout(_vehicle(VehicleKind.sleeperBus));
      expect(l.decks, hasLength(2));
      expect(l.seatCount, 2 * 5 * 3);
      expect(l.seatOrder.first, 'L1');
      expect(l.seatOrder, contains('U15'));
      expect(l.decks[1].titleKey, 'veh_deck_upper');
    });

    test('a microbus has two seats beside the driver, then rows of three', () {
      final l = buildLayout(_vehicle(VehicleKind.microbus));
      expect(l.seatCount, 2 + 9);
      expect(l.rows.first, ['F1', 'F2']);
    });

    test('a train chair coach numbers seats front to back', () {
      final l = buildLayout(_vehicle(VehicleKind.trainChair, rows: 2));
      expect(l.seatOrder, ['1', '2', '3', '4', '5', '6', '7', '8']);
      expect(l.windowSeats, {'1', '4', '5', '8'});
    });

    test('a train cabin coach has lower and upper berths per cabin', () {
      final l = buildLayout(_vehicle(VehicleKind.trainCabin, rows: 2));
      expect(l.seatCount, 8);
      expect(l.blocks.first, ['C1-1', 'C1-2']);
      expect(l.blocks[1], ['C1-3', 'C1-4']);
      expect(l.rows.first, ['C1-1', 'C1-2', 'C1-3', 'C1-4']);
    });

    test('a flight names seats by row and letter', () {
      final l =
          buildLayout(_vehicle(VehicleKind.flight, rows: 2, pattern: '3-3'));
      expect(l.rows.first, ['1A', '1B', '1C', '1D', '1E', '1F']);
      expect(l.windowSeats, containsAll(['1A', '1F', '2A', '2F']));
    });

    test('a launch numbers cabins by floor', () {
      final l = buildLayout(_vehicle(VehicleKind.launchCabin, rows: 1));
      expect(l.decks, hasLength(2));
      expect(l.blocks, [
        ['101-1', '101-2'],
        ['102-1', '102-2'],
        ['201-1', '201-2'],
        ['202-1', '202-2'],
      ]);
    });

    test('a ship row is 2+3+2', () {
      final l = buildLayout(_vehicle(VehicleKind.ship, rows: 1));
      expect(l.blocks.map((b) => b.length), [2, 3, 2]);
    });

    test('settings out of range are brought back within limits', () {
      final v = _vehicle(VehicleKind.flight, rows: 500, pattern: '9-9');
      final l = buildLayout(v);
      expect(l.rows, hasLength(kMaxVehicleRows));
      expect(l.rows.first, hasLength(4)); // falls back to the 2-2 default
    });

    test('every seat id on a map is unique', () {
      for (final kind in VehicleKind.values) {
        final l = buildLayout(_vehicle(kind));
        expect(l.seatOrder.toSet().length, l.seatCount, reason: kind.name);
      }
    });
  });

  group('seat planner', () {
    final coach = buildLayout(_vehicle(VehicleKind.bus, rows: 3));

    test('a family of two sits side by side in one block', () {
      final plan = planSeats(layout: coach, taken: const [], members: const [
        PlanMember(email: 'rina@x.com', name: 'Rina', familySize: 2),
      ]);
      expect(plan.map((a) => a.seatId), ['A1', 'A2']);
      expect(plan.map((a) => a.familySlot), [0, 1]);
    });

    test('a family of four takes a whole row', () {
      final plan = planSeats(
        layout: coach,
        taken: [_taken('A1', 'other@x.com')],
        members: const [
          PlanMember(email: 'babu@x.com', name: 'Babu', familySize: 4),
        ],
      );
      expect(plan.map((a) => a.seatId), ['B1', 'B2', 'B3', 'B4']);
    });

    test('bigger families are seated first, and seated people are kept', () {
      final plan = planSeats(
        layout: coach,
        taken: [_taken('A1', 'rina@x.com')],
        members: const [
          PlanMember(email: 'rina@x.com', name: 'Rina', familySize: 2),
          PlanMember(email: 'solo@x.com', name: 'Solo'),
          PlanMember(email: 'big@x.com', name: 'Big', familySize: 3),
        ],
      );
      expect(plan.first.email, 'big@x.com');
      final rina = plan.where((a) => a.email == 'rina@x.com').toList();
      expect(rina, hasLength(1));
      expect(rina.single.familySlot, 1);
      expect(plan.where((a) => a.email == 'solo@x.com'), hasLength(1));
    });

    test('a full vehicle seats as many as it can and stops', () {
      final car = buildLayout(_vehicle(VehicleKind.car));
      final plan = planSeats(layout: car, taken: const [], members: const [
        PlanMember(email: 'a@x.com', name: 'A', familySize: 3),
        PlanMember(email: 'b@x.com', name: 'B', familySize: 3),
      ]);
      expect(plan, hasLength(4));
    });
  });

  group('room planner', () {
    HotelRoom room(String id, int capacity,
            {List<String> guests = const [], String hotel = ''}) =>
        HotelRoom(
          id: id,
          roomNumber: id,
          title: '',
          capacity: capacity,
          hotelName: hotel,
          assignedMemberEmails: guests,
          assignedMemberNames: guests,
        );

    test('each family goes to the tightest room that fits, never split', () {
      final plan = planRooms(
        rooms: [room('301', 2), room('302', 4), room('303', 6)],
        members: const [
          PlanMember(email: 'a@x.com', name: 'A', familySize: 4),
          PlanMember(email: 'b@x.com', name: 'B', familySize: 2),
          PlanMember(email: 'c@x.com', name: 'C', familySize: 7),
        ],
      );
      expect({for (final a in plan.assignments) a.email: a.roomId},
          {'a@x.com': '302', 'b@x.com': '301'});
      expect(plan.unplaced.single.email, 'c@x.com');
    });

    test('families already in a room count by size', () {
      final plan = planRooms(
        rooms: [
          room('301', 4, guests: ['a@x.com'])
        ],
        members: const [
          PlanMember(email: 'a@x.com', name: 'A', familySize: 3),
          PlanMember(email: 'b@x.com', name: 'B', familySize: 2),
        ],
      );
      expect(plan.assignments, isEmpty);
      expect(plan.unplaced.single.email, 'b@x.com');
    });

    test('each hotel is planned on its own', () {
      final plan = planRooms(
        hotelName: 'Sea Pearl',
        rooms: [
          room('1', 2, guests: ['a@x.com'], hotel: 'Hill View'),
          room('2', 2, hotel: 'Sea Pearl'),
        ],
        members: const [PlanMember(email: 'a@x.com', name: 'A')],
      );
      expect(plan.assignments.single.roomId, '2');
    });
  });

  test(
      'a seat round-trips its vehicle and family slot; old seats read as before',
      () {
    final seat = BusSeat.fromMap(_taken('C2', 'r@x.com', slot: 2).toMap());
    expect(seat.vehicleId, 'v1');
    expect(seat.familySlot, 2);
    final old = BusSeat.fromMap({'seatNumber': 'A1'});
    expect(old.vehicleId, isNull);
    expect(old.familySlot, 0);
  });

  test('a room round-trips its hotel, bed and balcony', () {
    final r = HotelRoom.fromMap(
        'r1',
        const HotelRoom(
          id: 'r1',
          roomNumber: '301',
          title: 'Deluxe',
          hotelName: 'Sea Pearl',
          bedType: 'twin',
          hasBalcony: true,
        ).toMap());
    expect(r.hotelName, 'Sea Pearl');
    expect(r.bedType, 'twin');
    expect(r.hasBalcony, isTrue);
    expect(HotelRoom.fromMap('r2', {'bedType': 'castle'}).bedType, '');
  });
}
