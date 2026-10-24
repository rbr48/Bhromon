import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class HighwayMilestone {
  final String id;
  final String name;
  final String nameEn;
  final int kmFromStart;
  final double lat;
  final double lng;
  final String estDuration;
  final String highlight;
  final String details;
  final List<String> amenities;
  final String iconEmoji;

  const HighwayMilestone({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.kmFromStart,
    required this.lat,
    required this.lng,
    required this.estDuration,
    required this.highlight,
    required this.details,
    required this.amenities,
    required this.iconEmoji,
  });
}

class JourneyTrackerScreen extends StatefulWidget {
  final String tourId;

  const JourneyTrackerScreen({super.key, required this.tourId});

  @override
  State<JourneyTrackerScreen> createState() => _JourneyTrackerScreenState();
}

class _JourneyTrackerScreenState extends State<JourneyTrackerScreen> {
  Position? _currentPosition;
  int _activeFilterIndex = 0; // 0: All, 1: Rest/Food, 2: Prayer, 3: Fuel

  static const int totalDistanceKm = 820;

  static const List<HighwayMilestone> milestones = [
    HighwayMilestone(
      id: 'RANGPUR_START',
      name: 'রংপুর জিরো পয়েন্ট (মডার্ন মোড়)',
      nameEn: 'Rangpur Zero Point',
      kmFromStart: 0,
      lat: 25.7439,
      lng: 89.2752,
      estDuration: '০০:০০ ঘণ্টা',
      highlight: 'যাত্রার শুভ সূচনা ও দোয়া',
      details: 'পরিবারের সকলের বাসে আসন গ্রহণ, লাগেজ চেকিং ও নিরাপদ ভ্রমণের শুভ দোয়া।',
      amenities: ['বাস ডিপো', 'চা ও কফি', 'নামাজ'],
      iconEmoji: '🚌',
    ),
    HighwayMilestone(
      id: 'BOGRA_SHERPUR',
      name: 'বগুড়া শেরপুর (ফুড ভিলেজ প্লাস)',
      nameEn: 'Sherpur, Bogra',
      kmFromStart: 110,
      lat: 24.6738,
      lng: 89.4187,
      estDuration: '০২:১৫ ঘণ্টা',
      highlight: 'শেরপুরের বিখ্যাত দই ও রাতের হালকা নাস্তা',
      details: 'ফুড ভিলেজে হাইওয়ে বিরতি, পরিষ্কার ওয়াশরুম এবং স্পেশাল চা ও মিষ্টি দই।',
      amenities: ['রেস্তোরাঁ', 'ওয়াশরুম', 'নামাজঘর', 'এটিএম'],
      iconEmoji: '🍲',
    ),
    HighwayMilestone(
      id: 'JAMUNA_BRIDGE',
      name: 'বঙ্গবন্ধু যমুনা বহুমুখী সেতু',
      nameEn: 'Jamuna Bridge',
      kmFromStart: 180,
      lat: 24.3985,
      lng: 89.7828,
      estDuration: '০৩:৪৫ ঘণ্টা',
      highlight: 'যমুনা নদীর নৈসর্গিক রূপ ও ৪.৮ কিমি সেতু পারাপার',
      details: 'পশ্চিম টোল প্লাজা অতিক্রম করে ঐতিহ্যবাহী যমুনা পারাপার। রাতে নদীর শীতল বাতাস।',
      amenities: ['টোল প্লাজা', 'ভিউ পয়েন্ট'],
      iconEmoji: '🌉',
    ),
    HighwayMilestone(
      id: 'ELENGA_TANGAIL',
      name: 'এলেঙ্গা ও টাঙ্গাইল বাইপাস',
      nameEn: 'Elenga, Tangail',
      kmFromStart: 215,
      lat: 24.3364,
      lng: 89.9234,
      estDuration: '০৪:৩০ ঘণ্টা',
      highlight: 'পোড়াবাড়ির চমচম অঞ্চল ও চারলেন এক্সপ্রেসওয়ে',
      details: 'টাঙ্গাইল বাইপাস ধরে দ্রুত ঢাকা অভিমুখে যাত্রা। হাইওয়ে ফুয়েলিং স্টেশন।',
      amenities: ['সিএনজি/তেল পাম্প', 'ওয়াশরুম'],
      iconEmoji: '⛽',
    ),
    HighwayMilestone(
      id: 'CHANDRA_GAZIPUR',
      name: 'চন্দ্রা মোড় ও ঢাকা বাইপাস',
      nameEn: 'Chandra, Gazipur',
      kmFromStart: 270,
      lat: 24.0384,
      lng: 90.2647,
      estDuration: '০৫:৪৫ ঘণ্টা',
      highlight: 'ঢাকা উত্তর এশিয়ান হাইওয়ে বাইপাস সংযোগ',
      details: 'ঢাকা শহরের যানজট এড়িয়ে বাইপাস এক্সপ্রেসওয়ে ধরে সরাসরি চট্টগ্রাম রোডের দিকে অগ্রসর।',
      amenities: ['বাইপাস রোড', 'পুলিশ বক্স'],
      iconEmoji: '🛣️',
    ),
    HighwayMilestone(
      id: 'KANCHPUR_MEGHNA',
      name: 'কাঁচপুর ও মেঘনা ঘাট (হাইওয়ে ইন)',
      nameEn: 'Kanchpur / Meghna Ghat',
      kmFromStart: 330,
      lat: 23.5937,
      lng: 90.6128,
      estDuration: '০৭:০০ ঘণ্টা',
      highlight: 'মেঘনা নদী পারাপার ও ফজর নামাজের বিরতি',
      details: 'হাইওয়ে ইন রেস্টুরেন্টে ভোরবেলা ফজর নামাজের বিশেষ বিরতি ও গরম চা।',
      amenities: ['নামাজঘর', 'পরিচ্ছন্ন ওয়াশরুম', 'হাইওয়ে ক্যাফে'],
      iconEmoji: '🕌',
    ),
    HighwayMilestone(
      id: 'DAUDKANDI_COMILLA',
      name: 'দাউদকান্দি ও গোমতী টোল প্লাজা',
      nameEn: 'Daudkandi, Cumilla',
      kmFromStart: 365,
      lat: 23.5358,
      lng: 90.7208,
      estDuration: '০৭:৪৫ ঘণ্টা',
      highlight: 'গোমতী নদী সেতু ও চারলেন এক্সপ্রেস মহাসড়ক',
      details: 'দাউদকান্দি বাইপাস ধরে কুমিল্লা অভিমুখে দ্রুত ট্রানজিট।',
      amenities: ['টোল প্লাজা', 'সিএনজি স্টেশন'],
      iconEmoji: '🚗',
    ),
    HighwayMilestone(
      id: 'COMILLA_PADUAR_BAZAR',
      name: 'কুমিল্লা পদুয়ার বাজার ও মায়ামী রিসোর্ট',
      nameEn: 'Paduar Bazar, Cumilla',
      kmFromStart: 410,
      lat: 23.4190,
      lng: 91.1780,
      estDuration: '০৮:৩০ ঘণ্টা',
      highlight: 'কুমিল্লার ঐতিহ্যবাহী রসমালাই ও সকালের নাস্তা',
      details: 'হাইওয়ে মায়ামী বা নূরজাহান রেস্তোরাঁয় সকালের গরম পরোটা, ডিম ও বিখ্যাত রসমালাই।',
      amenities: ['রেস্তোরাঁ', 'নামাজঘর', 'ওয়াশরুম', 'মিষ্টি দোকান'],
      iconEmoji: '☕',
    ),
    HighwayMilestone(
      id: 'FENI_MOHIPAL',
      name: 'ফেনী মহিপাল ফ্লাইওভার',
      nameEn: 'Mohipal, Feni',
      kmFromStart: 470,
      lat: 23.0186,
      lng: 91.3912,
      estDuration: '০৯:৪৫ ঘণ্টা',
      highlight: 'বাংলাদেশের প্রথম ছয়লেন ফ্লাইওভার অতিক্রম',
      details: 'ফেনী মহিপাল পার হয়ে চট্টগ্রাম মহানগরীর দিকে যাত্রা।',
      amenities: ['ফ্লাইওভার', 'তেল পাম্প'],
      iconEmoji: '🛣️',
    ),
    HighwayMilestone(
      id: 'CHITTAGONG_BYPASS',
      name: 'চট্টগ্রাম সিটি গেট ও ফৌজদারহাট',
      nameEn: 'Chittagong City Gate',
      kmFromStart: 540,
      lat: 22.3850,
      lng: 91.7510,
      estDuration: '১১:০০ ঘণ্টা',
      highlight: 'বন্দরনগরী চট্টগ্রাম প্রবেশ ও সমুদ্র উপকূল বাতাস',
      details: 'সিটি গেট পার হয়ে বাইপাস ধরে কর্ণফুলী সেতুর দিকে ডাইভারশন।',
      amenities: ['পুলিশ চেকপোস্ট', 'হাইওয়ে হোটেল'],
      iconEmoji: '⚓',
    ),
    HighwayMilestone(
      id: 'KARNAPHULI_BRIDGE',
      name: 'শাহ আমানত কর্ণফুলী ৩য় সেতু',
      nameEn: 'Karnaphuli Bridge',
      kmFromStart: 575,
      lat: 22.3210,
      lng: 91.8480,
      estDuration: '১১:৪৫ ঘণ্টা',
      highlight: 'কর্ণফুলী নদী পারাপার ও দক্ষিণ চট্টগ্রাম প্রবেশ',
      details: 'চট্টগ্রাম শহর পার হয়ে কক্সবাজার সরাসরি মহাসড়কে প্রবেশ।',
      amenities: ['টোল প্লাজা', 'ভিউ পয়েন্ট'],
      iconEmoji: '🌉',
    ),
    HighwayMilestone(
      id: 'LOHAGARA_AMIRABAD',
      name: 'লোহাগাড়া ও আমিরাবাদ জংশন',
      nameEn: 'Lohagara, Chittagong',
      kmFromStart: 635,
      lat: 22.0080,
      lng: 92.0980,
      estDuration: '১৩:০০ ঘণ্টা',
      highlight: 'সবুজ পাহাড়ের দৃশ্য ও চুনতি বন্যপ্রাণী অভয়ারণ্য শুরু',
      details: 'পাহাড় ও বনের বুক চিরে আঁকাবাঁকা প্রাকৃতিক মহাসড়ক।',
      amenities: ['রেস্তোরাঁ', 'ওয়াশরুম', 'চা দোকান'],
      iconEmoji: '🌳',
    ),
    HighwayMilestone(
      id: 'CHAKARIA_REST',
      name: 'চকরিয়া পৌরসভা ও মাতামুহুরী নদী',
      nameEn: 'Chakaria, Cox\'s Bazar',
      kmFromStart: 685,
      lat: 21.7860,
      lng: 92.0780,
      estDuration: '১৪:০০ ঘণ্টা',
      highlight: 'কক্সবাজার জেলা সীমানা প্রবেশ ও মাতামুহুরী ব্রিজ',
      details: 'চকরিয়া পার হলে কক্সবাজারের দূরত্ব মাত্র ৫০ কি.মি.।',
      amenities: ['ফিলিং স্টেশন', 'রেস্তোরাঁ'],
      iconEmoji: '🏞️',
    ),
    HighwayMilestone(
      id: 'RAMU_RUBBER',
      name: 'রামু রাবার বাগান ও বৌদ্ধ বিহার মোড়',
      nameEn: 'Ramu, Cox\'s Bazar',
      kmFromStart: 740,
      lat: 21.4420,
      lng: 92.1020,
      estDuration: '১৫:০০ ঘণ্টা',
      highlight: 'বিশাল রাবার বাগান ও ঐতিহাসিক রামু সংযোগ',
      details: 'কক্সবাজার সমুদ্র সৈকত মাত্র ৩০ মিনিটের ড্রাইভ দূরে।',
      amenities: ['রাবার বাগান ভিউ', 'চা পয়েন্ট'],
      iconEmoji: '🌿',
    ),
    HighwayMilestone(
      id: 'COXS_BAZAR_ZERO',
      name: 'কক্সবাজার কলাতলী ডলফিন মোড় (গন্তব্য)',
      nameEn: 'Cox\'s Bazar Dolphin Point',
      kmFromStart: 770,
      lat: 21.4270,
      lng: 91.9780,
      estDuration: '১৫:৪৫ ঘণ্টা',
      highlight: 'গন্তব্যে শুভ আগমন ও সমুদ্রের বিশাল গর্জন',
      details: 'হোটেল সি মুনে চেক-ইন, ফ্রেশ হওয়া এবং বিকেলে সুগন্ধা সৈকতে মিলনমেলা।',
      amenities: ['হোটেল সি মুন', 'সৈকত', 'রেস্তোরাঁ', 'বাজার'],
      iconEmoji: '🏖️',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fetchGps();
  }

  Future<void> _fetchGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = pos);
    } catch (_) {}
  }

  Future<void> _openLocationOnMap(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: const Text('Highway Journey Tracker (রোডম্যাপ)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'আমার লোকেশন রিফ্রেশ',
            onPressed: _fetchGps,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Overview Card
            _buildOverviewHeader(),

            // Filter Chips
            _buildFilterTabs(),

            // Milestones Timeline
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: milestones.length,
                itemBuilder: (context, index) {
                  return _buildMilestoneTile(milestones[index], index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewHeader() {
    double progress = 0.35;
    String statusSubtitle = 'যাত্রাপথ সম্পন্ন: ৩৫%';

    if (_currentPosition != null) {
      final distToDestKm = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            milestones.last.lat,
            milestones.last.lng,
          ) /
          1000.0;
      final traveledKm = (totalDistanceKm - distToDestKm).clamp(0, totalDistanceKm);
      progress = (traveledKm / totalDistanceKm).clamp(0.0, 1.0);
      statusSubtitle = 'গন্তব্য থেকে ${distToDestKm.toStringAsFixed(0)} কি.মি. দূরে (${(progress * 100).toStringAsFixed(0)}%)';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF142428),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.alt_route, color: Colors.tealAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'রংপুর ➔ কক্সবাজার জাতীয় মহাসড়ক',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('~$totalDistanceKm কি.মি.',
                    style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Route Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFF263D42),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('রংপুর (০ কি.মি.)', style: TextStyle(color: Colors.white54, fontSize: 11)),
              Text(statusSubtitle, style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              const Text('কক্সবাজার ($totalDistanceKm কি.মি.)', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final filters = ['সব মাইলস্টোন (${milestones.length})', 'বিরতি ও খাবার', 'নামাজঘর', 'ফুয়েল/পাম্প'];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (context, i) {
          final isSelected = _activeFilterIndex == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filters[i]),
              selected: isSelected,
              selectedColor: Colors.tealAccent.shade700,
              backgroundColor: const Color(0xFF182B30),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                if (val) setState(() => _activeFilterIndex = i);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMilestoneTile(HighwayMilestone m, int index) {
    // Check filters
    if (_activeFilterIndex == 1 && !m.amenities.any((a) => a.contains('রেস্তোরাঁ') || a.contains('নাস্তা') || a.contains('ক্যাফে'))) {
      return const SizedBox.shrink();
    }
    if (_activeFilterIndex == 2 && !m.amenities.any((a) => a.contains('নামাজ'))) {
      return const SizedBox.shrink();
    }
    if (_activeFilterIndex == 3 && !m.amenities.any((a) => a.contains('পাম্প') || a.contains('স্টেশন'))) {
      return const SizedBox.shrink();
    }

    final isFirst = index == 0;
    final isLast = index == milestones.length - 1;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Indicator
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isLast ? Colors.amber : (isFirst ? Colors.green : const Color(0xFF1E3A40)),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Center(
                    child: Text(
                      m.iconEmoji,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.teal.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Milestone Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF142428),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          m.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${m.kmFromStart} কি.মি.',
                          style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${m.nameEn} • সময়: ${m.estDuration}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '✨ ${m.highlight}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.details,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  // Amenities chips & Map button
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: m.amenities.map((a) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(a, style: const TextStyle(color: Colors.white60, fontSize: 10)),
                            );
                          }).toList(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.map, size: 18, color: Colors.tealAccent),
                        tooltip: 'ম্যাপে দেখুন',
                        onPressed: () => _openLocationOnMap(m.lat, m.lng),
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
