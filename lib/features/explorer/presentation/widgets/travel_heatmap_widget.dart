import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/theme_context.dart';

class TravelHeatmapWidget extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;

  const TravelHeatmapWidget({super.key, required this.docs});

  @override
  Widget build(BuildContext context) {
    // Build a map: date-string -> count
    final Map<String, int> activityMap = {};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final raw = data['lastConfirmed'] ?? data['publishedAt'];
      DateTime? dt;
      if (raw is Timestamp) {
        dt = raw.toDate();
      }
      if (dt == null) continue;
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      activityMap[key] = (activityMap[key] ?? 0) + 1;
    }

    final today = DateTime.now();
    // Start from 52 weeks ago, on Sunday
    final startDate = today.subtract(const Duration(days: 364));
    final startWeekday = startDate.weekday % 7; // 0=Sun
    final gridStart = startDate.subtract(Duration(days: startWeekday));

    // Build 53 columns x 7 rows
    final List<List<DateTime?>> weeks = [];
    DateTime cursor = gridStart;
    while (cursor.isBefore(today.add(const Duration(days: 1)))) {
      final List<DateTime?> week = [];
      for (int d = 0; d < 7; d++) {
        if (cursor.isBefore(gridStart) || cursor.isAfter(today)) {
          week.add(null);
        } else {
          week.add(cursor);
        }
        cursor = cursor.add(const Duration(days: 1));
      }
      weeks.add(week);
    }

    final maxVal = activityMap.values.fold(0, (m, v) => v > m ? v : m);

    Color cellColor(DateTime? dt) {
      if (dt == null) return Colors.transparent;
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final count = activityMap[key] ?? 0;
      if (count == 0) return Colors.white.withValues(alpha: 0.05);
      final intensity = maxVal > 0 ? count / maxVal : 0.0;
      return Color.lerp(
        AppColors.mintGreen.withValues(alpha: 0.2),
        AppColors.mintGreen,
        intensity,
      )!;
    }

    final months = <String>[];
    final monthPositions = <int>[];
    String lastMonth = '';
    for (int i = 0; i < weeks.length; i++) {
      final day = weeks[i].firstWhere((d) => d != null, orElse: () => null);
      if (day != null) {
        final monthStr = _monthAbbr(day.month);
        if (monthStr != lastMonth) {
          months.add(monthStr);
          monthPositions.add(i);
          lastMonth = monthStr;
        }
      }
    }

    final totalLogs = docs.length;
    final activeDays = activityMap.keys.length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TRAVEL ACTIVITY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                '$totalLogs logs · $activeDays active days',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Month labels
                SizedBox(
                  height: 14,
                  child: Row(
                    children: List.generate(weeks.length, (i) {
                      final idx = monthPositions.indexOf(i);
                      return SizedBox(
                        width: 11,
                        child: idx >= 0
                            ? Text(
                                months[idx],
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 7,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 4),
                // Grid
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: weeks.map((week) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Column(
                        children: week.map((dt) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: GestureDetector(
                              onTap: dt == null
                                  ? null
                                  : () {
                                      final key =
                                          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                                      final count = activityMap[key] ?? 0;
                                      if (count > 0) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '$count log${count > 1 ? 's' : ''} on ${dt.day}/${dt.month}/${dt.year}',
                                            ),
                                            duration:
                                                const Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    },
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: cellColor(dt),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Less',
                style: TextStyle(color: Colors.white54, fontSize: 9),
              ),
              const SizedBox(width: 4),
              ...List.generate(5, (i) {
                return Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: i == 0
                        ? Colors.white.withValues(alpha: 0.05)
                        : AppColors.mintGreen.withValues(alpha: 0.2 * i),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
              const SizedBox(width: 4),
              const Text(
                'More',
                style: TextStyle(color: Colors.white54, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _monthAbbr(int month) {
    const abbrs = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return abbrs[month - 1];
  }
}
