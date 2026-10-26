import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/date_codec.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/seat_planner.dart';

/// Hotel rooms as a floor plan: grouped by hotel, then floor. Families count
/// by size, so a family of four fills a four-person room.
class HotelRoomMapScreen extends StatefulWidget {
  final String tourId;

  /// When true, only the body is built (used inside the logistics tabs).
  final bool embedded;

  const HotelRoomMapScreen(
      {super.key, required this.tourId, this.embedded = false});

  @override
  State<HotelRoomMapScreen> createState() => _HotelRoomMapScreenState();
}

class _HotelRoomMapScreenState extends State<HotelRoomMapScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  final Uuid _uuid = const Uuid();
  late final Stream<List<HotelRoom>> _rooms =
      _repository.watchHotelRooms(widget.tourId);
  StreamSubscription<List<TourMember>>? _memberSub;
  List<TourMember> _members = const [];
  TourRole? _myRole;
  String? _hotel;
  bool _busy = false;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  Map<String, int> get _familySizes => {
        for (final m in _members)
          normalizeEmail(m.email): m.familyCount.clamp(1, 20),
      };

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    });
    _memberSub = _repository.watchMembers(widget.tourId).listen((m) {
      if (mounted) setState(() => _members = m);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    super.dispose();
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text), backgroundColor: error ? Colors.redAccent : null));
  }

  String _hotelLabel(AppLocalizations l10n, String hotel) =>
      hotel.isEmpty ? l10n.translate('room_main_hotel') : hotel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final body = StreamBuilder<List<HotelRoom>>(
      stream: _rooms,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return Center(
            child: Text(l10n.translate('room_unavailable'),
                style: const TextStyle(color: Colors.white54)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.midGreen));
        }
        final rooms = snapshot.data!;
        if (rooms.isEmpty) return _empty(l10n);

        final hotels = <String>[];
        for (final r in rooms) {
          if (!hotels.contains(r.hotelName)) hotels.add(r.hotelName);
        }
        hotels.sort();
        final hotel =
            _hotel != null && hotels.contains(_hotel) ? _hotel! : hotels.first;
        final inHotel = rooms.where((r) => r.hotelName == hotel).toList();
        return _hotelView(l10n, rooms, hotels, hotel, inHotel);
      },
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: Text(l10n.translate('room_title'),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
      ),
      body: body,
    );
  }

  Widget _empty(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hotel_rounded, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          Text(l10n.translate('room_none'),
              style: const TextStyle(color: Colors.white70)),
          if (_isAdmin) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showRoomDialog(const []),
              icon: const Icon(Icons.add),
              label: Text(l10n.translate('room_add_first')),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hotelView(AppLocalizations l10n, List<HotelRoom> all,
      List<String> hotels, String hotel, List<HotelRoom> rooms) {
    final sizes = _familySizes;
    final capacity = rooms.fold<int>(0, (n, r) => n + r.capacity);
    final placed = rooms.fold<int>(0, (n, r) => n + r.peopleIn(sizes));
    final roomed = {for (final r in rooms) ...r.assignedMemberEmails};
    final waiting = [
      for (final m in _members)
        if (!roomed.contains(normalizeEmail(m.email))) m,
    ];
    final floors = <int, List<HotelRoom>>{};
    for (final r in rooms) {
      floors.putIfAbsent(r.floor, () => []).add(r);
    }
    final floorNumbers = floors.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        if (hotels.length > 1)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final h in hotels)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(Icons.apartment_rounded,
                          size: 18,
                          color: h == hotel
                              ? AppColors.darkGreen
                              : AppColors.mintGreen),
                      label: Text(_hotelLabel(l10n, h)),
                      selected: h == hotel,
                      selectedColor: AppColors.mintGreen,
                      backgroundColor: const Color(0xFF14241B),
                      labelStyle: TextStyle(
                          color:
                              h == hotel ? AppColors.darkGreen : Colors.white),
                      onSelected: (_) => setState(() => _hotel = h),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_hotelLabel(l10n, hotel),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                l10n.translate('room_summary', args: {
                  'rooms': l10n.number(rooms.length),
                  'placed': l10n.number(placed),
                  'capacity': l10n.number(capacity),
                }),
                style: const TextStyle(color: AppColors.gold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: capacity == 0 ? 0 : (placed / capacity).clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(AppColors.mintGreen),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_isAdmin)
                    FilledButton.tonalIcon(
                      onPressed: _busy || waiting.isEmpty
                          ? null
                          : () => _autoRoom(all, hotel),
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(l10n.translate('room_auto')),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _shareList(hotel, rooms, waiting),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(l10n.translate('room_share')),
                  ),
                  if (_isAdmin)
                    OutlinedButton.icon(
                      onPressed: () => _showRoomDialog(hotels, hotel: hotel),
                      icon: const Icon(Icons.add_home_work_rounded),
                      label: Text(l10n.translate('room_add')),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (waiting.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
              l10n.translate('room_waiting',
                  args: {'n': l10n.number(waiting.length)}),
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in waiting)
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                  side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.4)),
                  label: Text(
                    m.familyCount > 1
                        ? l10n.translate('room_family_of', args: {
                            'name': m.displayName,
                            'n': l10n.number(m.familyCount),
                          })
                        : m.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
        for (final floor in floorNumbers) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.stairs_rounded, color: AppColors.gold, size: 18),
              const SizedBox(width: 6),
              Text(
                  floor == 0
                      ? l10n.translate('room_ground_floor')
                      : l10n.translate('room_floor',
                          args: {'n': l10n.number(floor)}),
                  style: const TextStyle(
                      color: AppColors.gold, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final columns = (constraints.maxWidth / 170).floor().clamp(2, 6);
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final r in floors[floor]!)
                  SizedBox(width: width, child: _roomTile(l10n, r, hotels)),
              ],
            );
          }),
        ],
      ],
    );
  }

  Widget _roomTile(AppLocalizations l10n, HotelRoom room, List<String> hotels) {
    final sizes = _familySizes;
    final people = room.peopleIn(sizes);
    final ratio = room.capacity == 0 ? 0.0 : people / room.capacity;
    final color = people == 0
        ? Colors.white24
        : ratio >= 1
            ? Colors.redAccent
            : AppColors.mintGreen;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showGuestSheet(room.id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF14241B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(room.roomNumber,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18)),
                ),
                if (_isAdmin)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      tooltip: l10n.translate('room_options'),
                      icon: const Icon(Icons.more_vert,
                          color: Colors.white54, size: 18),
                      color: const Color(0xFF1B4332),
                      onSelected: (v) {
                        if (v == 'edit') {
                          _showRoomDialog(hotels, existing: room);
                        }
                        if (v == 'delete') _deleteRoom(room);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'edit',
                            child: Text(l10n.translate('room_edit'))),
                        PopupMenuItem(
                            value: 'delete',
                            child: Text(l10n.translate('room_delete'),
                                style:
                                    const TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  ),
              ],
            ),
            if (room.title.isNotEmpty)
              Text(room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                if (room.bedType.isNotEmpty)
                  _feature(Icons.king_bed_rounded,
                      l10n.translate('room_bed_${room.bedType}')),
                _feature(room.isAc ? Icons.ac_unit_rounded : Icons.air_rounded,
                    l10n.translate(room.isAc ? 'room_ac' : 'room_non_ac')),
                if (room.hasSeaView)
                  _feature(
                      Icons.waves_rounded, l10n.translate('room_sea_view')),
                if (room.hasBalcony)
                  _feature(
                      Icons.balcony_rounded, l10n.translate('room_balcony')),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio.clamp(0, 1),
                minHeight: 5,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.translate('room_people', args: {
                'people': l10n.number(people),
                'capacity': l10n.number(room.capacity),
              }),
              style: TextStyle(color: color, fontSize: 11),
            ),
            if (room.assignedMemberNames.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                room.assignedMemberNames.where((n) => n.isNotEmpty).join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _feature(IconData icon, String label) => Tooltip(
        message: label,
        child: Icon(icon, size: 16, color: Colors.white54),
      );

  Future<void> _autoRoom(List<HotelRoom> rooms, String hotel) async {
    final l10n = context.l10n;
    final plan = planRooms(
      rooms: rooms,
      hotelName: hotel,
      members: [
        for (final m in _members)
          PlanMember(
              email: m.email, name: m.displayName, familySize: m.familyCount),
      ],
    );
    if (plan.assignments.isEmpty) {
      _snack(l10n.translate('room_auto_none'));
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.applyRoomPlan(widget.tourId, plan.assignments);
      _snack(plan.unplaced.isEmpty
          ? l10n.translate('room_auto_done',
              args: {'n': l10n.number(plan.assignments.length)})
          : l10n.translate('room_auto_short', args: {
              'n': l10n.number(plan.assignments.length),
              'names': plan.unplaced.map((m) => m.name).join(', '),
            }));
    } catch (e) {
      _snack(l10n.translate('room_change_failed', args: {'error': e}),
          error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _shareList(
      String hotel, List<HotelRoom> rooms, List<TourMember> waiting) {
    final l10n = context.l10n;
    final sorted = [...rooms]..sort((a, b) {
        final f = a.floor.compareTo(b.floor);
        return f != 0 ? f : a.roomNumber.compareTo(b.roomNumber);
      });
    final lines = [
      _hotelLabel(l10n, hotel),
      '',
      for (final r in sorted)
        '${l10n.translate('room_label', args: {'number': r.roomNumber})}: '
            '${r.assignedMemberNames.where((n) => n.isNotEmpty).join(', ')}',
      if (waiting.isNotEmpty) ...[
        '',
        l10n.translate('room_waiting_list',
            args: {'names': waiting.map((m) => m.displayName).join(', ')}),
      ],
    ];
    // ignore: deprecated_member_use
    Share.share(lines.join('\n'), subject: _hotelLabel(l10n, hotel));
  }

  Future<void> _deleteRoom(HotelRoom room) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title: Text(
            l10n.translate('room_delete_confirm',
                args: {'number': room.roomNumber}),
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.translate('check_no'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.translate('room_delete'),
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteHotelRoom(widget.tourId, room.id);
    } catch (e) {
      _snack(l10n.translate('room_delete_failed', args: {'error': e}),
          error: true);
    }
  }

  void _showRoomDialog(List<String> hotels,
      {HotelRoom? existing, String? hotel}) {
    final l10n = context.l10n;
    final numberCtrl = TextEditingController(text: existing?.roomNumber ?? '');
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final floorCtrl = TextEditingController(text: '${existing?.floor ?? 1}');
    final hotelCtrl =
        TextEditingController(text: existing?.hotelName ?? hotel ?? '');
    int capacity = existing?.capacity ?? 2;
    bool isAc = existing?.isAc ?? true;
    bool hasSeaView = existing?.hasSeaView ?? false;
    bool hasBalcony = existing?.hasBalcony ?? false;
    String bedType = existing?.bedType ?? '';
    String? error;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF14241B),
          title: Text(
              l10n.translate(existing == null ? 'room_add' : 'room_edit'),
              style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: hotelCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                      labelText: l10n.translate('room_hotel_name'),
                      helperText: l10n.translate('room_hotel_name_help'),
                      helperStyle: const TextStyle(color: Colors.white38)),
                ),
                if (hotels.where((h) => h.isNotEmpty).isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final h in hotels.where((h) => h.isNotEmpty))
                        ActionChip(
                          label: Text(h),
                          onPressed: () =>
                              setDialogState(() => hotelCtrl.text = h),
                        ),
                    ],
                  ),
                TextField(
                  controller: numberCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration:
                      InputDecoration(labelText: l10n.translate('room_number')),
                ),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration:
                      InputDecoration(labelText: l10n.translate('room_type')),
                ),
                DropdownButtonFormField<int>(
                  initialValue: capacity,
                  dropdownColor: const Color(0xFF1B4332),
                  decoration: InputDecoration(
                      labelText: l10n.translate('room_capacity')),
                  items: [
                    for (var c = 1; c <= 10; c++)
                      DropdownMenuItem(
                          value: c,
                          child: Text(l10n.translate('room_capacity_n',
                              args: {'n': l10n.number(c)}))),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => capacity = v);
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: bedType,
                  dropdownColor: const Color(0xFF1B4332),
                  decoration:
                      InputDecoration(labelText: l10n.translate('room_bed')),
                  items: [
                    DropdownMenuItem(
                        value: '',
                        child: Text(l10n.translate('room_bed_none'))),
                    for (final b in kBedTypes)
                      DropdownMenuItem(
                          value: b, child: Text(l10n.translate('room_bed_$b'))),
                  ],
                  onChanged: (v) => setDialogState(() => bedType = v ?? ''),
                ),
                TextField(
                  controller: floorCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                      labelText: l10n.translate('room_floor_label')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.translate('room_ac'),
                      style: const TextStyle(color: Colors.white)),
                  value: isAc,
                  activeThumbColor: AppColors.mintGreen,
                  onChanged: (v) => setDialogState(() => isAc = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.translate('room_sea_view'),
                      style: const TextStyle(color: Colors.white)),
                  value: hasSeaView,
                  activeThumbColor: AppColors.gold,
                  onChanged: (v) => setDialogState(() => hasSeaView = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.translate('room_balcony'),
                      style: const TextStyle(color: Colors.white)),
                  value: hasBalcony,
                  activeThumbColor: AppColors.gold,
                  onChanged: (v) => setDialogState(() => hasBalcony = v),
                ),
                if (error != null)
                  Text(error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.translate('tour_cancel'))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: () async {
                final number = numberCtrl.text.trim();
                final floor = int.tryParse(floorCtrl.text.trim());
                if (number.isEmpty) {
                  setDialogState(
                      () => error = l10n.translate('room_number_required'));
                  return;
                }
                if (floor == null || floor < 0 || floor > 200) {
                  setDialogState(
                      () => error = l10n.translate('room_floor_invalid'));
                  return;
                }
                final room = HotelRoom(
                  id: existing?.id ?? _uuid.v4(),
                  roomNumber: number,
                  title: titleCtrl.text.trim(),
                  capacity: capacity,
                  floor: floor,
                  isAc: isAc,
                  hasSeaView: hasSeaView,
                  hasBalcony: hasBalcony,
                  hotelName: hotelCtrl.text.trim(),
                  bedType: bedType,
                  assignedMemberEmails:
                      existing?.assignedMemberEmails ?? const [],
                  assignedMemberNames:
                      existing?.assignedMemberNames ?? const [],
                );
                // Shrinking capacity below the current guests is refused.
                if (room.assignedMemberEmails.length > room.capacity) {
                  setDialogState(() => error = l10n
                          .translate('room_capacity_too_small', args: {
                        'n': l10n.number(room.assignedMemberEmails.length)
                      }));
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await _repository.saveHotelRoom(widget.tourId, room);
                  if (mounted) setState(() => _hotel = room.hotelName);
                } catch (e) {
                  _snack(l10n.translate('room_save_failed'), error: true);
                }
              },
              child: Text(l10n.translate('tour_save'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      numberCtrl.dispose();
      titleCtrl.dispose();
      floorCtrl.dispose();
      hotelCtrl.dispose();
    });
  }

  /// Guest list for one room, read live so it always shows the current state.
  void _showGuestSheet(String roomId) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: const Color(0xFF14241B),
      builder: (ctx) {
        return StreamBuilder<List<HotelRoom>>(
          stream: _repository.watchHotelRooms(widget.tourId),
          builder: (context, roomSnap) {
            final room = (roomSnap.data ?? const <HotelRoom>[])
                .where((r) => r.id == roomId)
                .firstOrNull;
            if (room == null) {
              return SizedBox(
                  height: 120,
                  child: Center(
                      child: Text(l10n.translate('room_gone'),
                          style: const TextStyle(color: Colors.white54))));
            }
            final sizes = _familySizes;
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l10n.translate('room_label', args: {
                              'number': room.roomNumber
                            })} — ${l10n.translate('room_people', args: {
                              'people': l10n.number(room.peopleIn(sizes)),
                              'capacity': l10n.number(room.capacity),
                            })}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      if (room.hotelName.isNotEmpty)
                        Text(room.hotelName,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      const Divider(color: Colors.white12),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final m in _members)
                              _guestTile(l10n, room, m, sizes),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _guestTile(AppLocalizations l10n, HotelRoom room, TourMember m,
      Map<String, int> sizes) {
    final here = room.hasGuest(m.email);
    final family = m.familyCount.clamp(1, 20);
    final fits = room.fitsFamily(family, sizes);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.midGreen,
        child: Text(
            m.displayName.isNotEmpty ? m.displayName.characters.first : '?',
            style: const TextStyle(color: Colors.white)),
      ),
      title: Text(
          family > 1
              ? l10n.translate('room_family_of',
                  args: {'name': m.displayName, 'n': l10n.number(family)})
              : m.displayName,
          style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        here
            ? l10n.translate('room_in_this')
            : fits
                ? l10n.translate('room_move_note')
                : l10n.translate('room_no_space'),
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
      trailing: IconButton(
        tooltip: l10n.translate(here ? 'room_remove_guest' : 'room_add_guest'),
        icon: Icon(here ? Icons.remove_circle : Icons.add_circle,
            color: here
                ? Colors.redAccent
                : (fits ? AppColors.mintGreen : Colors.white24)),
        onPressed: !here && !fits
            ? null
            : () async {
                try {
                  if (here) {
                    await _repository.removeHotelGuest(
                        widget.tourId, room.id, m.email);
                  } else {
                    await _repository.assignHotelGuest(widget.tourId, room.id,
                        email: m.email, name: m.displayName);
                  }
                } on StateError catch (e) {
                  _snack(e.message, error: true);
                } catch (e) {
                  _snack(
                      l10n.translate('room_change_failed', args: {'error': e}),
                      error: true);
                }
              },
      ),
    );
  }
}
