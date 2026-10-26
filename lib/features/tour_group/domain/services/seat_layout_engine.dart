import '../models/vehicle_models.dart';

/// What a place on a seat map is.
enum SeatCellKind { seat, berth, driver, door }

class SeatCell {
  const SeatCell.seat(this.seatId, {this.isWindow = false})
      : kind = SeatCellKind.seat;
  const SeatCell.berth(this.seatId, {this.isWindow = false})
      : kind = SeatCellKind.berth;
  const SeatCell.driver()
      : kind = SeatCellKind.driver,
        seatId = null,
        isWindow = false;
  const SeatCell.door()
      : kind = SeatCellKind.door,
        seatId = null,
        isWindow = false;

  final SeatCellKind kind;

  /// The id the seat is stored and shown by, such as "A3", "12C" or "101-2".
  /// Null for the driver and the door.
  final String? seatId;
  final bool isWindow;

  bool get isBookable => seatId != null;
}

/// Seats side by side with no aisle between them, or one cabin.
class SeatBlock {
  const SeatBlock(this.cells, {this.title});

  final List<SeatCell> cells;

  /// A cabin number or a "Lower"/"Upper" translation key, when the block has
  /// a heading.
  final String? title;
}

/// One row across the vehicle: blocks with an aisle between each.
class SeatRow {
  const SeatRow(this.blocks, {this.label, this.labelKey, this.labelArgs});

  final List<SeatBlock> blocks;

  /// Shown beside the row as is, such as "A" or "12".
  final String? label;

  /// Or a translation key with [labelArgs], such as a cabin heading.
  final String? labelKey;
  final Map<String, Object>? labelArgs;

  Iterable<String> get seatIds => [
        for (final b in blocks) ...b.cells.map((c) => c.seatId)
      ].whereType<String>();
}

class SeatDeck {
  const SeatDeck(this.rows, {this.titleKey, this.titleArgs});

  final List<SeatRow> rows;

  /// A translation key for the deck or floor heading, or null for one deck.
  final String? titleKey;
  final Map<String, Object>? titleArgs;
}

/// A vehicle's seat map.
class VehicleLayout {
  VehicleLayout(this.decks);

  final List<SeatDeck> decks;

  /// Every bookable seat, front to back and left to right.
  late final List<String> seatOrder = [
    for (final d in decks)
      for (final r in d.rows) ...r.seatIds,
  ];

  /// Seats that sit side by side, front to back. A family is kept within one
  /// of these first.
  late final List<List<String>> blocks = [
    for (final d in decks)
      for (final r in d.rows)
        for (final b in r.blocks)
          if (b.cells.any((c) => c.isBookable))
            [
              for (final c in b.cells)
                if (c.seatId != null) c.seatId!
            ],
  ];

  /// Each row's blocks, front to back: the seats a family can sit in
  /// together, closest first.
  late final List<List<List<String>>> rowBlocks = [
    for (final d in decks)
      for (final r in d.rows)
        if (r.seatIds.isNotEmpty)
          [
            for (final b in r.blocks)
              if (b.cells.any((c) => c.isBookable))
                [
                  for (final c in b.cells)
                    if (c.seatId != null) c.seatId!
                ],
          ],
  ];

  /// Seats in the same row, front to back.
  late final List<List<String>> rows = [
    for (final d in decks)
      for (final r in d.rows)
        if (r.seatIds.isNotEmpty) r.seatIds.toList(),
  ];

  late final Set<String> windowSeats = {
    for (final d in decks)
      for (final r in d.rows)
        for (final b in r.blocks)
          for (final c in b.cells)
            if (c.isWindow && c.seatId != null) c.seatId!,
  };

  int get seatCount => seatOrder.length;
}

/// The tour's original coach, kept as it was: rows A to I, four seats each,
/// stored in `bus_seats` with no vehicle id.
VehicleLayout legacyCoachLayout() => VehicleLayout([
      SeatDeck([
        _frontRow(),
        for (final row in 'ABCDEFGHI'.split(''))
          SeatRow(
            [
              SeatBlock([
                SeatCell.seat('${row}1', isWindow: true),
                SeatCell.seat('${row}2'),
              ]),
              SeatBlock([
                SeatCell.seat('${row}3'),
                SeatCell.seat('${row}4', isWindow: true),
              ]),
            ],
            label: row,
          ),
      ]),
    ]);

