import 'package:flutter/material.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/models/itinerary_models.dart';
import '../../../domain/models/predefined_spot.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/services/destination_catalog.dart';
import '../../../data/predefined_spots_repository.dart';
import '../../../../../core/localization/localized_date.dart';
import '../transport/local_fare_guide_sheet.dart';

/// The result of editing an itinerary.
class ItineraryEdit {
  const ItineraryEdit({required this.stops, required this.returnHome});

  final List<TourStop> stops;
  final bool returnHome;
}

String tourTypeKey(TourType t) => 'itin_kind_${t.name}';

IconData tourTypeIcon(TourType t) => switch (t) {
      TourType.beach => Icons.beach_access_rounded,
      TourType.hill => Icons.terrain_rounded,
      TourType.nature => Icons.forest_rounded,
      TourType.heritage => Icons.account_balance_rounded,
      TourType.city => Icons.location_city_rounded,
      TourType.custom => Icons.place_rounded,
    };

/// Opens the itinerary editor for [group]. Returns the new itinerary, or null
/// when the editor is dismissed.
Future<ItineraryEdit?> showItineraryEditor(
    BuildContext context, TourGroup group) {
  return Navigator.of(context).push<ItineraryEdit>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ItineraryEditorPage(group: group),
    ),
  );
}

class _ItineraryEditorPage extends StatefulWidget {
  const _ItineraryEditorPage({required this.group});

  final TourGroup group;

  @override
  State<_ItineraryEditorPage> createState() => _ItineraryEditorPageState();
}

class _ItineraryEditorPageState extends State<_ItineraryEditorPage> {
  late final List<TourStop> _stops = [...widget.group.effectiveStops];
  late bool _returnHome = widget.group.returnHome;

  void _sort() => _stops.sort((a, b) => a.arrive.compareTo(b.arrive));

  /// A new stop starts the day the last one ends.
  DateTime get _nextDay =>
      _stops.isEmpty ? widget.group.startDate : _stops.last.leave;

  Future<void> _add() async {
    final pick = await showDestinationPicker(context);
    if (pick == null || !mounted) return;
    final l10n = context.l10n;
    final start = _nextDay;
    final String name;
    final TourType kind;
    final double? lat;
    final double? lng;
    final String? presetId;

    if (pick.spot != null) {
      name = pick.spot!.name;
      kind = pick.spot!.kind;
      lat = pick.spot!.lat;
      lng = pick.spot!.lng;
      presetId = pick.spot!.pinId;
    } else if (pick.preset != null) {
      name = pick.preset!.nameFor(l10n.locale.languageCode);
      kind = pick.preset!.kind;
      lat = pick.preset!.lat;
      lng = pick.preset!.lng;
      presetId = pick.preset!.id;
    } else {
      name = '';
      kind = TourType.custom;
      lat = null;
      lng = null;
      presetId = null;
    }

    final stop = TourStop(
      id: const Uuid().v4(),
      name: name,
      kind: kind,
      arrive: start,
      leave: start.add(const Duration(days: 1)),
      lat: lat,
      lng: lng,
      presetId: presetId,
    );
    final edited = await _editStop(stop);
    if (edited == null) return;
    setState(() {
      _stops.add(edited);
      _sort();
    });
  }

