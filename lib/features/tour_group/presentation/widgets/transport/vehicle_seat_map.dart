import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/models/date_codec.dart';
import '../../../domain/models/logistics_models.dart';
import '../../../domain/models/vehicle_models.dart';
import '../../../domain/services/seat_layout_engine.dart';

/// Colours for the seat states, shared by the map and its legend.
class SeatColors {
  static const free = Color(0xFF22302A);
  static const taken = Color(0xFF2D6A4F);
  static const mine = Color(0xFFE8B04B);
  static const window = Color(0xFF74C69D);
}

IconData vehicleKindIcon(VehicleKind? kind) => switch (kind) {
      null || VehicleKind.bus => Icons.directions_bus_filled_rounded,
      VehicleKind.businessBus => Icons.directions_bus_rounded,
      VehicleKind.sleeperBus => Icons.bed_rounded,
      VehicleKind.microbus => Icons.airport_shuttle_rounded,
      VehicleKind.car => Icons.directions_car_rounded,
      VehicleKind.trainChair => Icons.train_rounded,
      VehicleKind.trainCabin => Icons.train_outlined,
      VehicleKind.flight => Icons.flight_rounded,
      VehicleKind.launchCabin => Icons.directions_boat_filled_rounded,
      VehicleKind.ship => Icons.sailing_rounded,
    };

/// The name a seat shows: the member, or "Rina +2" for the people travelling
/// with them.
String seatOccupantName(AppLocalizations l10n, BusSeat seat) {
  final name = seat.assignedMemberName?.trim();
  final base = (name == null || name.isEmpty)
      ? l10n.translate('tour_seat_booked')
      : name;
  if (seat.familySlot <= 0) return base;
  return l10n.translate('veh_family_seat',
      args: {'name': base, 'n': l10n.number(seat.familySlot)});
}

/// Draws a vehicle's seat map from its [layout]: decks, rows, blocks of seats
/// with an aisle between them, the driver and the door.
class VehicleSeatMap extends StatelessWidget {
  const VehicleSeatMap({
    super.key,
    required this.layout,
    required this.seats,
    required this.myEmail,
    required this.onSeatTap,
    this.kind,
  });

  final VehicleLayout layout;

  /// Seats by seat id. Seats missing here are free.
  final Map<String, BusSeat> seats;
  final String myEmail;
  final ValueChanged<String> onSeatTap;

  /// The vehicle kind, for the icon at the front. Null for the original coach.
  final VehicleKind? kind;

  static const double _labelWidth = 26;
  static const double _aisle = 22;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final me = normalizeEmail(myEmail);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(vehicleKindIcon(kind), color: AppColors.mintGreen, size: 18),
            const SizedBox(width: 6),
            Text(l10n.translate('veh_front').toUpperCase(),
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        for (final deck in layout.decks) ...[
          if (deck.titleKey != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Text(
                l10n.translate(deck.titleKey!, args: {
                  for (final e in (deck.titleArgs ?? const {}).entries)
                    e.key:
                        e.value is int ? l10n.number(e.value as int) : e.value,
                }),
                style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
          LayoutBuilder(builder: (context, constraints) {
            var widest = 0.0;
            for (final r in deck.rows) {
              var w = _labelWidth + (r.blocks.length - 1) * _aisle;
              for (final b in r.blocks) {
                w += (b.cells.length - 1).clamp(0, 99) * _gap;
                for (final c in b.cells) {
                  w += c.kind == SeatCellKind.berth ? 64 : 56;
                }
                if (b.title != null) w += 14; // the cabin box's padding
              }
              if (w > widest) widest = w;
            }
            final fits = widest <= constraints.maxWidth;
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in deck.rows) _row(context, row, me),
              ],
            );
            return fits
                ? content
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal, child: content);
          }),
        ],
        const SizedBox(height: 8),
        Center(
          child: Text(l10n.translate('veh_back').toUpperCase(),
              style: const TextStyle(
                  color: Colors.white24, fontSize: 10, letterSpacing: 2)),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, SeatRow row, String me) {
    final l10n = context.l10n;
    final label = row.label ??
        (row.labelKey == null
            ? null
            : l10n.translate(row.labelKey!, args: {
                for (final e in (row.labelArgs ?? const {}).entries)
                  e.key: e.value is int ? l10n.number(e.value as int) : e.value,
              }));
    final isHeading = row.labelKey != null;

    final blocks = <Widget>[];
    for (var i = 0; i < row.blocks.length; i++) {
      if (i > 0) blocks.add(const SizedBox(width: _aisle));
      blocks.add(_block(context, row.blocks[i], me));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isHeading && label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 4),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: _labelWidth,
                child: isHeading || label == null
                    ? null
                    : Text(label,
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
              ),
              ...blocks,
            ],
          ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, SeatBlock block, String me) {
    final l10n = context.l10n;
    final cells = <Widget>[];
    for (var i = 0; i < block.cells.length; i++) {
      if (i > 0) cells.add(const SizedBox(width: _gap));
      cells.add(_cell(context, block.cells[i], me));
    }
    final row = Row(mainAxisSize: MainAxisSize.min, children: cells);
    if (block.title == null) return row;
    final title = block.title!.startsWith('veh_')
        ? l10n.translate(block.title!)
        : block.title!;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 4),
          row,
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, SeatCell cell, String me) {
    final l10n = context.l10n;
    if (!cell.isBookable) {
      final driver = cell.kind == SeatCellKind.driver;
      return Tooltip(
        message: l10n.translate(driver ? 'tour_driver' : 'tour_door'),
        child: Container(
          width: 56,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
              driver ? Icons.sports_motorsports_rounded : Icons.sensor_door,
              color: Colors.white38,
              size: 18),
        ),
      );
    }

    final id = cell.seatId!;
    final seat = seats[id];
    final occupied = seat?.isOccupied ?? false;
    final mine = occupied && normalizeEmail(seat!.assignedMemberEmail!) == me;
    final berth = cell.kind == SeatCellKind.berth;
    final color = mine
        ? SeatColors.mine
        : occupied
            ? SeatColors.taken
            : SeatColors.free;
    final name = occupied ? seatOccupantName(l10n, seat!) : null;

    return Semantics(
      button: true,
      label: [
        l10n.translate('tour_seat_label', args: {'number': id}),
        if (cell.isWindow) l10n.translate('veh_window'),
        name ?? l10n.translate('tour_seat_free'),
      ].join(', '),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onSeatTap(id),
        child: Container(
          width: berth ? 64 : 56,
          height: berth ? 52 : 44,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: occupied ? 0.9 : 1),
            borderRadius: BorderRadius.circular(berth ? 8 : 10),
            border: Border.all(
              color: cell.isWindow
                  ? SeatColors.window.withValues(alpha: 0.7)
                  : Colors.white10,
              width: cell.isWindow ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      berth
                          ? Icons.bed_rounded
                          : Icons.airline_seat_recline_normal_rounded,
                      size: 11,
                      color: mine ? AppColors.darkGreen : Colors.white54),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(id,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: mine ? AppColors.darkGreen : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                name ?? l10n.translate('tour_seat_free'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mine
                      ? AppColors.darkGreen
                      : occupied
                          ? Colors.white
                          : Colors.white38,
                  fontSize: 9,
                  fontWeight: occupied ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
