import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/weather_service.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/theme_context.dart';

/// Live weather for the user's top visited districts.
///
/// Temperatures come from the real Open-Meteo API via [WeatherService] —
/// never simulated. The "best time to visit" advice is static seasonal
/// domain knowledge and is shown even when live weather is unavailable.
class WeatherDestinationsWidget extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;

  const WeatherDestinationsWidget({super.key, required this.docs});

  @override
  State<WeatherDestinationsWidget> createState() =>
      _WeatherDestinationsWidgetState();
}

class _WeatherDestinationsWidgetState extends State<WeatherDestinationsWidget> {
  List<String> _top3 = [];
  final Map<String, WeatherData?> _live = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant WeatherDestinationsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newTop3 = _computeTop3();
    if (newTop3.join('|') != _top3.join('|')) _refresh();
  }

  List<String> _computeTop3() {
    final Map<String, int> districtCounts = {};
    for (final doc in widget.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final district = data['district'];
      if (district is String && district.isNotEmpty) {
        districtCounts[district] = (districtCounts[district] ?? 0) + 1;
      }
    }
    final sorted = districtCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = sorted.take(3).map((e) => e.key).toList();
    if (top3.isEmpty) top3.addAll(['Dhaka', "Cox's Bazar", 'Sylhet']);
    return top3;
  }

  Future<void> _refresh() async {
    _top3 = _computeTop3();
    setState(() => _loading = true);
    await Future.wait(_top3.map((district) async {
      final coords = _districtCoords(district);
      _live[district] = coords == null
          ? null
          : await WeatherService.getCurrentWeather(coords.$1, coords.$2);
    }));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
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
              children: _top3.map((district) {
                return _buildWeatherCard(context, district, currentMonth);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherCard(BuildContext context, String district, int month) {
    final WeatherData? live = _live[district];
    final seasonal = _seasonalAdvice(district, month);

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
          if (live != null) ...[
            Row(
              children: [
                Icon(_iconForCode(live.code),
                    color: _iconColorForCode(live.code), size: 28),
                const SizedBox(width: 8),
                Text(
                  '${live.tempC.round()}°C',
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
              _conditionForCode(live.code),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (_loading) ...[
            const SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.mintGreen),
            ),
            const SizedBox(height: 8),
            Text(
              'Fetching live weather…',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            ),
          ] else ...[
            Icon(Icons.cloud_off,
                color: Colors.white.withValues(alpha: 0.3), size: 28),
            const SizedBox(height: 8),
            Text(
              'Live weather unavailable',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            ),
          ],
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
                  seasonal,
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

  // ── Open-Meteo weather codes → display ────────────────────────────────────

  IconData _iconForCode(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code <= 3) return Icons.wb_cloudy_outlined;
    if (code <= 48) return Icons.foggy;
    if (code <= 67) return Icons.umbrella;
    if (code <= 77) return Icons.ac_unit;
    if (code <= 82) return Icons.cloudy_snowing;
    return Icons.thunderstorm;
  }

  Color _iconColorForCode(int code) {
    if (code == 0) return Colors.amber;
    if (code <= 3) return Colors.yellow;
    if (code <= 48) return Colors.blueGrey;
    if (code <= 82) return Colors.lightBlueAccent;
    return Colors.deepOrangeAccent;
  }

  String _conditionForCode(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 57) return 'Light drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 82) return 'Rain showers';
    return 'Thunderstorm';
  }

  // ── Seasonal advice (domain knowledge, not measurements) ─────────────────

  String _seasonalAdvice(String district, int month) {
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
        name.contains('chattogram') ||
        name.contains('noakhali');

    if (month >= 6 && month <= 8) {
      if (isHilly) return 'Jun - Sep (Green Season)';
      if (isCoastal) return 'Nov - Feb (Winter Beach)';
      return 'Nov - Feb (Cool Months)';
    } else if (month >= 11 || month <= 2) {
      if (isHilly) return 'Nov - Mar (Trekking)';
      if (isCoastal) return 'Nov - Feb (Peak Season)';
      return 'Nov - Feb (Festivals)';
    } else if (month >= 9 && month <= 10) {
      return 'Sep - Oct (Autumn Colors)';
    } else {
      if (isHilly) return 'Oct - Mar (Dry Weather)';
      return 'Dec - Feb (Pleasant Temp)';
    }
  }

  // ── District centers (approximate; good enough for weather) ──────────────

  (double, double)? _districtCoords(String district) {
    final key = district.toLowerCase().trim();
    for (final entry in _coords.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static const Map<String, (double, double)> _coords = {
    'dhaka': (23.81, 90.41),
    'gazipur': (24.00, 90.42),
    'narayanganj': (23.62, 90.50),
    'tangail': (24.25, 89.92),
    'kishoreganj': (24.44, 90.78),
    'mymensingh': (24.75, 90.40),
    'netrokona': (24.88, 90.73),
    'jamalpur': (24.94, 89.94),
    'sherpur': (25.02, 90.02),
    'sylhet': (24.90, 91.87),
    'moulvibazar': (24.48, 91.78),
    'sunamganj': (25.07, 91.40),
    'habiganj': (24.38, 91.41),
    'chattogram': (22.36, 91.78),
    'chittagong': (22.36, 91.78),
    'cox': (21.44, 91.97),
    'bandarban': (22.20, 92.22),
    'rangamati': (22.65, 92.17),
    'sajek': (23.38, 92.29),
    'khagrachhari': (23.11, 91.98),
    'cumilla': (23.46, 91.18),
    'comilla': (23.46, 91.18),
    'noakhali': (22.87, 91.10),
    'feni': (23.02, 91.40),
    'chandpur': (23.23, 90.66),
    'brahmanbaria': (23.96, 91.11),
    'lakshmipur': (22.94, 90.83),
    'khulna': (22.82, 89.55),
    'bagerhat': (22.65, 89.79),
    'satkhira': (22.72, 89.07),
    'jashore': (23.17, 89.21),
    'jessore': (23.17, 89.21),
    'kushtia': (23.90, 89.12),
    'jhenaidah': (23.54, 89.15),
    'magura': (23.49, 89.42),
    'narail': (23.17, 89.51),
    'chuadanga': (23.64, 88.86),
    'meherpur': (23.76, 88.63),
    'barishal': (22.70, 90.37),
    'barisal': (22.70, 90.37),
    'patuakhali': (22.36, 90.33),
    'kuakata': (21.82, 90.12),
    'bhola': (22.69, 90.64),
    'pirojpur': (22.58, 89.97),
    'jhalokathi': (22.64, 90.20),
    'barguna': (22.15, 90.13),
    'rajshahi': (24.37, 88.60),
    'bogura': (24.85, 89.37),
    'bogra': (24.85, 89.37),
    'pabna': (24.00, 89.24),
    'sirajganj': (24.45, 89.71),
    'naogaon': (24.79, 88.94),
    'natore': (24.41, 88.99),
    'chapainawabganj': (24.60, 88.28),
    'joypurhat': (25.10, 89.02),
    'rangpur': (25.74, 89.28),
    'dinajpur': (25.63, 88.64),
    'panchagarh': (26.34, 88.55),
    'thakurgaon': (26.03, 88.47),
    'nilphamari': (25.93, 88.86),
    'lalmonirhat': (25.92, 89.45),
    'kurigram': (25.81, 89.64),
    'gaibandha': (25.33, 89.53),
    'manikganj': (23.86, 90.00),
    'munshiganj': (23.54, 90.53),
    'narsingdi': (23.92, 90.72),
    'rajbari': (23.76, 89.64),
    'faridpur': (23.61, 89.84),
    'gopalganj': (23.01, 89.82),
    'madaripur': (23.17, 90.21),
    'shariatpur': (23.24, 90.43),
  };
}