  Future<TourStop?> _editStop(TourStop stop) {
    return showModalBottomSheet<TourStop>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.forest.surfaceFor(const Color(0xFF14241B)),
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StopSheet(stop: stop),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final days = localizedDateFormat('d MMM');
    return Scaffold(
      backgroundColor: context.forest.surfaceFor(const Color(0xFF0F1A1C)),
      appBar: AppBar(
        backgroundColor: context.forest.surfaceFor(const Color(0xFF142428)),
        foregroundColor: context.forest.text,
        title: Text(l10n.translate('itin_title'),
            style: TextStyle(
                color: context.forest.text,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'লোকাল পরিবহন ভাড়া গাইড',
            icon: const Icon(Icons.calculate_outlined),
            onPressed: () => showLocalFareGuideSheet(context),
          ),
          TextButton(
            onPressed: _stops.isEmpty
                ? null
                : () => Navigator.pop(context,
                    ItineraryEdit(stops: _stops, returnHome: _returnHome)),
            child: Text(l10n.translate('tour_save'),
                style: TextStyle(
                    color: context.forest.accentText,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.mintGreen,
        foregroundColor: AppColors.darkGreen,
        onPressed: _add,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: Text(l10n.translate('itin_add_stop')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text(l10n.translate('itin_help'),
              style: TextStyle(color: context.forest.text60, fontSize: 12)),
          const SizedBox(height: 12),
          _point(Icons.home_rounded, widget.group.originCity,
              l10n.translate('itin_start')),
          for (var i = 0; i < _stops.length; i++)
            Card(
              color: context.forest.surfaceFor(const Color(0xFF142428)),
              margin: const EdgeInsets.only(top: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.mintGreen.withValues(alpha: 0.2),
                  child: Icon(tourTypeIcon(_stops[i].kind),
                      color: context.forest.accentText),
                ),
                title: Text(
                    _stops[i].name.isEmpty
                        ? l10n.translate('itin_unnamed')
                        : _stops[i].name,
                    style: TextStyle(
                        color: context.forest.text,
                        fontWeight: FontWeight.bold)),
                subtitle: Text(
                  [
                    '${days.format(_stops[i].arrive)} – ${days.format(_stops[i].leave)}',
                    l10n.translate('itin_nights',
                        args: {'n': l10n.number(_stops[i].nights)}),
                    if (_stops[i].stay.isNotEmpty) _stops[i].stay,
                  ].join(' · '),
                  style: TextStyle(color: context.forest.text60, fontSize: 12),
                ),
                trailing: IconButton(
                  tooltip: l10n.translate('itin_remove'),
                  icon: Icon(Icons.delete_outline,
                      color: context.forest.readable(Colors.redAccent)),
                  onPressed: _stops.length == 1
                      ? null
                      : () => setState(() => _stops.removeAt(i)),
                ),
                onTap: () async {
                  final edited = await _editStop(_stops[i]);
                  if (edited == null) return;
                  setState(() {
                    _stops[i] = edited;
                    _sort();
                  });
                },
              ),
            ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _returnHome,
            activeThumbColor: AppColors.mintGreen,
            title: Text(
                l10n.translate('itin_return_home',
                    args: {'origin': widget.group.originCity}),
                style: TextStyle(color: context.forest.text)),
            onChanged: (v) => setState(() => _returnHome = v),
          ),
        ],
      ),
    );
  }

  Widget _point(IconData icon, String name, String label) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: context.forest.readable(AppColors.gold)),
        title: Text(name, style: TextStyle(color: context.forest.text)),
        subtitle: Text(label,
            style: TextStyle(color: context.forest.text54, fontSize: 12)),
      );
}

/// Name, dates, kind and stay for one stop.
class _StopSheet extends StatefulWidget {
  const _StopSheet({required this.stop});

  final TourStop stop;

