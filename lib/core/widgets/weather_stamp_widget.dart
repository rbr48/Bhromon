import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../value_objects/weather_snapshot.dart';

/// 🌦️ Small weather pill shown at the top of a diary entry.
/// Auto-stamped when the user first saves a new diary entry.
class WeatherStampWidget extends StatelessWidget {
  final WeatherSnapshot weather;
  final bool compact;

  const WeatherStampWidget({
    super.key,
    required this.weather,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(weather.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            compact ? weather.shortDisplay : weather.fullDisplay,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!compact && !weather.isSafeToVisit) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠️ ভ্রমণে সতর্ক থাকুন',
                style: TextStyle(
                  color: AppColors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
