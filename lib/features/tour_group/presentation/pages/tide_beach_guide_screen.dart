import 'package:flutter/material.dart';
import '../../domain/services/tide_schedule_engine.dart';
import '../../../../core/theme/colors.dart';

class TideBeachGuideScreen extends StatelessWidget {
  final String tourId;

  const TideBeachGuideScreen({super.key, required this.tourId});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final safety = TideScheduleEngine.evaluateCurrentSafety(now);
    final tides = TideScheduleEngine.getTidesForDate(now);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: const Text(
          'Tide & Beach Safety (জোয়ার-ভাটা ও সৈকত গাইড)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Real-time Safety Status Banner
          _buildLiveSafetyBanner(safety),
          const SizedBox(height: 20),

          // 2. Today's Tidal Schedule
          const Text(
            'আজকের জোয়ার-ভাটার সময়সূচী (Today\'s Tide Schedule)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          ...tides.map((t) => _buildTideCard(t, safety.currentWindow == t)),

          const SizedBox(height: 24),

          // 3. Danger Spots & Safety Guidelines
          const Text(
            'সৈকত সতর্কতা ও লাইফগার্ড জোন (Beach Safety & Checkpoints)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          _buildSafetyWarningCard(
            title: 'চোরাবালি ও গুপ্ত গর্ত সতর্কতা (Quicksand Advisory)',
            desc: 'ভাটার সময় সৈকতের বালি দ্রুত ধসে পড়ে। বিশেষ করে কলাতলী ও লাবণী পয়েন্টের কিছু অংশে চোরাবালি সৃষ্টি হয়। ভাটার সময় সাগরে নামবেন না।',
            icon: Icons.warning_amber_rounded,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 10),
          _buildSafetyWarningCard(
            title: 'লাইফগার্ড ফ্ল্যাগ গাইড (Beach Flag Guide)',
            desc: '🔴 লাল পতাকা: সাগরে নামা সম্পূর্ণ নিষিদ্ধ ও মারাত্মক ঝুঁকিপূর্ণ।\n🟡 হলুদ পতাকা: মাঝারি সতর্কতা, কোমর পানির বেশি নামবেন না।\n🟢 সবুজ পতাকা: লাইফগার্ড সীমানার ভেতরে স্নান নিরাপদ।',
            icon: Icons.flag_rounded,
            color: AppColors.gold,
          ),
          const SizedBox(height: 10),
          _buildSafetyWarningCard(
            title: 'জরুরি সহায়তা ও হেল্পলাইন (Emergency Contacts)',
            desc: 'ট্যুরিস্ট পুলিশ কন্ট্রোল রুম: 01320-169999\nসি-সেফ লাইফগার্ড: 01711-000000\nজাতীয় জরুরি সেবা: 999',
            icon: Icons.support_agent_rounded,
            color: const Color(0xFF38BDF8),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveSafetyBanner(
      ({SwimSafetyStatus status, String advisory, TideWindow? currentWindow, TideWindow? nextWindow}) safety) {
    Color bannerColor;
    IconData bannerIcon;

    switch (safety.status) {
      case SwimSafetyStatus.safe:
        bannerColor = AppColors.mintGreen;
        bannerIcon = Icons.check_circle_rounded;
        break;
      case SwimSafetyStatus.caution:
        bannerColor = AppColors.gold;
        bannerIcon = Icons.info_rounded;
        break;
      case SwimSafetyStatus.danger:
        bannerColor = Colors.redAccent;
        bannerIcon = Icons.dangerous_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bannerColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(bannerIcon, color: bannerColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  safety.status.banglaTitle,
                  style: TextStyle(
                    color: bannerColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            safety.advisory,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          ),
          if (safety.currentWindow != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'বর্তমান পর্যায়: ${safety.currentWindow!.name} (${safety.currentWindow!.formatTimeRange()})',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTideCard(TideWindow tide, bool isCurrent) {
    final isHigh = tide.type == TideType.high;
    final color = isHigh ? const Color(0xFF38BDF8) : Colors.orangeAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? color : Colors.white12,
          width: isCurrent ? 2.0 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isHigh ? Icons.waves_rounded : Icons.water_drop_outlined,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tide.name,
                      style: TextStyle(
                        color: isCurrent ? color : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      tide.formatTimeRange(),
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tide.description,
                  style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyWarningCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
