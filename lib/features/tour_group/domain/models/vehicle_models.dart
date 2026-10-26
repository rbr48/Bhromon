// Domain models for a tour's vehicles: buses, trains, flights, launches and
// more. Each vehicle's seat map is drawn from its layout settings by
// `seat_layout_engine.dart`; its seats are stored one document each.

import 'date_codec.dart';

/// The kinds of transport a Bangladeshi family tour uses. Each kind has its
/// own seat map style and sensible starting settings ([VehicleKindDefaults]).
enum VehicleKind {
  /// An AC or non-AC coach: 2+2 seats with a five-seat back row.
  bus,

  /// A business-class coach: 2+1 seats.
  businessBus,

  /// A sleeper coach: single and double berths on a lower and an upper deck.
  sleeperBus,

  /// A microbus (such as a Hiace): two seats beside the driver, then rows of
  /// three.
  microbus,

  /// A private car or 7-seater: one seat beside the driver, then rows of three.
  car,

  /// A train chair coach (Shovan, Shovan chair, Snigdha): numbered seats.
  trainChair,

  /// A train berth coach: cabins of four berths, two lower and two upper.
  trainCabin,

  /// A flight: rows by number, seats by letter.
  flight,

  /// A river launch: cabins on each floor, either side of a corridor.
  launchCabin,

  /// A sea ship or cruise (such as to Saint Martin's): rows of chairs.
  ship;

  static VehicleKind fromString(String? value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return VehicleKind.bus;
  }

  /// Kinds whose seats are cabins of berths rather than rows of seats.
  bool get usesCabins => this == trainCabin || this == launchCabin;

  /// Kinds with a driver at the front.
  bool get hasDriver =>
      this == bus ||
      this == businessBus ||
      this == sleeperBus ||
      this == microbus ||
      this == car;

  /// Kinds whose seat patterns can be changed. The others have a fixed shape.
  bool get hasPattern => !usesCabins && this != microbus && this != car;

  /// Kinds that can have more than one deck or floor.
  bool get hasDecks => this == sleeperBus || this == launchCabin;
}

/// Starting settings for a new vehicle of each kind.
class VehicleKindDefaults {
  const VehicleKindDefaults({
    required this.rows,
    required this.pattern,
    this.decks = 1,
    this.berthsPerCabin = 2,
  });

  final int rows;

  /// Seats per block across a row, left to right, with an aisle between
  /// blocks: '2-2', '2-1', '1-2', '3-3', '2-3-2' or '3'.
  final String pattern;
  final int decks;
  final int berthsPerCabin;

  static VehicleKindDefaults of(VehicleKind kind) => switch (kind) {
        VehicleKind.bus => const VehicleKindDefaults(rows: 9, pattern: '2-2'),
        VehicleKind.businessBus =>
          const VehicleKindDefaults(rows: 9, pattern: '2-1'),
        VehicleKind.sleeperBus =>
          const VehicleKindDefaults(rows: 5, pattern: '1-2', decks: 2),
        VehicleKind.microbus =>
          const VehicleKindDefaults(rows: 3, pattern: '3'),
        VehicleKind.car => const VehicleKindDefaults(rows: 1, pattern: '3'),
        VehicleKind.trainChair =>
          const VehicleKindDefaults(rows: 15, pattern: '2-2'),
        VehicleKind.trainCabin =>
          const VehicleKindDefaults(rows: 6, pattern: '4', berthsPerCabin: 4),
        VehicleKind.flight =>
          const VehicleKindDefaults(rows: 18, pattern: '2-2'),
        VehicleKind.launchCabin => const VehicleKindDefaults(
            rows: 4, pattern: '2', decks: 2, berthsPerCabin: 2),
        VehicleKind.ship =>
          const VehicleKindDefaults(rows: 10, pattern: '2-3-2'),
      };
}

/// The seat patterns a vehicle may use.
const List<String> kSeatPatterns = ['2-2', '2-1', '1-2', '3-3', '2-3-2', '3'];

/// Limits that keep a seat map a sensible size.
const int kMaxVehicleRows = 40;
const int kMaxVehicleDecks = 4;
const int kMaxBerthsPerCabin = 6;

