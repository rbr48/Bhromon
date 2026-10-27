import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/date_codec.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/models/vehicle_models.dart';
import '../../domain/services/seat_layout_engine.dart';
import '../../domain/services/seat_planner.dart';
import '../widgets/transport/vehicle_editor_sheet.dart';
import '../widgets/transport/vehicle_seat_map.dart';
import '../../../../core/localization/localized_date.dart';

/// Seats on every vehicle of the tour: coaches, sleepers, microbuses, cars,
/// trains, flights, launches and ships. The tour's original 36-seat coach
/// stays available while anyone is seated on it, or while there are no other
/// vehicles.
class TransportScreen extends StatefulWidget {
  const TransportScreen(
      {super.key, required this.tourId, this.embedded = false});

  final String tourId;

  /// When true, only the body is built (used inside the logistics tabs).
  final bool embedded;

  @override
  State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen> {
  static const _coachId = '__coach';

  final TourGroupRepository _repository = TourGroupRepository();
  final List<StreamSubscription<Object?>> _subs = [];

  List<TourVehicle> _vehicles = const [];
  List<BusSeat> _coachSeats = const [];
  List<TourMember> _members = const [];
  bool _vehiclesLoaded = false;
  TourRole? _myRole;

  String? _selected;
  Stream<List<BusSeat>>? _seatStream;
  String? _seatStreamFor;
  bool _busy = false;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      _repository.watchVehicles(widget.tourId).listen((v) {
        if (mounted) {
          setState(() {
            _vehicles = v;
            _vehiclesLoaded = true;
          });
        }
      }, onError: (Object _) {
        if (mounted) setState(() => _vehiclesLoaded = true);
      }),
      _repository.watchCoachSeats(widget.tourId).listen((s) {
        if (mounted) setState(() => _coachSeats = s);
      }, onError: (Object _) {}),
      _repository.watchMembers(widget.tourId).listen((m) {
        if (mounted) setState(() => _members = m);
      }, onError: (Object _) {}),
    ]);
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  bool get _showCoach =>
      _vehicles.isEmpty || _coachSeats.any((s) => s.isOccupied);

  /// The tabs: the original coach (when shown) and then every vehicle.
  List<String> get _tabs =>
      [if (_showCoach) _coachId, for (final v in _vehicles) v.id];

  String get _current {
    final tabs = _tabs;
    if (_selected != null && tabs.contains(_selected)) return _selected!;
    return tabs.isEmpty ? _coachId : tabs.first;
  }

  TourVehicle? get _vehicle {
    final id = _current;
    for (final v in _vehicles) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// The vehicle id stored on seats: null for the original coach.
  String? get _vehicleId => _current == _coachId ? null : _current;

  Stream<List<BusSeat>> _seatsFor(String id) {
    if (_seatStreamFor != id || _seatStream == null) {
      _seatStreamFor = id;
      _seatStream =
          _repository.watchSeatsOf(widget.tourId, id == _coachId ? null : id);
    }
    return _seatStream!;
  }

  bool _canEditSeats(TourVehicle? v) => _isAdmin || !(v?.locked ?? false);

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.redAccent : null,
    ));
  }

  Future<void> _run(Future<void> Function() action) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack(l10n.translate('tour_seat_change_failed', args: {'error': e}),
          error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Vehicles ───────────────────────────────────────────────────────────

  Future<void> _addOrEdit({TourVehicle? existing}) async {
    final saved = await showVehicleEditor(context, existing: existing);
    if (saved == null || !mounted) return;
    await _run(() => _repository.saveVehicle(widget.tourId, saved));
    if (mounted) setState(() => _selected = saved.id);
  }

  Future<void> _delete(TourVehicle v) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title: Text(
            l10n.translate('veh_delete_confirm', args: {'name': v.name}),
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.translate('veh_delete_note'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.translate('tour_cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.translate('veh_delete'),
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _repository.deleteVehicle(widget.tourId, v.id));
  }

  // ── Seats ──────────────────────────────────────────────────────────────

  Future<void> _autoSeat(VehicleLayout layout, List<BusSeat> seats) async {
    final l10n = context.l10n;
    final members = [
      for (final m in _members)
        PlanMember(
            email: m.email, name: m.displayName, familySize: m.familyCount),
    ];
    final plan = planSeats(layout: layout, taken: seats, members: members);
    if (plan.isEmpty) {
      _snack(l10n.translate('veh_auto_none'));
      return;
    }
    final needed = members.fold<int>(0, (n, m) => n + m.size) -
        seats.where((s) => s.isOccupied).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title: Text(l10n.translate('veh_auto_title'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
            l10n.translate('veh_auto_body',
                args: {'n': l10n.number(plan.length)}),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.translate('tour_cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.translate('veh_auto_go'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _repository.applySeatPlan(widget.tourId, _vehicleId, plan,
        windowSeats: layout.windowSeats));
    final short = needed - plan.length;
    _snack(short > 0
        ? l10n.translate('veh_auto_short', args: {'n': l10n.number(short)})
        : l10n
            .translate('veh_auto_done', args: {'n': l10n.number(plan.length)}));
  }

  Future<void> _clear() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title: Text(l10n.translate('veh_clear_confirm'),
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.translate('tour_cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.translate('veh_clear'),
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _repository.clearSeats(widget.tourId, _vehicleId));
  }

  void _shareManifest(VehicleLayout layout, List<BusSeat> seats) {
    final l10n = context.l10n;
    final v = _vehicle;
    final byId = {for (final s in seats) s.seatNumber: s};
    final seatedEmails = {
      for (final s in seats)
        if (s.isOccupied) normalizeEmail(s.assignedMemberEmail!),
    };
    final lines = <String>[
      '${v?.name ?? l10n.translate('veh_coach')}'
          '${v != null && v.number.isNotEmpty ? ' · ${v.number}' : ''}',
      if (v != null && v.route.isNotEmpty) v.route,
      if (v?.departure != null)
        localizedDateFormat('d MMM yyyy, h:mm a').format(v!.departure!),
      '',
      for (final id in layout.seatOrder)
        if (byId[id]?.isOccupied ?? false)
          '$id — ${seatOccupantName(l10n, byId[id]!)}',
    ];
    final unseated = [
      for (final m in _members)
        if (!seatedEmails.contains(normalizeEmail(m.email))) m.displayName,
    ];
    if (unseated.isNotEmpty) {
      lines
        ..add('')
        ..add(l10n.translate('veh_unseated', args: {
          'names': unseated.join(', '),
        }));
    }
    final manifestText = lines.join('\n');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14241B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined,
                    color: AppColors.mintGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    v?.name ?? l10n.translate('veh_manifest'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  manifestText,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: manifestText));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('ম্যানিফেস্ট ক্লিপবোর্ডে কপি করা হয়েছে!'),
                          backgroundColor: AppColors.darkGreen,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('কপি করুন'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: AppColors.darkGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      // ignore: deprecated_member_use
                      Share.share(manifestText,
                          subject: v?.name ?? l10n.translate('veh_coach'));
                    },
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('শেয়ার করুন'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openSeat(String seatId, VehicleLayout layout, List<BusSeat> seats) {
    final v = _vehicle;
    final canEdit = _canEditSeats(v);
    final vehicleId = _vehicleId;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14241B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _SeatSheet(
        seatId: seatId,
        isWindow: layout.windowSeats.contains(seatId),
        seats: seats,
        members: _members,
        canEdit: canEdit,
        onAssign: (m) {
          Navigator.pop(ctx);
          _run(() => _repository.assignSeat(
                widget.tourId,
                seatId,
                vehicleId: vehicleId,
                email: m.email,
                name: m.displayName,
                familySize: m.familyCount,
                isWindow: layout.windowSeats.contains(seatId),
              ));
        },
        onFree: () {
          Navigator.pop(ctx);
          _run(() => _repository.assignSeat(widget.tourId, seatId,
              vehicleId: vehicleId,
              isWindow: layout.windowSeats.contains(seatId)));
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final body = !_vehiclesLoaded
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.midGreen))
        : Column(
            children: [
              _vehicleTabs(l10n),
              Expanded(child: _vehicleBody(l10n)),
            ],
          );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: Text(l10n.translate('veh_title'),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
      ),
      body: body,
    );
  }

  Widget _vehicleTabs(AppLocalizations l10n) {
    final current = _current;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final id in _tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  vehicleKindIcon(id == _coachId
                      ? null
                      : _vehicles.firstWhere((v) => v.id == id).kind),
                  size: 18,
                  color:
                      id == current ? AppColors.darkGreen : AppColors.mintGreen,
                ),
                label: Text(id == _coachId
                    ? l10n.translate('veh_coach')
                    : _vehicles.firstWhere((v) => v.id == id).name),
                selected: id == current,
                selectedColor: AppColors.mintGreen,
                backgroundColor: const Color(0xFF14241B),
                labelStyle: TextStyle(
                    color: id == current ? AppColors.darkGreen : Colors.white,
                    fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => _selected = id),
              ),
            ),
          if (_isAdmin)
            ActionChip(
              avatar: const Icon(Icons.add, size: 18, color: AppColors.gold),
              label: Text(l10n.translate('veh_add')),
              backgroundColor: const Color(0xFF14241B),
              labelStyle: const TextStyle(color: AppColors.gold),
              side: const BorderSide(color: AppColors.gold),
              onPressed: _busy ? null : () => _addOrEdit(),
            ),
        ],
      ),
    );
  }

  Widget _vehicleBody(AppLocalizations l10n) {
    final current = _current;
    final v = _vehicle;
    final layout = v == null ? legacyCoachLayout() : buildLayout(v);
    return StreamBuilder<List<BusSeat>>(
      stream: _seatsFor(current),
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.translate('tour_seats_unavailable'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.midGreen));
        }
        final valid = layout.seatOrder.toSet();
        final seats =
            snapshot.data!.where((s) => valid.contains(s.seatNumber)).toList();
        final byId = {for (final s in seats) s.seatNumber: s};
        final booked = seats.where((s) => s.isOccupied).length;
        final me = normalizeEmail(_repository.currentEmail);
        final mine = [
          for (final id in layout.seatOrder)
            if (byId[id]?.isOccupied == true &&
                normalizeEmail(byId[id]!.assignedMemberEmail!) == me)
              id,
        ];
        final needed = _members.fold<int>(0, (n, m) => n + m.familyCount);

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
          children: [
            _infoCard(l10n, v, booked, layout.seatCount, mine, needed),
            const SizedBox(height: 10),
            _actions(l10n, v, layout, seats),
            const SizedBox(height: 10),
            _legend(l10n),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF14241B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppColors.mintGreen.withValues(alpha: 0.3),
                    width: 1.5),
              ),
              child: VehicleSeatMap(
                layout: layout,
                seats: byId,
                myEmail: me,
                kind: v?.kind,
                onSeatTap: (id) => _openSeat(id, layout, seats),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoCard(AppLocalizations l10n, TourVehicle? v, int booked, int total,
      List<String> mine, int needed) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(vehicleKindIcon(v?.kind),
                  color: AppColors.mintGreen, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v?.name ?? l10n.translate('veh_coach'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text(
                      [
                        l10n.translate(v == null
                            ? 'veh_kind_bus'
                            : vehicleKindKey(v.kind)),
                        if (v != null && v.number.isNotEmpty) v.number,
                      ].join(' · '),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (v?.locked ?? false)
                Tooltip(
                  message: l10n.translate('veh_locked_note'),
                  child: const Icon(Icons.lock_rounded,
                      color: AppColors.gold, size: 18),
                ),
              if (_isAdmin && v != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                  color: const Color(0xFF1B4332),
                  onSelected: (choice) {
                    switch (choice) {
                      case 'edit':
                        _addOrEdit(existing: v);
                      case 'lock':
                        _run(() => _repository.saveVehicle(
                            widget.tourId, v.copyWith(locked: !v.locked)));
                      case 'delete':
                        _delete(v);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'edit', child: Text(l10n.translate('veh_edit'))),
                    PopupMenuItem(
                        value: 'lock',
                        child: Text(l10n
                            .translate(v.locked ? 'veh_unlock' : 'veh_lock'))),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.translate('veh_delete'),
                            style: const TextStyle(color: Colors.redAccent))),
                  ],
                ),
            ],
          ),
          if (v != null && (v.route.isNotEmpty || v.departure != null)) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (v.route.isNotEmpty) v.route,
                if (v.departure != null)
                  localizedDateFormat('d MMM, h:mm a').format(v.departure!),
              ].join(' · '),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          if (v != null && v.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(v.notes,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : booked / total,
              minHeight: 6,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation(AppColors.mintGreen),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.translate('veh_booked_line', args: {
              'booked': l10n.number(booked),
              'total': l10n.number(total),
              'people': l10n.number(needed),
            }),
            style: const TextStyle(color: AppColors.gold, fontSize: 12),
          ),
          if (mine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.translate('veh_my_seats',
                    args: {'seats': mine.join(', ')}),
                style: const TextStyle(
                    color: SeatColors.mine,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(AppLocalizations l10n, TourVehicle? v, VehicleLayout layout,
      List<BusSeat> seats) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_isAdmin)
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _autoSeat(layout, seats),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(l10n.translate('veh_auto')),
          ),
        OutlinedButton.icon(
          onPressed: () => _shareManifest(layout, seats),
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(l10n.translate('veh_manifest')),
        ),
        if (_isAdmin && seats.any((s) => s.isOccupied))
          TextButton.icon(
            onPressed: _busy ? null : _clear,
            icon:
                const Icon(Icons.layers_clear_rounded, color: Colors.redAccent),
            label: Text(l10n.translate('veh_clear'),
                style: const TextStyle(color: Colors.redAccent)),
          ),
      ],
    );
  }

  Widget _legend(AppLocalizations l10n) {
    Widget item(String label, Color color, {Color? border}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: border == null ? null : Border.all(color: border),
              ),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(l10n.translate('tour_seat_free'), SeatColors.free),
        item(l10n.translate('tour_seat_booked'), SeatColors.taken),
        item(l10n.translate('veh_mine'), SeatColors.mine),
        item(l10n.translate('veh_window'), SeatColors.free,
            border: SeatColors.window),
      ],
    );
  }
}

