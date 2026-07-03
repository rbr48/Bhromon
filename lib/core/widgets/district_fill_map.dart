import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// 🗺️ Bangladesh District Fill Map widget.
/// Colors districts the user has visited, shows completion percentage.
/// Uses a simplified rectangular representation of Bangladesh's 64 districts
/// organized by division for performance (no external SVG dependency).
class DistrictFillMapWidget extends StatelessWidget {
  /// Districts the user has logged diary entries for.
  final List<String> visitedDistricts;

  /// Size of the widget (it will be square).
  final double size;

  const DistrictFillMapWidget({
    super.key,
    required this.visitedDistricts,
    this.size = 300,
  });

  static const Map<String, List<String>> _districtsByDivision = {
    'ঢাকা': [
      'ঢাকা', 'ফরিদপুর', 'গাজীপুর', 'গোপালগঞ্জ', 'কিশোরগঞ্জ',
      'মাদারীপুর', 'মানিকগঞ্জ', 'মুন্সীগঞ্জ', 'নারায়ণগঞ্জ', 'নরসিংদী',
      'রাজবাড়ী', 'শরীয়তপুর', 'টাঙ্গাইল',
    ],
    'চট্টগ্রাম': [
      'ব্রাহ্মণবাড়িয়া', 'চাঁদপুর', 'চট্টগ্রাম', 'কুমিল্লা', 'কক্সবাজার',
      'ফেনী', 'খাগড়াছড়ি', 'লক্ষ্মীপুর', 'নোয়াখালী', 'রাঙামাটি',
    ],
    'সিলেট': ['হবিগঞ্জ', 'মৌলভীবাজার', 'সুনামগঞ্জ', 'সিলেট'],
    'রাজশাহী': [
      'বগুড়া', 'চাঁপাইনবাবগঞ্জ', 'জয়পুরহাট', 'নওগাঁ', 'নাটোর',
      'পাবনা', 'রাজশাহী', 'সিরাজগঞ্জ',
    ],
    'খুলনা': [
      'বাগেরহাট', 'চুয়াডাঙ্গা', 'যশোর', 'ঝিনাইদহ', 'খুলনা',
      'কুষ্টিয়া', 'মাগুরা', 'মেহেরপুর', 'নড়াইল', 'সাতক্ষীরা',
    ],
    'বরিশাল': [
      'বরগুনা', 'বরিশাল', 'ভোলা', 'ঝালকাঠি', 'পটুয়াখালী', 'পিরোজপুর',
    ],
    'রংপুর': [
      'দিনাজপুর', 'গাইবান্ধা', 'কুড়িগ্রাম', 'লালমনিরহাট', 'নীলফামারী',
      'পঞ্চগড়', 'রংপুর', 'ঠাকুরগাঁও',
    ],
    'ময়মনসিংহ': ['জামালপুর', 'ময়মনসিংহ', 'নেত্রকোণা', 'শেরপুর'],
    'বান্দরবান': ['বান্দরবান'],
  };

  static const Map<String, Color> _divisionColors = {
    'ঢাকা': Color(0xFF2D6A4F),
    'চট্টগ্রাম': Color(0xFF1B4332),
    'সিলেট': Color(0xFF52B788),
    'রাজশাহী': Color(0xFF40916C),
    'খুলনা': Color(0xFF74C69D),
    'বরিশাল': Color(0xFFB7E4C7),
    'রংপুর': Color(0xFFD8F3DC),
    'ময়মনসিংহ': Color(0xFF95D5B2),
    'বান্দরবান': Color(0xFF52B788),
  };

  @override
  Widget build(BuildContext context) {
    final visitedSet = visitedDistricts.toSet();
    final totalVisited = _districtsByDivision.values
        .expand((d) => d)
        .where((d) => visitedSet.contains(d))
        .length;
    const total = 64;
    final pct = (totalVisited / total * 100).toStringAsFixed(0);

    return Column(
      children: [
        // Stats row
        Row(
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              '$totalVisited / $total জেলা অন্বেষণ করেছেন ($pct%)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Map grid
        SizedBox(
          width: size,
          height: size * 0.8,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            itemCount: _allDistricts.length,
            itemBuilder: (context, index) {
              final district = _allDistricts[index];
              final division = _divisionFor(district);
              final isVisited = visitedSet.contains(district);
              final baseColor = _divisionColors[division] ?? AppColors.mintGreen;

              return Tooltip(
                message: district,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  decoration: BoxDecoration(
                    color: isVisited ? baseColor : Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isVisited
                          ? baseColor.withOpacity(0.5)
                          : Colors.white10,
                      width: 0.5,
                    ),
                    boxShadow: isVisited
                        ? [
                            BoxShadow(
                              color: baseColor.withOpacity(0.4),
                              blurRadius: 4,
                            )
                          ]
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: _divisionColors.entries.take(4).map((e) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: e.value,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  e.key,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  String _divisionFor(String district) {
    for (final entry in _districtsByDivision.entries) {
      if (entry.value.contains(district)) return entry.key;
    }
    return 'ঢাকা';
  }

  List<String> get _allDistricts =>
      _districtsByDivision.values.expand((d) => d).toList();
}
