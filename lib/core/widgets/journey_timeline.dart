import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// 🗓️ Journey Timeline widget — shows all diary entries grouped by year/month.
/// Used on the Explorer Profile to visualize the user's travel history.
class JourneyTimelineWidget extends StatelessWidget {
  final List<JourneyEntry> entries;

  const JourneyTimelineWidget({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _EmptyTimeline();
    }

    // Group by year
    final Map<int, List<JourneyEntry>> byYear = {};
    for (final e in entries) {
      byYear.putIfAbsent(e.year, () => []).add(e);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TimelineHeader(
          totalDistricts: entries.map((e) => e.district).toSet().length,
          totalDays: entries.fold(0, (sum, e) => sum + (e.tripDays ?? 1)),
          totalSpent: entries.fold(0.0, (sum, e) => sum + e.totalSpent),
        ),
        const SizedBox(height: 20),
        ...years.map((year) => _YearSection(
              year: year,
              entries: byYear[year]!,
            )),
      ],
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  final int totalDistricts;
  final int totalDays;
  final double totalSpent;

  const _TimelineHeader({
    required this.totalDistricts,
    required this.totalDays,
    required this.totalSpent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatPill(
          emoji: '🗺️',
          value: '$totalDistricts',
          label: 'জেলা',
        ),
        const SizedBox(width: 12),
        _StatPill(
          emoji: '📅',
          value: '$totalDays',
          label: 'দিন',
        ),
        const SizedBox(width: 12),
        _StatPill(
          emoji: '💰',
          value: '৳${totalSpent.toStringAsFixed(0)}',
          label: 'মোট খরচ',
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;

  const _StatPill({required this.emoji, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _YearSection extends StatelessWidget {
  final int year;
  final List<JourneyEntry> entries;

  const _YearSection({required this.year, required this.entries});

  @override
  Widget build(BuildContext context) {
    // Sort by date descending within year
    final sorted = List<JourneyEntry>.from(entries)
      ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '$year',
            style: const TextStyle(
              color: AppColors.mintGreen,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        ...sorted.asMap().entries.map((entry) {
          final isLast = entry.key == sorted.length - 1;
          return _TimelineEntry(entry: entry.value, isLast: isLast);
        }),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final JourneyEntry entry;
  final bool isLast;

  const _TimelineEntry({required this.entry, required this.isLast});

  String get _monthLabel {
    const months = [
      'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
      'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
    ];
    return months[entry.date.month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline spine
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.mintGreen,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.white12,
                    ),
                  ),
              ],
            ),
          ),
          // Entry card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _monthLabel,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.destination,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (entry.tripDays != null) ...[
                        _Tag(text: '${entry.tripDays} দিন', icon: '📅'),
                        const SizedBox(width: 8),
                      ],
                      if (entry.totalSpent > 0)
                        _Tag(
                          text: '৳${entry.totalSpent.toStringAsFixed(0)}',
                          icon: '💰',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final String icon;
  const _Tag({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$icon $text',
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Text('🗓️', style: TextStyle(fontSize: 48)),
          SizedBox(height: 12),
          Text(
            'এখনো কোনো ভ্রমণ নেই',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'আপনার প্রথম ডায়েরি লিখুন!',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Data class for a single entry in the journey timeline.
class JourneyEntry {
  final String tripId;
  final String destination;
  final String district;
  final DateTime date;
  final int? tripDays;
  final double totalSpent;

  const JourneyEntry({
    required this.tripId,
    required this.destination,
    required this.district,
    required this.date,
    this.tripDays,
    this.totalSpent = 0.0,
  });

  int get year => date.year;
}
