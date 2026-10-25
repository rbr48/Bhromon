import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/tour_group.dart';

class BusSeatMapScreen extends StatefulWidget {
  final String tourId;

  /// When true, only the body is built (used inside the logistics tabs).
  final bool embedded;

  const BusSeatMapScreen(
      {super.key, required this.tourId, this.embedded = false});

  @override
  State<BusSeatMapScreen> createState() => _BusSeatMapScreenState();
}

class _BusSeatMapScreenState extends State<BusSeatMapScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<BusSeat>> _seats =
      _repository.watchBusSeats(widget.tourId);

  // Standard 36-seater tourist coach: rows A to I, four seats each.
  static final List<String> _seatLabels = [
    for (final row in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'])
      for (final col in ['1', '2', '3', '4']) '$row$col',
  ];

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _assign(String seatNumber, {String? email, String? name}) async {
    try {
      await _repository.assignBusSeat(widget.tourId, seatNumber,
          email: email, name: name);
    } catch (e) {
      _showError('সিট বদলানো যায়নি: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<List<BusSeat>>(
      stream: _seats,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'সিটের তথ্য দেখা যাচ্ছে না। আপনি এই ট্যুরের সদস্য কি না দেখুন।',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.midGreen),
          );
        }
        final byNumber = {for (final s in snapshot.data!) s.seatNumber: s};
        final booked = byNumber.values.where((s) => s.isOccupied).length;

        return Column(
          children: [
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
                  _legend('খালি', Colors.white24),
                  _legend('বুকড', AppColors.mintGreen),
                  Text('বুকড: $booked / ${_seatLabels.length}',
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF14241B),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: AppColors.mintGreen.withValues(alpha: 0.3),
                      width: 1.5),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _CabinTag(
                            icon: Icons.directions_bus_rounded,
                            label: 'DOOR (দরজা)'),
                        _CabinTag(
                            icon: Icons.sports_motorsports_rounded,
                            label: 'DRIVER'),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _seatLabels.length ~/ 4,
                        itemBuilder: (context, row) {
                          final i = row * 4;
                          BusSeat seatAt(int k) =>
                              byNumber[_seatLabels[k]] ??
                              BusSeat(seatNumber: _seatLabels[k]);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Expanded(child: _seatCard(seatAt(i))),
                                const SizedBox(width: 6),
                                Expanded(child: _seatCard(seatAt(i + 1))),
                                const SizedBox(
                                  width: 32,
                                  child: Center(
                                    child: Text('│',
                                        style: TextStyle(
                                            color: Colors.white12,
                                            fontSize: 14)),
                                  ),
                                ),
                                Expanded(child: _seatCard(seatAt(i + 2))),
                                const SizedBox(width: 6),
                                Expanded(child: _seatCard(seatAt(i + 3))),
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
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: const Text(
          'Bus Seat Allocator (বাসের সিট)',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: body,
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _seatCard(BusSeat seat) {
    final occupied = seat.isOccupied;
    return GestureDetector(
      onTap: () => _showSeatSheet(seat),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: occupied
              ? AppColors.midGreen.withValues(alpha: 0.35)
              : Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: occupied
                ? AppColors.mintGreen
                : Colors.white.withValues(alpha: 0.1),
            width: occupied ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.airline_seat_recline_normal_rounded,
                    size: 14,
                    color: occupied ? AppColors.mintGreen : Colors.white38),
                const SizedBox(width: 2),
                Text(
                  seat.seatNumber,
                  style: TextStyle(
                    color: occupied ? AppColors.mintGreen : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              occupied ? (seat.assignedMemberName ?? 'বুকড') : 'খালি',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: occupied ? Colors.white : Colors.white24,
                fontSize: 10,
                fontWeight: occupied ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSeatSheet(BusSeat seat) {
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
            final members = snapshot.data ?? const <TourMember>[];
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(ctx).padding.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('সিট ${seat.seatNumber}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        if (seat.isOccupied)
                          TextButton.icon(
                            icon: const Icon(Icons.clear,
                                color: Colors.redAccent, size: 16),
                            label: const Text('সিট খালি করুন',
                                style: TextStyle(color: Colors.redAccent)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _assign(seat.seatNumber);
                            },
                          ),
                      ],
                    ),
                    const Divider(color: Colors.white12),
                    const Text('যাত্রী বাছাই করুন:',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: members.length,
                        itemBuilder: (context, i) {
                          final m = members[i];
                          final isHere = seat.assignedMemberEmail == m.email;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.midGreen,
                              child: Text(
                                m.displayName.isNotEmpty
                                    ? m.displayName[0]
                                    : 'P',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(m.displayName,
                                style: const TextStyle(color: Colors.white)),
                            subtitle: Text(
                              isHere
                                  ? 'এই সিটে'
                                  : 'অন্য সিট বাছাই করলে এখানকার সিট ছেড়ে দেওয়া হবে',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                            trailing: isHere
                                ? const Icon(Icons.check_circle,
                                    color: AppColors.mintGreen)
                                : null,
                            onTap: isHere
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    _assign(seat.seatNumber,
                                        email: m.email, name: m.displayName);
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

class _CabinTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CabinTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.mintGreen, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
