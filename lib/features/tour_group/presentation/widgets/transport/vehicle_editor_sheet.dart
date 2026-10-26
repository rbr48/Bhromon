import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/models/vehicle_models.dart';
import '../../../domain/services/seat_layout_engine.dart';
import 'vehicle_seat_map.dart';
import '../../../../../core/localization/localized_date.dart';

/// The translation key for a vehicle kind's name.
String vehicleKindKey(VehicleKind kind) => 'veh_kind_${kind.name}';

/// Opens the sheet for adding a vehicle, or editing [existing]. Returns the
/// vehicle to save, or null when the sheet is dismissed.
Future<TourVehicle?> showVehicleEditor(BuildContext context,
    {TourVehicle? existing}) {
  return showModalBottomSheet<TourVehicle>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14241B),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => VehicleEditorSheet(existing: existing),
  );
}

class VehicleEditorSheet extends StatefulWidget {
  const VehicleEditorSheet({super.key, this.existing});

  final TourVehicle? existing;

  @override
  State<VehicleEditorSheet> createState() => _VehicleEditorSheetState();
}

class _VehicleEditorSheetState extends State<VehicleEditorSheet> {
  late TourVehicle _v = widget.existing ??
      TourVehicle.create(
        id: const Uuid().v4(),
        kind: VehicleKind.bus,
        name: '',
        now: DateTime.now(),
      );
  late final _name = TextEditingController(text: _v.name);
  late final _number = TextEditingController(text: _v.number);
  late final _route = TextEditingController(text: _v.route);
  late final _notes = TextEditingController(text: _v.notes);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _route.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _pickKind(VehicleKind kind) {
    if (kind == _v.kind) return;
    final d = VehicleKindDefaults.of(kind);
    setState(() {
      _v = _v.copyWith(
        kind: kind,
        rows: d.rows,
        pattern: d.pattern,
        decks: d.decks,
        berthsPerCabin: d.berthsPerCabin,
      );
    });
  }

  Future<void> _pickDeparture() async {
    final now = DateTime.now();
    final start = _v.departure ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (!mounted) return;
    setState(() {
      _v = _v.copyWith(
        departure: DateTime(date.year, date.month, date.day, time?.hour ?? 0,
            time?.minute ?? 0),
      );
    });
  }

  void _save() {
    final l10n = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.translate('veh_name_required'));
      return;
    }
    Navigator.pop(
      context,
      _v
          .copyWith(
            name: name,
            number: _number.text.trim(),
            route: _route.text.trim(),
            notes: _notes.text.trim(),
          )
          .normalized(),
    );
  }

  Widget _stepper(
      String label, int value, int min, int max, ValueChanged<int> onChanged) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70))),
        IconButton(
          tooltip: l10n.translate('veh_less'),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
        ),
        SizedBox(
          width: 32,
          child: Text(l10n.number(value),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        IconButton(
          tooltip: l10n.translate('veh_more'),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
        ),
      ],
    );
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24)),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kind = _v.kind;
    final seatCount = buildLayout(_v).seatCount;
    final rowsLabel = switch (kind) {
      VehicleKind.trainCabin => l10n.translate('veh_cabins'),
      VehicleKind.launchCabin => l10n.translate('veh_cabin_rows'),
      _ => l10n.translate('veh_rows'),
    };

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              l10n.translate(widget.existing == null ? 'veh_add' : 'veh_edit'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(l10n.translate('veh_kind'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in VehicleKind.values)
                  ChoiceChip(
                    avatar: Icon(vehicleKindIcon(k),
                        size: 18,
                        color:
                            k == kind ? AppColors.darkGreen : Colors.white70),
                    label: Text(l10n.translate(vehicleKindKey(k))),
                    selected: k == kind,
                    selectedColor: AppColors.mintGreen,
                    backgroundColor: const Color(0xFF1E3326),
                    labelStyle: TextStyle(
                        color: k == kind ? AppColors.darkGreen : Colors.white,
                        fontWeight:
                            k == kind ? FontWeight.bold : FontWeight.normal),
                    onSelected: (_) => _pickKind(k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              style: const TextStyle(color: Colors.white),
              decoration: _field(l10n.translate('veh_name_hint')),
            ),
            TextField(
              controller: _number,
              style: const TextStyle(color: Colors.white),
              decoration: _field(l10n.translate('veh_number_hint')),
            ),
            TextField(
              controller: _route,
              style: const TextStyle(color: Colors.white),
              decoration: _field(l10n.translate('veh_route_hint')),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded,
                  color: AppColors.mintGreen),
              title: Text(
                _v.departure == null
                    ? l10n.translate('veh_departure_pick')
                    : localizedDateFormat('d MMM yyyy, h:mm a')
                        .format(_v.departure!),
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(l10n.translate('veh_departure'),
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              trailing: _v.departure == null
                  ? null
                  : IconButton(
                      tooltip: l10n.translate('veh_departure_clear'),
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () =>
                          setState(() => _v = _v.copyWith(departure: null)),
                    ),
              onTap: _pickDeparture,
            ),
            const Divider(color: Colors.white12),
            Text(l10n.translate('veh_layout'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            _stepper(rowsLabel, _v.rows, 1, kMaxVehicleRows,
                (n) => setState(() => _v = _v.copyWith(rows: n))),
            if (kind.hasPattern)
              Row(
                children: [
                  Expanded(
                      child: Text(l10n.translate('veh_pattern'),
                          style: const TextStyle(color: Colors.white70))),
                  DropdownButton<String>(
                    value: _v.pattern,
                    dropdownColor: const Color(0xFF1B4332),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      for (final p in kSeatPatterns)
                        DropdownMenuItem(
                            value: p, child: Text(p.replaceAll('-', ' + '))),
                    ],
                    onChanged: (p) {
                      if (p != null) {
                        setState(() => _v = _v.copyWith(pattern: p));
                      }
                    },
                  ),
                ],
              ),
            if (kind.hasDecks)
              _stepper(
                  l10n.translate(kind == VehicleKind.launchCabin
                      ? 'veh_floors'
                      : 'veh_decks'),
                  _v.decks,
                  1,
                  kMaxVehicleDecks,
                  (n) => setState(() => _v = _v.copyWith(decks: n))),
            if (kind.usesCabins)
              _stepper(
                  l10n.translate('veh_berths_per_cabin'),
                  _v.berthsPerCabin,
                  1,
                  kMaxBerthsPerCabin,
                  (n) => setState(() => _v = _v.copyWith(berthsPerCabin: n))),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                l10n.translate('veh_seat_count',
                    args: {'n': l10n.number(seatCount)}),
                style: const TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.bold),
              ),
            ),
            TextField(
              controller: _notes,
              maxLines: 2,
              maxLength: 300,
              style: const TextStyle(color: Colors.white),
              decoration: _field(l10n.translate('veh_notes_hint')),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: AppColors.darkGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _save,
              child: Text(l10n.translate('tour_save'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