/// Who sits on one seat, and who can be put there.
class _SeatSheet extends StatefulWidget {
  const _SeatSheet({
    required this.seatId,
    required this.isWindow,
    required this.seats,
    required this.members,
    required this.canEdit,
    required this.onAssign,
    required this.onFree,
  });

  final String seatId;
  final bool isWindow;
  final List<BusSeat> seats;
  final List<TourMember> members;
  final bool canEdit;
  final ValueChanged<TourMember> onAssign;
  final VoidCallback onFree;

  @override
  State<_SeatSheet> createState() => _SeatSheetState();
}

class _SeatSheetState extends State<_SeatSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    BusSeat? seat;
    for (final s in widget.seats) {
      if (s.seatNumber == widget.seatId) seat = s;
    }
    final occupied = seat?.isOccupied ?? false;
    final held = <String, int>{};
    for (final s in widget.seats) {
      if (s.isOccupied) {
        final key = normalizeEmail(s.assignedMemberEmail!);
        held[key] = (held[key] ?? 0) + 1;
      }
    }
    final q = _query.trim().toLowerCase();
    final members = [
      for (final m in widget.members)
        if (q.isEmpty || m.displayName.toLowerCase().contains(q)) m,
    ];

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.translate('tour_seat_label',
                          args: {'number': widget.seatId}),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (widget.isWindow)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.window_rounded,
                          size: 16, color: SeatColors.window),
                      label: Text(l10n.translate('veh_window')),
                    ),
                  if (occupied && widget.canEdit)
                    TextButton.icon(
                      icon: const Icon(Icons.clear,
                          color: Colors.redAccent, size: 16),
                      label: Text(l10n.translate('tour_free_seat'),
                          style: const TextStyle(color: Colors.redAccent)),
                      onPressed: widget.onFree,
                    ),
                ],
              ),
              if (occupied)
                Text(seatOccupantName(l10n, seat!),
                    style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontWeight: FontWeight.w600)),
              const Divider(color: Colors.white12),
              if (!widget.canEdit)
                Text(l10n.translate('veh_locked_note'),
                    style: const TextStyle(color: AppColors.gold))
              else ...[
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    hintText: l10n.translate('veh_search'),
                    hintStyle: const TextStyle(color: Colors.white38),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.builder(
                    itemCount: members.length,
                    itemBuilder: (context, i) {
                      final m = members[i];
                      final key = normalizeEmail(m.email);
                      final isHere = occupied &&
                          normalizeEmail(seat!.assignedMemberEmail!) == key;
                      final has = held[key] ?? 0;
                      final family = m.familyCount.clamp(1, 20);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.midGreen,
                          child: Text(
                            m.displayName.isNotEmpty
                                ? m.displayName.characters.first
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(m.displayName,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          isHere
                              ? l10n.translate('tour_on_this_seat')
                              : has < family
                                  ? l10n.translate('veh_seats_held', args: {
                                      'held': l10n.number(has),
                                      'family': l10n.number(family),
                                    })
                                  : l10n.translate('veh_seat_moves'),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                        trailing: isHere
                            ? const Icon(Icons.check_circle,
                                color: AppColors.mintGreen)
                            : null,
                        onTap: isHere ? null : () => widget.onAssign(m),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