/// Builds the seat map for [vehicle].
VehicleLayout buildLayout(TourVehicle vehicle) {
  final v = vehicle.normalized();
  return switch (v.kind) {
    VehicleKind.bus ||
    VehicleKind.businessBus ||
    VehicleKind.ship =>
      _lettered(v, frontRow: v.kind != VehicleKind.ship),
    VehicleKind.sleeperBus => _sleeper(v),
    VehicleKind.microbus => _small(v, frontSeats: 2),
    VehicleKind.car => _small(v, frontSeats: 1),
    VehicleKind.trainChair => _numbered(v),
    VehicleKind.trainCabin => _trainCabins(v),
    VehicleKind.flight => _flight(v),
    VehicleKind.launchCabin => _launch(v),
  };
}

const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// A row label for row [i]: A to Z, then AA, AB and so on.
String _rowLetter(int i) =>
    i < 26 ? _letters[i] : '${_letters[i ~/ 26 - 1]}${_letters[i % 26]}';

/// Driver on the right (Bangladesh drives on the left), door on the left.
SeatRow _frontRow() => const SeatRow([
      SeatBlock([SeatCell.door()]),
      SeatBlock([SeatCell.driver()]),
    ]);

/// Coaches and ships: rows A, B, C…, seats numbered across the row. A 2+2
/// coach gets a five-seat back row, as Bangladeshi coaches do.
VehicleLayout _lettered(TourVehicle v, {required bool frontRow}) {
  final blocks = v.blocks;
  final across = blocks.fold(0, (n, b) => n + b);
  final rows = <SeatRow>[if (frontRow) _frontRow()];
  for (var r = 0; r < v.rows; r++) {
    final letter = _rowLetter(r);
    var col = 0;
    rows.add(SeatRow(
      [
        for (final size in blocks)
          SeatBlock([
            for (var i = 0; i < size; i++)
              () {
                col++;
                return SeatCell.seat('$letter$col',
                    isWindow: col == 1 || col == across);
              }(),
          ]),
      ],
      label: letter,
    ));
  }
  if (v.kind == VehicleKind.bus && blocks.length == 2 && blocks[0] == 2) {
    final letter = _rowLetter(v.rows);
    final back = across + 1;
    rows.add(SeatRow(
      [
        SeatBlock([
          for (var c = 1; c <= back; c++)
            SeatCell.seat('$letter$c', isWindow: c == 1 || c == back),
        ]),
      ],
      label: letter,
    ));
  }
  return VehicleLayout([SeatDeck(rows)]);
}

/// Sleeper coaches: berths numbered per deck, L1… below and U1… above.
VehicleLayout _sleeper(TourVehicle v) {
  final decks = <SeatDeck>[];
  for (var d = 0; d < v.decks; d++) {
    final prefix = switch (d) { 0 => 'L', 1 => 'U', _ => 'D${d + 1}-' };
    var n = 0;
    final across = v.blocks.fold(0, (s, b) => s + b);
    final rows = <SeatRow>[if (d == 0) _frontRow()];
    for (var r = 0; r < v.rows; r++) {
      var col = 0;
      rows.add(SeatRow([
        for (final size in v.blocks)
          SeatBlock([
            for (var i = 0; i < size; i++)
              () {
                col++;
                n++;
                return SeatCell.berth('$prefix$n',
                    isWindow: col == 1 || col == across);
              }(),
          ]),
      ]));
    }
    decks.add(SeatDeck(
      rows,
      titleKey: switch (d) {
        0 => 'veh_deck_lower',
        1 => 'veh_deck_upper',
        _ => 'veh_deck_n',
      },
      titleArgs: {'n': d + 1},
    ));
  }
  return VehicleLayout(decks);
}

