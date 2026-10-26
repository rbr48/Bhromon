import 'package:flutter/material.dart';

import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/domain/services/tide_schedule_engine.dart';
import 'package:bhromon/features/tour_group/presentation/pages/family_safety_hub_screen.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Live Beach Tide & Ocean Safety pill banner shown at the top of InstaFeed.
class InstafeedTideBanner extends StatelessWidget {
  final VoidCallback? onTap;

  const InstafeedTideBanner({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final minutesNow = now.hour * 60 + now.minute;
    final tides = TideScheduleEngine.getTidesForDate(now);

    TideWindow? current;
    for (final t in tides) {
      if (t.contains(minutesNow)) {
        current = t;
        break;
      }
    }

    final isHighTide = current?.type == TideType.high;
    final title = current?.name ?? 'সমুদ্র নিরাপত্তা ও জোয়ার-ভাটা তথ্য';
    final subtitle = isHighTide
        ? context.l10n.translate('ig_tide_high_banner')
        : context.l10n.translate('ig_tide_low_banner');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isHighTide
            ? const Color(0xFF004D40).withValues(alpha: 0.85)
            : const Color(0xFF3E2723).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighTide ? Colors.tealAccent.shade400 : Colors.orangeAccent,
          width: 0.8,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              isHighTide ? Icons.waves : Icons.warning_amber_rounded,
              color: isHighTide ? Colors.tealAccent : Colors.orangeAccent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color:
                          isHighTide ? Colors.tealAccent : Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 18),
          ],
        ),
      ),
    );
  }
}

/// High-visibility emergency SOS banner pinned to top of feed when active.
class InstafeedSosBanner extends StatelessWidget {
  final String tourId;
  final SafetyAlert alert;

  const InstafeedSosBanner({
    super.key,
    required this.tourId,
    required this.alert,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFB71C1C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.redAccent,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.emergency_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.translate('ig_sos_banner',
                      args: {'name': alert.senderName}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  context.l10n.translate('ig_sos_help'),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => FamilySafetyHubScreen(tourId: tourId),
                ),
              );
            },
            child: Text(
              context.l10n.translate('ig_view'),
              style: const TextStyle(
                color: Color(0xFFB71C1C),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog showing author's real-world logistics: Coach Seat, Hotel Room, Family Count.
class InstafeedMemberLogisticsDialog extends StatelessWidget {
  final String authorName;
  final String authorEmail;
  final String? authorPhoto;
  final String? seatNumber;
  final String? roomNumber;
  final int? familyCount;

  const InstafeedMemberLogisticsDialog({
    super.key,
    required this.authorName,
    required this.authorEmail,
    this.authorPhoto,
    this.seatNumber,
    this.roomNumber,
    this.familyCount,
  });

  static Future<void> show(
    BuildContext context, {
    required String authorName,
    required String authorEmail,
    String? authorPhoto,
    String? seatNumber,
    String? roomNumber,
    int? familyCount,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => InstafeedMemberLogisticsDialog(
        authorName: authorName,
        authorEmail: authorEmail,
        authorPhoto: authorPhoto,
        seatNumber: seatNumber,
        roomNumber: roomNumber,
        familyCount: familyCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.mintGreen,
            backgroundImage:
                authorPhoto != null ? NetworkImage(authorPhoto!) : null,
            child: authorPhoto == null
                ? Text(
                    authorName.isNotEmpty ? authorName[0].toUpperCase() : 'M',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  authorEmail,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(color: Colors.white10),
          _buildInfoRow(
            icon: Icons.directions_bus,
            label: context.l10n.translate('ig_bus_seat_label'),
            value: seatNumber != null && seatNumber!.isNotEmpty
                ? context.l10n
                    .translate('ig_seat_number', args: {'seat': '$seatNumber'})
                : context.l10n.translate('ig_not_assigned'),
            valueColor:
                seatNumber != null ? AppColors.mintGreen : Colors.white54,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.hotel,
            label: context.l10n.translate('ig_hotel_room_label'),
            value: roomNumber != null && roomNumber!.isNotEmpty
                ? context.l10n
                    .translate('ig_room_number', args: {'room': '$roomNumber'})
                : context.l10n.translate('ig_not_assigned'),
            valueColor:
                roomNumber != null ? Colors.amberAccent : Colors.white54,
          ),
          if (familyCount != null && familyCount! > 1) ...[
            const SizedBox(height: 10),
            _buildInfoRow(
              icon: Icons.family_restroom,
              label: context.l10n.translate('ig_family_members'),
              value: context.l10n.translate('ig_people_count',
                  args: {'count': '$familyCount'}),
              valueColor: Colors.lightBlueAccent,
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.mintGreen,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.translate('ig_ok')),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
