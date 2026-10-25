import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import '../../../../core/theme/colors.dart';

class HotelRoomMapScreen extends StatefulWidget {
  final String tourId;

  const HotelRoomMapScreen({super.key, required this.tourId});

  @override
  State<HotelRoomMapScreen> createState() => _HotelRoomMapScreenState();
}

class _HotelRoomMapScreenState extends State<HotelRoomMapScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  @override
  Widget build(BuildContext context) {
    final roomCollection = _firestore
        .collection('tours')
        .doc(widget.tourId)
        .collection('hotel_rooms');

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
          IconButton(
            icon: const Icon(Icons.add_home_work_rounded,
                color: AppColors.mintGreen),
            tooltip: 'Add Room',
            onPressed: () => _showAddRoomDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: roomCollection.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.midGreen));
          }

          final rooms = snapshot.data!.docs
              .map((d) => HotelRoom.fromMap(d.id, d.data()))
              .toList();

          if (rooms.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.hotel_rounded,
                      size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text('No hotel rooms configured yet.',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAddRoomDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Room'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.midGreen),
                  ),
                ],
              ),
            );
          }

          int totalCapacity = rooms.fold(0, (acc, r) => acc + r.capacity);
          int assignedCount =
              rooms.fold(0, (acc, r) => acc + r.assignedMemberEmails.length);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary Banner
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF14241B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('Total Rooms', '${rooms.length}'),
                    _buildStat('Total Beds', '$totalCapacity'),
                    _buildStat(
                        'Assigned Guests', '$assignedCount / $totalCapacity',
                        color: AppColors.mintGreen),
                  ],
                ),
              ),

              // Room Cards
              ...rooms.map((room) => _buildRoomCard(context, room)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStat(String label, String value, {Color color = Colors.white}) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildRoomCard(BuildContext context, HotelRoom room) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: room.isFull
              ? AppColors.mintGreen.withValues(alpha: 0.3)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.midGreen.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Room ${room.roomNumber}',
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    room.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                ],
              ),
              Row(
                children: [
                  if (room.isAc)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.ac_unit_rounded,
                          size: 16, color: Color(0xFF38BDF8)),
                    ),
                  if (room.hasSeaView)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.waves_rounded,
                          size: 16, color: AppColors.gold),
                    ),
                  Text(
                    'Floor ${room.floor}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Capacity and Assigned Members
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Occupancy: ${room.assignedMemberEmails.length} / ${room.capacity}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              TextButton(
                onPressed: () => _showManageRoomGuestsSheet(context, room),
                child: const Text('Manage Guests',
                    style: TextStyle(color: AppColors.mintGreen, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Assigned Member Badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (int i = 0; i < room.assignedMemberNames.length; i++)
                Chip(
                  backgroundColor: AppColors.midGreen.withValues(alpha: 0.2),
                  avatar: CircleAvatar(
                    backgroundColor: AppColors.midGreen,
                    child: Text(room.assignedMemberNames[i].isNotEmpty
                        ? room.assignedMemberNames[i][0]
                        : 'G'),
                  ),
                  label: Text(room.assignedMemberNames[i],
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              for (int i = 0; i < room.availableSlots; i++)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white12, style: BorderStyle.solid),
                  ),
                  child: const Text('Empty Bed',
                      style: TextStyle(color: Colors.white30, fontSize: 11)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddRoomDialog(BuildContext context) {
    final numberCtrl = TextEditingController();
    final titleCtrl = TextEditingController(text: 'Standard Double Room');
    int capacity = 2;
    int floor = 2;
    bool isAc = true;
    bool hasSeaView = false;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF14241B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: const Text('Add Hotel Room',
                  style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: numberCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Room Number (e.g. 201)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Room Name / Category',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: capacity,
                            dropdownColor: const Color(0xFF1B4332),
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                                labelText: 'Beds / Capacity'),
                            items: [1, 2, 3, 4, 5, 6]
                                .map((c) => DropdownMenuItem(
                                    value: c, child: Text('$c Persons')))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => capacity = val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: floor,
                            dropdownColor: const Color(0xFF1B4332),
                            style: const TextStyle(color: Colors.white),
                            decoration:
                                const InputDecoration(labelText: 'Floor'),
                            items: [1, 2, 3, 4, 5, 6, 7]
                                .map((f) => DropdownMenuItem(
                                    value: f, child: Text('Floor $f')))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => floor = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Air Conditioned (AC)',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: isAc,
                      activeThumbColor: AppColors.mintGreen,
                      onChanged: (val) => setDialogState(() => isAc = val),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sea View Balcony',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: hasSeaView,
                      activeThumbColor: AppColors.gold,
                      onChanged: (val) =>
                          setDialogState(() => hasSeaView = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.midGreen),
                  onPressed: () async {
                    final num = numberCtrl.text.trim();
                    if (num.isEmpty) return;

                    Navigator.pop(ctx);
                    final roomId = _uuid.v4();
                    final room = HotelRoom(
                      id: roomId,
                      roomNumber: num,
                      title: titleCtrl.text.trim(),
                      capacity: capacity,
                      floor: floor,
                      isAc: isAc,
                      hasSeaView: hasSeaView,
                    );

                    await _firestore
                        .collection('tours')
                        .doc(widget.tourId)
                        .collection('hotel_rooms')
                        .doc(roomId)
                        .set(room.toMap());
                  },
                  child: const Text('Add Room',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showManageRoomGuestsSheet(BuildContext context, HotelRoom room) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: const Color(0xFF14241B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StreamBuilder<List<TourMember>>(
          stream: _repository.watchMembers(widget.tourId),
          builder: (context, snapshot) {
            final members = snapshot.data ?? [];
            final bottomPad = MediaQuery.of(ctx).padding.bottom;

            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: bottomPad + 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Room ${room.roomNumber} Guests (${room.assignedMemberEmails.length}/${room.capacity})',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                      const Divider(color: Colors.white12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: members.length,
                          itemBuilder: (context, i) {
                            final m = members[i];
                            final isAssigned =
                                room.assignedMemberEmails.contains(m.email);

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.midGreen,
                                child: Text(m.displayName.isNotEmpty
                                    ? m.displayName[0]
                                    : 'G'),
                              ),
                              title: Text(m.displayName,
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: Text(m.email,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                              trailing: isAssigned
                                  ? IconButton(
                                      icon: const Icon(Icons.remove_circle,
                                          color: Colors.redAccent),
                                      onPressed: () async {
                                        final updatedEmails = List<String>.from(
                                            room.assignedMemberEmails)
                                          ..remove(m.email);
                                        final updatedNames = List<String>.from(
                                            room.assignedMemberNames)
                                          ..remove(m.displayName);

                                        await _firestore
                                            .collection('tours')
                                            .doc(widget.tourId)
                                            .collection('hotel_rooms')
                                            .doc(room.id)
                                            .update({
                                          'assignedMemberEmails': updatedEmails,
                                          'assignedMemberNames': updatedNames,
                                        });
                                      },
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.add_circle,
                                          color: AppColors.mintGreen),
                                      onPressed: room.isFull
                                          ? null
                                          : () async {
                                              final updatedEmails =
                                                  List<String>.from(
                                                      room.assignedMemberEmails)
                                                    ..add(m.email);
                                              final updatedNames =
                                                  List<String>.from(
                                                      room.assignedMemberNames)
                                                    ..add(m.displayName);

                                              await _firestore
                                                  .collection('tours')
                                                  .doc(widget.tourId)
                                                  .collection('hotel_rooms')
                                                  .doc(room.id)
                                                  .update({
                                                'assignedMemberEmails':
                                                    updatedEmails,
                                                'assignedMemberNames':
                                                    updatedNames,
                                              });
                                            },
                                    ),
                            );
                          },
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
}
