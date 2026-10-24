import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import '../../../../core/theme/colors.dart';

class BusSeatMapScreen extends StatefulWidget {
  final String tourId;

  const BusSeatMapScreen({super.key, required this.tourId});

  @override
  State<BusSeatMapScreen> createState() => _BusSeatMapScreenState();
}

class _BusSeatMapScreenState extends State<BusSeatMapScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Standard 36-seater tourist coach layout: Rows A through I (4 seats each)
  static final List<String> _seatLabels = [
    'A1', 'A2', 'A3', 'A4',
    'B1', 'B2', 'B3', 'B4',
    'C1', 'C2', 'C3', 'C4',
    'D1', 'D2', 'D3', 'D4',
    'E1', 'E2', 'E3', 'E4',
    'F1', 'F2', 'F3', 'F4',
    'G1', 'G2', 'G3', 'G4',
    'H1', 'H2', 'H3', 'H4',
    'I1', 'I2', 'I3', 'I4',
  ];

  @override
  Widget build(BuildContext context) {
    final seatCollection = _firestore
        .collection('tours')
        .doc(widget.tourId)
        .collection('bus_seats');

    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: const Text(
          'Bus Seat Allocator (বাসের সিট)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: seatCollection.snapshots(),
        builder: (context, snapshot) {
          final seatData = <String, BusSeat>{};
          if (snapshot.hasData) {
            for (final doc in snapshot.data!.docs) {
              final seat = BusSeat.fromMap(doc.data());
              seatData[seat.seatNumber] = seat;
            }
          }

          int occupiedCount = seatData.values.where((s) => s.isOccupied).length;

          return Column(
            children: [
              // Statistics Banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF14241B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildLegendItem('Available', Colors.white24),
                    _buildLegendItem('Occupied', AppColors.mintGreen),
                    Text(
                      'Booked: $occupiedCount / ${_seatLabels.length}',
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),

              // Bus Cabin Frame
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14241B),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      // Driver & Door Front Row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.directions_bus_rounded, color: AppColors.mintGreen, size: 16),
                                  SizedBox(width: 6),
                                  Text('DOOR (দরজা)', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.sports_motorsports_rounded, color: AppColors.gold, size: 16),
                                  SizedBox(width: 6),
                                  Text('DRIVER', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 16),

                      // Seat Rows
                      Expanded(
                        child: ListView.builder(
                          itemCount: _seatLabels.length ~/ 4,
                          itemBuilder: (context, rowIndex) {
                            final i = rowIndex * 4;
                            final s1 = seatData[_seatLabels[i]] ?? BusSeat(seatNumber: _seatLabels[i], isWindow: true);
                            final s2 = seatData[_seatLabels[i + 1]] ?? BusSeat(seatNumber: _seatLabels[i + 1]);
                            final s3 = seatData[_seatLabels[i + 2]] ?? BusSeat(seatNumber: _seatLabels[i + 2]);
                            final s4 = seatData[_seatLabels[i + 3]] ?? BusSeat(seatNumber: _seatLabels[i + 3], isWindow: true);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  // Left Pair
                                  Expanded(child: _buildSeatCard(s1)),
                                  const SizedBox(width: 6),
                                  Expanded(child: _buildSeatCard(s2)),

                                  // Central Aisle
                                  const SizedBox(
                                    width: 32,
                                    child: Center(
                                      child: Text(
                                        '│',
                                        style: TextStyle(color: Colors.white12, fontSize: 14),
                                      ),
                                    ),
                                  ),

                                  // Right Pair
                                  Expanded(child: _buildSeatCard(s3)),
                                  const SizedBox(width: 6),
                                  Expanded(child: _buildSeatCard(s4)),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _buildSeatCard(BusSeat seat) {
    final isOccupied = seat.isOccupied;

    return GestureDetector(
      onTap: () => _showSeatAssignmentSheet(context, seat),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isOccupied
              ? AppColors.midGreen.withValues(alpha: 0.35)
              : Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isOccupied
                ? AppColors.mintGreen
                : Colors.white.withValues(alpha: 0.1),
            width: isOccupied ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.airline_seat_recline_normal_rounded,
                  size: 14,
                  color: isOccupied ? AppColors.mintGreen : Colors.white38,
                ),
                const SizedBox(width: 2),
                Text(
                  seat.seatNumber,
                  style: TextStyle(
                    color: isOccupied ? AppColors.mintGreen : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              isOccupied ? (seat.assignedMemberName ?? 'Booked') : 'Empty',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isOccupied ? Colors.white : Colors.white24,
                fontSize: 10,
                fontWeight: isOccupied ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSeatAssignmentSheet(BuildContext context, BusSeat seat) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14241B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StreamBuilder<List<TourMember>>(
          stream: _repository.watchMembers(widget.tourId),
          builder: (context, snapshot) {
            final members = snapshot.data ?? [];

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Seat ${seat.seatNumber} Assignment',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        if (seat.isOccupied)
                          TextButton.icon(
                            icon: const Icon(Icons.clear, color: Colors.redAccent, size: 16),
                            label: const Text('Vacate Seat', style: TextStyle(color: Colors.redAccent)),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _firestore
                                  .collection('tours')
                                  .doc(widget.tourId)
                                  .collection('bus_seats')
                                  .doc(seat.seatNumber)
                                  .delete();
                            },
                          ),
                      ],
                    ),
                    const Divider(color: Colors.white12),
                    const Text(
                      'Select passenger for this seat:',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: members.length,
                        itemBuilder: (context, i) {
                          final m = members[i];
                          final isAssigned = seat.assignedMemberEmail == m.email;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.midGreen,
                              child: Text(m.displayName.isNotEmpty ? m.displayName[0] : 'P'),
                            ),
                            title: Text(m.displayName, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(m.email, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            trailing: isAssigned
                                ? const Icon(Icons.check_circle, color: AppColors.mintGreen)
                                : null,
                            onTap: () async {
                              Navigator.pop(ctx);
                              final updated = seat.copyWith(
                                assignedMemberEmail: m.email,
                                assignedMemberName: m.displayName,
                              );
                              await _firestore
                                  .collection('tours')
                                  .doc(widget.tourId)
                                  .collection('bus_seats')
                                  .doc(seat.seatNumber)
                                  .set(updated.toMap());
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
