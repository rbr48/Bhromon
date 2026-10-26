import '../models/date_codec.dart';
import '../models/logistics_models.dart';
import 'seat_layout_engine.dart';

/// Someone to seat or room, with the number of people travelling with them
/// counted in [familySize] (themselves included).
class PlanMember {
  const PlanMember({
    required this.email,
    required this.name,
    this.familySize = 1,
  });

  final String email;
  final String name;
  final int familySize;

  String get key => normalizeEmail(email);
  int get size => familySize.clamp(1, 20);
}

class SeatAssignment {
  const SeatAssignment({
    required this.seatId,
    required this.email,
    required this.name,
    required this.familySlot,
  });

  final String seatId;
  final String email;
  final String name;
  final int familySlot;
}

/// Seats on [layout] for everyone in [members] who has fewer seats than
/// their family needs. Seats already taken are left alone.
///
/// A family is kept side by side where possible: in the frontmost row where
/// it fits within one block of seats or across the row, otherwise in the next
/// free seats front to back.
/// Bigger families are seated first, so they find room together. When the
/// vehicle runs out of seats, the rest are left unseated.
List<SeatAssignment> planSeats({
  required VehicleLayout layout,
  required Iterable<BusSeat> taken,
  required List<PlanMember> members,
}) {
  final occupied = <String>{};
  final slotsHeld = <String, Set<int>>{};
  for (final s in taken) {
    if (!s.isOccupied) continue;
    occupied.add(s.seatNumber);
    slotsHeld
        .putIfAbsent(normalizeEmail(s.assignedMemberEmail!), () => {})
        .add(s.familySlot);
  }
  final free = layout.seatOrder.where((id) => !occupied.contains(id)).toSet();

  final queue = [
    for (final m in members)
      if ((slotsHeld[m.key]?.length ?? 0) < m.size) m,
  ]..sort((a, b) {
      final need = (b.size - (slotsHeld[b.key]?.length ?? 0))
          .compareTo(a.size - (slotsHeld[a.key]?.length ?? 0));
      return need != 0 ? need : a.name.compareTo(b.name);
    });

  final plan = <SeatAssignment>[];
  for (final m in queue) {
    if (free.isEmpty) break;
    final held = slotsHeld.putIfAbsent(m.key, () => {});
    final need = m.size - held.length;

    // Front to back, the first row where the family fits together: within
    // one of its blocks if possible, otherwise across the row.
    List<String>? pick;
    for (var r = 0; r < layout.rows.length && pick == null; r++) {
      for (final group in [...layout.rowBlocks[r], layout.rows[r]]) {
        final open = group.where(free.contains).toList();
        if (open.length >= need) {
          pick = open.take(need).toList();
          break;
        }
      }
    }
    pick ??= layout.seatOrder.where(free.contains).take(need).toList();

    for (final seatId in pick) {
      var slot = 0;
      while (held.contains(slot)) {
        slot++;
      }
      held.add(slot);
      free.remove(seatId);
      plan.add(SeatAssignment(
        seatId: seatId,
        email: m.key,
        name: m.name,
        familySlot: slot,
      ));
    }
  }
  return plan;
}

class RoomAssignment {
  const RoomAssignment({
    required this.roomId,
    required this.email,
    required this.name,
  });

  final String roomId;
  final String email;
  final String name;
}

class RoomPlan {
  const RoomPlan({required this.assignments, required this.unplaced});

  final List<RoomAssignment> assignments;

  /// Members whose whole family fits in no remaining room.
  final List<PlanMember> unplaced;
}

/// Rooms for everyone in [members] who has no room yet in the hotel named
/// [hotelName] ('' for a tour with one hotel). A family is never split: each
/// goes to the room that fits it with the fewest places left over, bigger
/// families first.
RoomPlan planRooms({
  required List<HotelRoom> rooms,
  required List<PlanMember> members,
  String hotelName = '',
}) {
  final hotelRooms = rooms.where((r) => r.hotelName == hotelName).toList()
    ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
  final sizes = {for (final m in members) m.key: m.size};
  final people = {for (final r in hotelRooms) r.id: r.peopleIn(sizes)};
  final guests = {
    for (final r in hotelRooms) r.id: r.assignedMemberEmails.length
  };
  final roomed = {for (final r in hotelRooms) ...r.assignedMemberEmails};

  final queue = members.where((m) => !roomed.contains(m.key)).toList()
    ..sort((a, b) {
      final s = b.size.compareTo(a.size);
      return s != 0 ? s : a.name.compareTo(b.name);
    });

  final assignments = <RoomAssignment>[];
  final unplaced = <PlanMember>[];
  for (final m in queue) {
    HotelRoom? best;
    var bestLeft = 1 << 30;
    for (final r in hotelRooms) {
      if (guests[r.id]! >= r.capacity) continue;
      final left = r.capacity - people[r.id]! - m.size;
      if (left >= 0 && left < bestLeft) {
        best = r;
        bestLeft = left;
      }
    }
    if (best == null) {
      unplaced.add(m);
      continue;
    }
    people[best.id] = people[best.id]! + m.size;
    guests[best.id] = guests[best.id]! + 1;
    assignments
        .add(RoomAssignment(roomId: best.id, email: m.key, name: m.name));
  }
  return RoomPlan(assignments: assignments, unplaced: unplaced);
}