  @override
  State<_StopSheet> createState() => _StopSheetState();
}

class _StopSheetState extends State<_StopSheet> {
  late TourStop _s = widget.stop;
  late final _name = TextEditingController(text: _s.name);
  late final _stay = TextEditingController(text: _s.stay);
  late final _notes = TextEditingController(text: _s.notes);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _stay.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(initial.year - 1),
        lastDate: DateTime(initial.year + 3),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final days = localizedDateFormat('EEE, d MMM yyyy');
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.translate('itin_stop'),
                style: TextStyle(
                    color: context.forest.text,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            TextField(
              controller: _name,
              style: TextStyle(color: context.forest.text),
              decoration:
                  InputDecoration(labelText: l10n.translate('itin_place')),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in TourType.values)
                  ChoiceChip(
                    avatar: Icon(tourTypeIcon(t),
                        size: 16,
                        color: t == _s.kind
                            ? AppColors.darkGreen
                            : context.forest.text70),
                    label: Text(l10n.translate(tourTypeKey(t))),
                    selected: t == _s.kind,
                    selectedColor: AppColors.mintGreen,
                    backgroundColor:
                        context.forest.surfaceFor(const Color(0xFF1E3326)),
                    labelStyle: TextStyle(
                        color: t == _s.kind
                            ? AppColors.darkGreen
                            : context.forest.text),
                    onSelected: (_) =>
                        setState(() => _s = _s.copyWith(kind: t)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  Icon(Icons.login_rounded, color: context.forest.accentText),
              title: Text(days.format(_s.arrive),
                  style: TextStyle(color: context.forest.text)),
              subtitle: Text(l10n.translate('itin_arrive'),
                  style: TextStyle(color: context.forest.text54)),
              onTap: () async {
                final d = await _pick(_s.arrive);
                if (d == null) return;
                setState(() => _s = _s.copyWith(
                    arrive: d, leave: _s.leave.isBefore(d) ? d : _s.leave));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout_rounded,
                  color: context.forest.readable(AppColors.gold)),
              title: Text(days.format(_s.leave),
                  style: TextStyle(color: context.forest.text)),
              subtitle: Text(
                  '${l10n.translate('itin_leave')} · ${l10n.translate('itin_nights', args: {
                        'n': l10n.number(_s.nights)
                      })}',
                  style: TextStyle(color: context.forest.text54)),
              onTap: () async {
                final d = await _pick(_s.leave);
                if (d == null) return;
                setState(() => _s = _s.copyWith(leave: d));
              },
            ),
            TextField(
              controller: _stay,
              style: TextStyle(color: context.forest.text),
              decoration:
                  InputDecoration(labelText: l10n.translate('itin_stay')),
            ),
            TextField(
              controller: _notes,
              maxLines: 2,
              maxLength: 300,
              style: TextStyle(color: context.forest.text),
              decoration:
                  InputDecoration(labelText: l10n.translate('itin_notes')),
            ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(
                      color: context.forest.readable(Colors.redAccent))),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: AppColors.darkGreen),
                onPressed: () {
                  final name = _name.text.trim();
                  if (name.isEmpty) {
                    setState(
                        () => _error = l10n.translate('itin_name_required'));
                    return;
                  }
                  if (_s.leave.isBefore(_s.arrive)) {
                    setState(() => _error = l10n.translate('itin_dates_bad'));
                    return;
                  }
                  // A typed name that matches the catalog gets its location.
                  final preset = _s.presetId == null || name != widget.stop.name
                      ? presetForName(name)
                      : presetById(_s.presetId);
                  Navigator.pop(
                    context,
                    _s.copyWith(
                      name: name,
                      stay: _stay.text.trim(),
                      notes: _notes.text.trim(),
                      lat: preset?.lat ?? _s.lat,
                      lng: preset?.lng ?? _s.lng,
                      presetId: preset?.id ?? _s.presetId,
                    ),
                  );
                },
                child: Text(l10n.translate('tour_save')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A catalog pick, verified spot, or a custom place.
class DestinationPick {
  const DestinationPick(this.preset, {this.spot});

  final DestinationPreset? preset;
  final PredefinedSpot? spot;

  bool get isCustom => preset == null && spot == null;
}

/// A searchable list of well-known places, grouped by kind, with verified
/// tourist spots and division/category filtering, or a choice to type any other place.
Future<DestinationPick?> showDestinationPicker(BuildContext context) {
  return showModalBottomSheet<DestinationPick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.forest.surfaceFor(const Color(0xFF14241B)),
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _DestinationPicker(),
  );
}

class _DestinationPicker extends StatefulWidget {
  const _DestinationPicker();

  @override
  State<_DestinationPicker> createState() => _DestinationPickerState();
}

class _DestinationPickerState extends State<_DestinationPicker> {
  String _query = '';
  String _selectedDivision = 'all';
  List<PredefinedSpot> _verifiedSpots = const [];

