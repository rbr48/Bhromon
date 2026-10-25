import 'package:flutter/material.dart';
import '../../domain/services/tide_schedule_engine.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import '../../../../core/theme/colors.dart';

class TideBeachGuideScreen extends StatefulWidget {
  final String tourId;

  const TideBeachGuideScreen({super.key, required this.tourId});

  @override
  State<TideBeachGuideScreen> createState() => _TideBeachGuideScreenState();
}

class _TideBeachGuideScreenState extends State<TideBeachGuideScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;
  bool _isBeachView = true;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    final g = await _repository.getGroup(widget.tourId);
    if (mounted) {
      setState(() {
        _tourGroup = g;
        _isBeachView = g?.tourType == TourType.beach ||
            (g?.destination.toLowerCase().contains('cox') ?? true) ||
            (g?.destination.toLowerCase().contains('kuakata') ?? false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final safety = TideScheduleEngine.evaluateCurrentSafety(now);
    final tides = TideScheduleEngine.getTidesForDate(now);
    final dest = _tourGroup?.destination ?? 'ভ্রমণ এলাকা';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: Text(
          _isBeachView
              ? 'Tide & Beach Safety (জোয়ার-ভাটা ও সৈকত)'
              : '$dest ওয়েদার ও নেচার সেফটি',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: Icon(
                _isBeachView ? Icons.landscape_rounded : Icons.waves_rounded,
                color: AppColors.mintGreen),
            tooltip: _isBeachView
                ? 'পাহাড় ও নেচার গাইড দেখুন'
                : 'বিচ ও জোয়ার-ভাটা দেখুন',
            onPressed: () {
              setState(() => _isBeachView = !_isBeachView);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Mode Switcher Banner
          Container(
            padding: const EdgeInsets.all(4),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isBeachView = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _isBeachView ? AppColors.mintGreen : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '🌊 সমুদ্র ও জোয়ার-ভাটা',
                          style: TextStyle(
                            color: _isBeachView ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isBeachView = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            !_isBeachView ? Colors.tealAccent.shade700 : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '⛰️ পাহাড়, আবহাওয়া ও ট্র্যাকিং',
                          style: TextStyle(
                            color:
                                !_isBeachView ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_isBeachView) ...[
            // ── Beach View ──
            _buildLiveSafetyBanner(safety),
            const SizedBox(height: 20),

            const Text(
              'আজকের জোয়ার-ভাটার সময়সূচী (Today\'s Tide Schedule)',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 10),
            ...tides.map((t) => _buildTideCard(t, safety.currentWindow == t)),

            const SizedBox(height: 24),

            const Text(
              'সৈকত সতর্কতা ও লাইফগার্ড জোন (Beach Safety & Checkpoints)',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 12),
            _buildSafetyWarningCard(
              title: 'চোরাবালি ও গুপ্ত গর্ত সতর্কতা (Quicksand Advisory)',
              desc:
                  'ভাটার সময় সৈকতের বালি দ্রুত ধসে পড়ে। বিশেষ করে চোরাবালির ঝুঁকি থাকে। ভাটার সময় কোমর পানির বেশি নামবেন না।',
              icon: Icons.warning_amber_rounded,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 10),
            _buildSafetyWarningCard(
              title: 'লাইফগার্ড ফ্ল্যাগ গাইড (Beach Flag Guide)',
              desc:
                  '🔴 লাল পতাকা: সাগরে নামা সম্পূর্ণ নিষিদ্ধ ও মারাত্মক ঝুঁকিপূর্ণ।\n🟡 হলুদ পতাকা: মাঝারি সতর্কতা, কোমর পানির বেশি নামবেন না।\n🟢 সবুজ পতাকা: লাইফগার্ড সীমানার ভেতরে স্নান নিরাপদ।',
              icon: Icons.flag_rounded,
              color: AppColors.gold,
            ),
          ] else ...[
            // ── Mountain, Forest & Nature View ──
            _buildMountainSafetyBanner(dest),
            const SizedBox(height: 20),

            const Text(
              'সূর্যোদয়, সূর্যাস্ত ও মেঘের দৃশ্য (Sun & Cloud Radar)',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 10),
            _buildSunEventCard(
                'ভোর ০৫:৩৫ – ০৬:১৫',
                'সূর্যোদয় ও মেঘের ভেলা (Sunrise Clouds)',
                'কটেজ বা পাহাড়ের পূর্ব কোণে মেঘের সমুদ্র দেখার সেরা সময়',
                Icons.wb_twilight_rounded,
                Colors.orangeAccent),
            const SizedBox(height: 8),
            _buildSunEventCard(
                'বিকেল ০৫:২০ – ০৫:৫৫',
                'পাহাড়ি সূর্যাস্ত ও গোধূলি (Golden Hour)',
                'পশ্চিম পাহাড়ের চূড়ায় রক্তিম সূর্যাস্ত ও ছবি তোলার সোনালী আলো',
                Icons.wb_sunny_rounded,
                Colors.amber),

            const SizedBox(height: 24),

            Text(
              '$dest পাহাড় ও ট্র্যাকিং নির্দেশিকা (Mountain Guidelines)',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 12),
            _buildSafetyWarningCard(
              title: 'ঝর্ণা ও পিচ্ছিল পাথর সতর্কতা (Waterfall Warning)',
              desc:
                  'পাহাড়ি ঝর্ণা ও নদীর পাথরে ভেজা শ্যাওলা থাকে। সাধারণ স্যান্ডেল পরে নামবেন না, ভালো গ্রিপযুক্ত বেল্ট স্যান্ডেল বা ট্র্যাকিং জুতো ব্যবহার করুন।',
              icon: Icons.water_drop_rounded,
              color: Colors.lightBlueAccent,
            ),
            const SizedBox(height: 10),
            _buildSafetyWarningCard(
              title: 'হড়কা বান ও আকস্মিক পাহাড়ি ঢল (Flash Flood Risk)',
              desc:
                  'উজান বা ভারতের পাহাড়ে বৃষ্টি হলে মুহূর্তের মধ্যে ঝর্ণা বা নদীতে হড়কা বান নেমে আসতে পারে। পানির রং ঘোলা হলেই সাথে সাথে ডাঙায় উঠে আসুন।',
              icon: Icons.thunderstorm_rounded,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 10),
            _buildSafetyWarningCard(
              title: 'চাঁদের গাড়ি ও পাহাড়ি বাঁক সতর্কতা (Off-road Travel)',
              desc:
                  'চাঁদের গাড়ি বা খোলা জিপে দাঁড়িয়ে চলার সময় শক্ত করে রড ধরে রাখুন। বাঁক ঘোরার সময় কোনো ঝুঁকিপূর্ণ সেলফি তুলবেন না।',
              icon: Icons.directions_bus_rounded,
              color: AppColors.gold,
            ),
          ],

          const SizedBox(height: 10),
          _buildSafetyWarningCard(
            title: 'জরুরি সহায়তা ও হেল্পলাইন (Emergency Contacts)',
            desc:
                'ট্যুরিস্ট পুলিশ কন্ট্রোল রুম: 01320-163599\nহাইওয়ে পুলিশ কন্ট্রোল: 01320-189999\nজাতীয় জরুরি সেবা: 999',
            icon: Icons.support_agent_rounded,
            color: const Color(0xFF38BDF8),
          ),
        ],
      ),
    );
  }

  Widget _buildSunEventCard(
      String time, String title, String desc, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    Text(time,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(desc,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMountainSafetyBanner(String dest) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.teal.shade900.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.tealAccent.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration:
                const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
            child: const Icon(Icons.terrain_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$dest নেচার ও ক্লাইমেট ট্র্যাকার',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  'আবহাওয়া অনুকূল। সকাল ও বিকেলে মৃদু শীতল বাতাস এবং পাহাড়ি ট্র্যাকিংয়ের মনোরম পরিবেশ থাকবে।',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveSafetyBanner(
      ({
        SwimSafetyStatus status,
        String advisory,
        TideWindow? currentWindow,
        TideWindow? nextWindow
      }) safety) {
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
        border:
            Border.all(color: bannerColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(bannerIcon, color: bannerColor, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      safety.status == SwimSafetyStatus.safe
                          ? 'স্নানের নিরাপদ সময় (Safe to Swim)'
                          : (safety.status == SwimSafetyStatus.caution
                              ? 'সতর্কতা অবলম্বন করুন (Caution)'
                              : 'সাগরে নামা নিষেধ (High Danger)'),
                      style: TextStyle(
                          color: bannerColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  safety.advisory,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, height: 1.3),
                ),
                if (safety.currentWindow != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'বর্তমান অবস্থা: ${safety.currentWindow!.type == TideType.high ? 'জোয়ার (High Tide)' : 'ভাটা (Low Tide)'}',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTideCard(TideWindow tide, bool isCurrent) {
    final isHigh = tide.type == TideType.high;
    final color = isHigh ? AppColors.mintGreen : const Color(0xFF38BDF8);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:
            isCurrent ? color.withValues(alpha: 0.12) : const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? color : Colors.white12,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHigh
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tide.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'চলমান',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tide.formatTimeRange(),
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            isHigh ? '🌊 গোসল নিরাপদ' : '⚠️ ভাটা ও সতর্কতা',
            style: TextStyle(
              color: isHigh ? AppColors.mintGreen : Colors.orangeAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
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
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