/// Microbuses and cars: seats beside the driver (F1…), then rows of three.
VehicleLayout _small(TourVehicle v, {required int frontSeats}) {
  final rows = <SeatRow>[
    SeatRow([
      SeatBlock([
        for (var i = 1; i <= frontSeats; i++)
          SeatCell.seat('F$i', isWindow: i == 1),
      ]),
      const SeatBlock([SeatCell.driver()]),
    ], label: 'F'),
  ];
  for (var r = 0; r < v.rows; r++) {
    final letter = _rowLetter(r);
    rows.add(SeatRow([
      SeatBlock([
        for (var c = 1; c <= 3; c++)
          SeatCell.seat('$letter$c', isWindow: c == 1 || c == 3),
      ]),
    ], label: letter));
  }
  return VehicleLayout([SeatDeck(rows)]);
}

/// Train chair coaches: seats numbered 1, 2, 3… front to back.
VehicleLayout _numbered(TourVehicle v) {
  final across = v.blocks.fold(0, (s, b) => s + b);
  var n = 0;
  final rows = <SeatRow>[];
  for (var r = 0; r < v.rows; r++) {
    var col = 0;
    rows.add(SeatRow([
      for (final size in v.blocks)
        SeatBlock([
          for (var i = 0; i < size; i++)
            () {
              col++;
              n++;
              return SeatCell.seat('$n', isWindow: col == 1 || col == across);
            }(),
        ]),
    ]));
  }
  return VehicleLayout([SeatDeck(rows)]);
}

/// Train berth coaches: cabins of berths, lower berths first.
VehicleLayout _trainCabins(TourVehicle v) {
  final rows = <SeatRow>[];
  final per = v.berthsPerCabin;
  final lower = (per + 1) ~/ 2;
  for (var c = 1; c <= v.rows; c++) {
    rows.add(SeatRow(
      [
        SeatBlock([
          for (var b = 1; b <= lower; b++) SeatCell.berth('C$c-$b'),
        ], title: 'veh_berth_lower'),
        if (per > lower)
          SeatBlock([
            for (var b = lower + 1; b <= per; b++) SeatCell.berth('C$c-$b'),
          ], title: 'veh_berth_upper'),
      ],
      labelKey: 'veh_cabin',
      labelArgs: {'n': c},
    ));
  }
  return VehicleLayout([SeatDeck(rows)]);
}

/// Flights: rows by number, seats by letter, window seats at either end.
VehicleLayout _flight(TourVehicle v) {
  final blocks = v.blocks;
  final across = blocks.fold(0, (s, b) => s + b);
  final rows = <SeatRow>[];
  for (var r = 1; r <= v.rows; r++) {
    var col = 0;
    rows.add(SeatRow(
      [
        for (final size in blocks)
          SeatBlock([
            for (var i = 0; i < size; i++)
              () {
                final letter = _letters[col];
                col++;
                return SeatCell.seat('$r$letter',
                    isWindow: col == 1 || col == across);
              }(),
          ]),
      ],
      label: '$r',
    ));
  }
  return VehicleLayout([SeatDeck(rows)]);
}

/// River launches: on each floor, cabins either side of a corridor, numbered
/// 101, 102… on the first floor and 201… on the second. Berths are 101-1,
/// 101-2 and so on.
VehicleLayout _launch(TourVehicle v) {
  final decks = <SeatDeck>[];
  for (var d = 1; d <= v.decks; d++) {
    final rows = <SeatRow>[];
    var cabin = 0;
    for (var r = 0; r < v.rows; r++) {
      rows.add(SeatRow([
        for (var side = 0; side < 2; side++)
          () {
            cabin++;
            final number = d * 100 + cabin;
            return SeatBlock([
              for (var b = 1; b <= v.berthsPerCabin; b++)
                SeatCell.berth('$number-$b', isWindow: b == 1),
            ], title: '$number');
          }(),
      ]));
    }
    decks.add(SeatDeck(rows, titleKey: 'veh_floor', titleArgs: {'n': d}));
  }
  return VehicleLayout(decks);
}
