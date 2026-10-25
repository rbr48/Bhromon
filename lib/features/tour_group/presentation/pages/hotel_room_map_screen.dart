import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/tour_group.dart';

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
  TourRole? _myRole;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;

  @override
  void initState() {
    super.initState();
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    });
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<List<HotelRoom>>(
      stream: _rooms,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return const Center(
            child: Text('রুমের তথ্য দেখা যাচ্ছে না।',
                style: TextStyle(color: Colors.white54)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.midGreen));
        }
        final rooms = snapshot.data!;
        if (rooms.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hotel_rounded,
                    size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                const Text('এখনও কোনো রুম যোগ করা হয়নি।',
                    style: TextStyle(color: Colors.white70)),
                if (_isAdmin) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showRoomDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('প্রথম রুম যোগ করুন'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.midGreen),
                  ),
                ],
              ],
            ),
          );
        }

        final capacity = rooms.fold<int>(0, (sum, r) => sum + r.capacity);
        final assigned =
            rooms.fold<int>(0, (sum, r) => sum + r.assignedMemberEmails.length);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF14241B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('রুম: ${rooms.length}',
                      style: const TextStyle(color: Colors.white70)),
                  Text('বরাদ্দ: $assigned / $capacity জন',
                      style: const TextStyle(
                          color: AppColors.gold, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final room in rooms) _roomCard(room),
          ],
        );
      },
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: const Text(
          'Hotel Rooms (হোটেল রুম)',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.add_home_work_rounded,
                  color: AppColors.mintGreen),
              tooltip: 'রুম যোগ করুন',
              onPressed: () => _showRoomDialog(),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _roomCard(HotelRoom room) {
    final full = room.isFull;
    return GestureDetector(
      onTap: () => _showGuestSheet(room.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF14241B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: full
                  ? Colors.redAccent.withValues(alpha: 0.4)
                  : Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.midGreen.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('রুম ${room.roomNumber}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(room.title.isEmpty ? 'রুম' : room.title,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                if (_isAdmin)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: Colors.white54, size: 18),
                    color: const Color(0xFF1B4332),
                    onSelected: (v) {
                      if (v == 'edit') _showRoomDialog(existing: room);
                      if (v == 'delete') _deleteRoom(room);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('রুম বদলান')),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text('রুম মুছুন',
                              style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'তলা ${room.floor} • ${room.isAc ? 'AC' : 'নন-AC'}'
              '${room.hasSeaView ? ' • সমুদ্র দৃশ্য' : ''} • ${room.assignedMemberEmails.length} / ${room.capacity} জন',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 8),
            if (room.assignedMemberEmails.isEmpty)
              const Text('কেউ বরাদ্দ পাননি — ট্যাপ করে যোগ করুন',
                  style: TextStyle(color: Colors.white38, fontSize: 12))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < room.assignedMemberEmails.length; i++)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor:
                          AppColors.midGreen.withValues(alpha: 0.25),
                      label: Text(
                        i < room.assignedMemberNames.length &&
                                room.assignedMemberNames[i].isNotEmpty
                            ? room.assignedMemberNames[i]
                            : 'সদস্য',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRoom(HotelRoom room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title: Text('রুম ${room.roomNumber} মুছবেন?',
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('না')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('মুছুন',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteHotelRoom(widget.tourId, room.id);
    } catch (e) {
      _showError('রুম মোছা যায়নি: $e');
    }
  }

  void _showRoomDialog({HotelRoom? existing}) {
    final numberCtrl = TextEditingController(text: existing?.roomNumber ?? '');
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final floorCtrl = TextEditingController(text: '${existing?.floor ?? 1}');
    int capacity = existing?.capacity ?? 2;
    bool isAc = existing?.isAc ?? true;
    bool hasSeaView = existing?.hasSeaView ?? false;
    String? error;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF14241B),
          title: Text(existing == null ? 'নতুন রুম যোগ করুন' : 'রুম বদলান',
              style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numberCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'রুম নম্বর'),
                ),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      labelText: 'রুমের ধরন (যেমন: Deluxe)'),
                ),
                DropdownButtonFormField<int>(
                  initialValue: capacity,
                  dropdownColor: const Color(0xFF1B4332),
                  decoration: const InputDecoration(labelText: 'কতজন থাকবেন'),
                  items: [
                    for (var c = 1; c <= 6; c++)
                      DropdownMenuItem(value: c, child: Text('$c জন')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => capacity = v);
                  },
                ),
                TextField(
                  controller: floorCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'তলা'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title:
                      const Text('AC', style: TextStyle(color: Colors.white)),
                  value: isAc,
                  activeThumbColor: AppColors.mintGreen,
                  onChanged: (v) => setDialogState(() => isAc = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('সমুদ্র দৃশ্য',
                      style: TextStyle(color: Colors.white)),
                  value: hasSeaView,
                  activeThumbColor: AppColors.gold,
                  onChanged: (v) => setDialogState(() => hasSeaView = v),
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
                child: const Text('বাতিল')),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: () async {
                final number = numberCtrl.text.trim();
                final floor = int.tryParse(floorCtrl.text.trim());
                if (number.isEmpty) {
                  setDialogState(() => error = 'রুম নম্বর লিখুন।');
                  return;
                }
                if (floor == null || floor < 0 || floor > 200) {
                  setDialogState(() => error = 'সঠিক তলা লিখুন।');
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
                  assignedMemberEmails:
                      existing?.assignedMemberEmails ?? const [],
                  assignedMemberNames:
                      existing?.assignedMemberNames ?? const [],
                );
                // Shrinking capacity below the current guests is refused.
                if (room.assignedMemberEmails.length > room.capacity) {
                  setDialogState(() => error =
                      'এখানে ${room.assignedMemberEmails.length} জন আছেন, তাই ধারণক্ষমতা কমানো যাবে না।');
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await _repository.saveHotelRoom(widget.tourId, room);
                } catch (e) {
                  _showError(
                      'রুম সংরক্ষণ করা যায়নি: শুধু অ্যাডমিন রুম যোগ বা বদলাতে পারবেন।');
                }
              },
              child:
                  const Text('সংরক্ষণ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      numberCtrl.dispose();
      titleCtrl.dispose();
      floorCtrl.dispose();
    });
  }

  /// Guest list for one room, read live so it always shows the current state.
  void _showGuestSheet(String roomId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: const Color(0xFF14241B),
      builder: (ctx) {
        return StreamBuilder<List<HotelRoom>>(
          stream: _rooms,
          builder: (context, roomSnap) {
            final room = (roomSnap.data ?? const <HotelRoom>[])
                .where((r) => r.id == roomId)
                .firstOrNull;
            if (room == null) {
              return const SizedBox(
                  height: 120,
                  child: Center(
                      child: Text('রুমটি আর পাওয়া যাচ্ছে না।',
                          style: TextStyle(color: Colors.white54))));
            }
            return StreamBuilder<List<TourMember>>(
              stream: _repository.watchMembers(widget.tourId),
              builder: (context, memberSnap) {
                final members = memberSnap.data ?? const <TourMember>[];
                return SafeArea(
                  child: SizedBox(
                    height: MediaQuery.of(ctx).size.height * 0.7,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'রুম ${room.roomNumber} — ${room.assignedMemberEmails.length} / ${room.capacity} জন',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                          const Divider(color: Colors.white12),
                          Expanded(
                            child: ListView(
                              children: [
                                for (final m in members) _guestTile(room, m),
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
      },
    );
  }

  Widget _guestTile(HotelRoom room, TourMember m) {
    final here = room.hasGuest(m.email);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.midGreen,
        child: Text(m.displayName.isNotEmpty ? m.displayName[0] : 'G',
            style: const TextStyle(color: Colors.white)),
      ),
      title: Text(m.displayName, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        here
            ? 'এই রুমে'
            : (room.isFull
                ? 'রুমটি পূর্ণ'
                : 'যোগ করলে আগের রুম থেকে সরে আসবেন'),
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: IconButton(
        icon: Icon(here ? Icons.remove_circle : Icons.add_circle,
            color: here
                ? Colors.redAccent
                : (room.isFull ? Colors.white24 : AppColors.mintGreen)),
        onPressed: !here && room.isFull
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
                  _showError(e.message);
                } catch (e) {
                  _showError('বরাদ্দ বদলানো যায়নি: $e');
                }
              },
      ),
    );
  }
}
