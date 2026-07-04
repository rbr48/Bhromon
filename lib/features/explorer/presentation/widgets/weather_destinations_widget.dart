import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/theme_context.dart';

class WeatherDestinationsWidget extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;

  const WeatherDestinationsWidget({super.key, required this.docs});

  @override
  Widget build(BuildContext context) {
    // 1. Extract top-3 most-visited districts from docs
    final Map<String, int> districtCounts = {};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final district = data['district'];
      if (district is String && district.isNotEmpty) {
        districtCounts[district] = (districtCounts[district] ?? 0) + 1;
      }
    }

    final sortedDistricts = districtCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top3 = sortedDistricts.take(3).map((e) => e.key).toList();

    // Fallback if no districts visited yet
    if (top3.isEmpty) {
      top3.addAll(['Dhaka', 'Cox\'s Bazar', 'Sylhet']);
    }

    final currentMonth = DateTime.now().month;

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
          const Row(
            children: [
              Icon(Icons.wb_sunny_outlined,
                  color: AppColors.mintGreen, size: 20),
              SizedBox(width: 8),
              Text(
                'DESTINATION WEATHER & SEASONAL TRIPS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: top3.map((district) {
                final info = _getSimulatedWeather(district, currentMonth);
                return _buildWeatherCard(context, district, info);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherCard(
      BuildContext context, String district, _DistrictWeatherInfo info) {
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            district,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(info.icon, color: info.iconColor, size: 28),
              const SizedBox(width: 8),
              Text(
                '${info.temp}°C',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            info.condition,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.mintGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BEST TIME TO VISIT',
                  style: TextStyle(
                    color: AppColors.mintGreen,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.bestTime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _DistrictWeatherInfo _getSimulatedWeather(String district, int month) {
    // Classify districts roughly
    final name = district.toLowerCase();
    final isHilly = name.contains('sylhet') ||
        name.contains('moulvibazar') ||
        name.contains('sunamganj') ||
        name.contains('bandarban') ||
        name.contains('rangamati') ||
        name.contains('khagrachhari') ||
        name.contains('netrokona');

    final isCoastal = name.contains('cox') ||
        name.contains('kuakata') ||
        name.contains('bagerhat') ||
        name.contains('patuakhali') ||
        name.contains('bhola') ||
        name.contains('chittagong') ||
        name.contains('noakhali');

    // Season determination in Bangladesh:
    // 6-8: Monsoon (Rainy)
    // 9-10: Autumn / Late Autumn (Warm/Wet transitions)
    // 11-2: Winter (Dry/Cool)
    // 3-5: Summer (Hot/Stormy)

    if (month >= 6 && month <= 8) {
      if (isHilly) {
        return _DistrictWeatherInfo(
          temp: 26 + (month % 3),
          condition: 'Monsoon Rain & Waterfalls',
          icon: Icons.umbrella,
          iconColor: Colors.lightBlueAccent,
          bestTime: 'Jun - Sep (Green Season)',
        );
      } else if (isCoastal) {
        return _DistrictWeatherInfo(
          temp: 28 + (month % 2),
          condition: 'Heavy Winds & Stormy Seas',
          icon: Icons.thunderstorm,
          iconColor: Colors.blueGrey,
          bestTime: 'Nov - Feb (Winter Beach)',
        );
      } else {
        return _DistrictWeatherInfo(
          temp: 31 + (month % 2),
          condition: 'Humid & Scattered Rain',
          icon: Icons.cloudy_snowing,
          iconColor: Colors.blue,
          bestTime: 'Nov - Feb (Cool Months)',
        );
      }
    } else if (month >= 11 || month <= 2) {
      // Winter
      if (isHilly) {
        return _DistrictWeatherInfo(
          temp: 14 + (month % 4),
          condition: 'Chilly Foggy Mornings',
          icon: Icons.ac_unit,
          iconColor: Colors.white,
          bestTime: 'Nov - Mar (Trekking)',
        );
      } else if (isCoastal) {
        return _DistrictWeatherInfo(
          temp: 20 + (month % 3),
          condition: 'Perfect Beach Breeze',
          icon: Icons.wb_sunny,
          iconColor: Colors.amber,
          bestTime: 'Nov - Feb (Peak Season)',
        );
      } else {
        return _DistrictWeatherInfo(
          temp: 17 + (month % 3),
          condition: 'Mild Cool & Sunny Days',
          icon: Icons.wb_cloudy_outlined,
          iconColor: Colors.yellow,
          bestTime: 'Nov - Feb (Festivals)',
        );
      }
    } else if (month >= 9 && month <= 10) {
      // Autumn
      return _DistrictWeatherInfo(
        temp: 29,
        condition: 'Clear Sky & Kashful',
        icon: Icons.wb_sunny_outlined,
        iconColor: Colors.cyanAccent,
        bestTime: 'Sep - Oct (Autumn Colors)',
      );
    } else {
      // Summer (Hot / Stormy)
      if (isHilly) {
        return _DistrictWeatherInfo(
          temp: 32,
          condition: 'Hot & Afternoon Kalboishakhi',
          icon: Icons.cyclone,
          iconColor: Colors.deepOrangeAccent,
          bestTime: 'Oct - Mar (Dry Weather)',
        );
      } else {
        return _DistrictWeatherInfo(
          temp: 34,
          condition: 'Intense Heat & Sun',
          icon: Icons.wb_sunny,
          iconColor: Colors.orange,
          bestTime: 'Dec - Feb (Pleasant Temp)',
        );
      }
    }
  }
}

class _DistrictWeatherInfo {
  final int temp;
  final String condition;
  final IconData icon;
  final Color iconColor;
  final String bestTime;

  _DistrictWeatherInfo({
    required this.temp,
    required this.condition,
    required this.icon,
    required this.iconColor,
    required this.bestTime,
  });
}