class TourVehicle {
  const TourVehicle({
    required this.id,
    required this.kind,
    required this.name,
    this.number = '',
    this.route = '',
    this.departure,
    required this.rows,
    required this.pattern,
    this.decks = 1,
    this.berthsPerCabin = 2,
    this.locked = false,
    this.notes = '',
    required this.createdAt,
  });

  /// A new vehicle of [kind] with that kind's starting settings.
  factory TourVehicle.create({
    required String id,
    required VehicleKind kind,
    required String name,
    required DateTime now,
  }) {
    final d = VehicleKindDefaults.of(kind);
    return TourVehicle(
      id: id,
      kind: kind,
      name: name,
      rows: d.rows,
      pattern: d.pattern,
      decks: d.decks,
      berthsPerCabin: d.berthsPerCabin,
      createdAt: now,
    );
  }

  final String id;
  final VehicleKind kind;

  /// The operator or vehicle name, such as "Green Line Scania" or
  /// "Sonar Bangla Express".
  final String name;

  /// The coach, flight, cabin or registration number, such as "Coach Ja" or
  /// "BG 433".
  final String number;

  /// The leg it covers, such as "Dhaka → Cox's Bazar".
  final String route;

  final DateTime? departure;

  final int rows;
  final String pattern;
  final int decks;
  final int berthsPerCabin;

  /// When true only admins change seats.
  final bool locked;

  final String notes;
  final DateTime createdAt;

  /// The seat blocks across a row, for example [2, 2] for '2-2'.
  List<int> get blocks {
    final parts = pattern
        .split('-')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .where((n) => n > 0)
        .toList();
    return parts.isEmpty ? const [2, 2] : parts;
  }

  /// A copy with its settings brought within the allowed limits.
  TourVehicle normalized() {
    final d = VehicleKindDefaults.of(kind);
    return copyWith(
      rows: rows.clamp(1, kMaxVehicleRows),
      pattern: kind.hasPattern && kSeatPatterns.contains(pattern)
          ? pattern
          : d.pattern,
      decks: kind.hasDecks ? decks.clamp(1, kMaxVehicleDecks) : 1,
      berthsPerCabin: kind.usesCabins
          ? berthsPerCabin.clamp(1, kMaxBerthsPerCabin)
          : d.berthsPerCabin,
    );
  }

  TourVehicle copyWith({
    VehicleKind? kind,
    String? name,
    String? number,
    String? route,
    Object? departure = _keep,
    int? rows,
    String? pattern,
    int? decks,
    int? berthsPerCabin,
    bool? locked,
    String? notes,
  }) {
    return TourVehicle(
      id: id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      number: number ?? this.number,
      route: route ?? this.route,
      departure:
          identical(departure, _keep) ? this.departure : departure as DateTime?,
      rows: rows ?? this.rows,
      pattern: pattern ?? this.pattern,
      decks: decks ?? this.decks,
      berthsPerCabin: berthsPerCabin ?? this.berthsPerCabin,
      locked: locked ?? this.locked,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'number': number,
        'route': route,
        'departure': departure == null ? null : writeDate(departure!),
        'rows': rows,
        'pattern': pattern,
        'decks': decks,
        'berthsPerCabin': berthsPerCabin,
        'locked': locked,
        'notes': notes,
        'createdAt': writeDate(createdAt),
      };

  factory TourVehicle.fromMap(String id, Map<String, dynamic> map) {
    final kind = VehicleKind.fromString(map['kind'] as String?);
    final d = VehicleKindDefaults.of(kind);
    return TourVehicle(
      id: id,
      kind: kind,
      name: map['name'] as String? ?? '',
      number: map['number'] as String? ?? '',
      route: map['route'] as String? ?? '',
      departure: readDate(map['departure']),
      rows: (map['rows'] as num?)?.toInt() ?? d.rows,
      pattern: map['pattern'] as String? ?? d.pattern,
      decks: (map['decks'] as num?)?.toInt() ?? d.decks,
      berthsPerCabin:
          (map['berthsPerCabin'] as num?)?.toInt() ?? d.berthsPerCabin,
      locked: map['locked'] as bool? ?? false,
      notes: map['notes'] as String? ?? '',
      createdAt:
          readDate(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    ).normalized();
  }
}

const Object _keep = Object();