  static const _divisions = [
    'all',
    'Chattogram',
    'Sylhet',
    'Khulna',
    'Dhaka',
    'Rajshahi',
    'Barishal',
    'Rangpur',
  ];

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    final spots = await PredefinedSpotsRepository().loadSpots();
    if (mounted) {
      setState(() => _verifiedSpots = spots);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = l10n.locale.languageCode;
    final q = _query.trim().toLowerCase();

    // Filter verified spots from assets
    final matchingSpots = _verifiedSpots.where((s) {
      if (_selectedDivision != 'all' &&
          s.division.toLowerCase() != _selectedDivision.toLowerCase()) {
        return false;
      }
      return s.matches(q);
    }).toList(growable: false);

    // Filter catalog presets
    final matchingPresets = [
      for (final p in kDestinationCatalog)
        if ((_selectedDivision == 'all' ||
                p.region.toLowerCase() == _selectedDivision.toLowerCase()) &&
            (q.isEmpty ||
                p.nameEn.toLowerCase().contains(q) ||
                p.nameBn.contains(q) ||
                p.aliases.any((a) => a.contains(q))))
          p,
    ];

    final byKind = <TourType, List<DestinationPreset>>{};
    for (final p in matchingPresets) {
      byKind.putIfAbsent(p.kind, () => []).add(p);
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(color: context.forest.text),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: context.forest.text54),
                  hintText: l10n.translate('itin_search'),
                  hintStyle: TextStyle(color: context.forest.text38),
                ),
              ),
            ),
            // Division filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  for (final div in _divisions) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(div == 'all'
                            ? l10n.translate('itin_filter_all')
                            : div),
                        selected: _selectedDivision.toLowerCase() ==
                            div.toLowerCase(),
                        selectedColor:
                            context.forest.readable(AppColors.mintGreen),
                        labelStyle: TextStyle(
                          color: _selectedDivision.toLowerCase() ==
                                  div.toLowerCase()
                              ? AppColors.darkGreen
                              : context.forest.text,
                          fontWeight: _selectedDivision.toLowerCase() ==
                                  div.toLowerCase()
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (sel) {
                          if (sel) setState(() => _selectedDivision = div);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.edit_location_alt_rounded,
                  color: context.forest.readable(AppColors.gold)),
              title: Text(l10n.translate('itin_custom_place'),
                  style: TextStyle(color: context.forest.text)),
              onTap: () => Navigator.pop(context, const DestinationPick(null)),
            ),
            Divider(color: context.forest.divider12, height: 1),
            Expanded(
              child: ListView(
                children: [
                  // ── Verified Predefined Spots ───────────────────────
                  if (matchingSpots.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Row(
                        children: [
                          Icon(Icons.verified_rounded,
                              size: 16,
                              color:
                                  context.forest.readable(AppColors.mintGreen)),
                          const SizedBox(width: 6),
                          Text(
                            l10n.translate('itin_verified_spots', args: {
                              'count': l10n.number(matchingSpots.length)
                            }),
                            style: TextStyle(
                              color:
                                  context.forest.readable(AppColors.mintGreen),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final s in matchingSpots)
                      ListTile(
                        leading: Icon(tourTypeIcon(s.kind),
                            color: context.forest.accentText),
                        title: Text(s.name,
                            style: TextStyle(
                                color: context.forest.text,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${s.district} · ${s.division} — ${s.description}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.forest.text54, fontSize: 12),
                        ),
                        trailing: Icon(Icons.add_circle_outline_rounded,
                            size: 20, color: context.forest.accentText),
                        onTap: () => Navigator.pop(
                            context, DestinationPick(null, spot: s)),
                      ),
                    Divider(color: context.forest.divider12, height: 16),
                  ],

                  // ── Catalog Destinations ────────────────────────────
                  for (final kind in TourType.values)
                    if (byKind[kind] != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Text(l10n.translate(tourTypeKey(kind)),
                            style: TextStyle(
                                color: context.forest.readable(AppColors.gold),
                                fontWeight: FontWeight.bold)),
                      ),
                      for (final p in byKind[kind]!)
                        ListTile(
                          leading: Icon(tourTypeIcon(p.kind),
                              color: context.forest.accentText),
                          title: Text(p.nameFor(lang),
                              style: TextStyle(color: context.forest.text)),
                          subtitle: Text(
                              '${lang == 'bn' ? p.nameEn : p.nameBn} · ${p.region}',
                              style: TextStyle(
                                  color: context.forest.text54, fontSize: 12)),
                          onTap: () =>
                              Navigator.pop(context, DestinationPick(p)),
                        ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
