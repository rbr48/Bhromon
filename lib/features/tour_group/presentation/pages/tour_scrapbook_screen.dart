import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/models/tour_group.dart';
import '../../data/tour_group_repository.dart';
import 'package:share_plus/share_plus.dart';

class TourScrapbookScreen extends StatefulWidget {
  final String tourId;

  const TourScrapbookScreen({super.key, required this.tourId});

  @override
  State<TourScrapbookScreen> createState() => _TourScrapbookScreenState();
}

class _TourScrapbookScreenState extends State<TourScrapbookScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;
  Map<String, dynamic>? _tourData;
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScrapbookData();
  }

  Future<void> _loadScrapbookData() async {
    try {
      final group = await _repository.getGroup(widget.tourId);
      final doc = await _firestore.collection('tours').doc(widget.tourId).get();
      var membersSnap = await _firestore
          .collection('memberships')
          .where('tourId', isEqualTo: widget.tourId)
          .get();

      if (membersSnap.docs.isEmpty) {
        membersSnap = await _firestore
            .collection('tours')
            .doc(widget.tourId)
            .collection('members')
            .get();
      }

      if (mounted) {
        setState(() {
          _tourGroup = group;
          _tourData = doc.data();
          _members = membersSnap.docs.map((d) => d.data()).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _shareScrapbookSummary() {
    final tourName = _tourGroup?.name ?? (_tourData?['name'] as String? ?? 'ফ্যামিলি ট্যুর স্মৃতিমালা');
    final datesStr = _tourGroup != null
        ? '${DateFormat('d MMM yyyy').format(_tourGroup!.startDate)} – ${DateFormat('d MMM yyyy').format(_tourGroup!.endDate)}'
        : 'ট্যুর সময়কাল';
    final durationStr = _tourGroup?.durationText ?? '৫ দিনব্যাপী ফ্যামিলি ট্যুর';
    final dest = _tourGroup?.destination ?? 'কক্সবাজার';
    final origin = _tourGroup?.originCity ?? 'যাত্রা স্থান';

    final shareText = '''
📖 $tourName — ডিজিটাল স্ক্র্যাপবুক ও স্মরণিকা
✨ ভ্রমণকাল: $datesStr ($durationStr)
🚌 যাত্রাপথ: $origin ➔ $dest
🏨 গন্তব্য: $dest
👥 মোট পরিভ্রমণকারী: ${_members.length} জন সদস্য

✨ স্মরণীয় দর্শনীয় স্থানসমূহ:
${(_tourGroup?.allSpots.take(5) ?? ['প্রধান দর্শনীয় স্পট', 'হোটেল ও রিসোর্ট']).map((s) => '• $s').join('\n')}

ভ্রমণে Bhromon অ্যাপের মাধ্যমে সংরক্ষিত অবিস্মরণীয় স্মৃতিমালা ❤️
''';
    // ignore: deprecated_member_use
    Share.share(shareText, subject: '$tourName ডিজিটাল স্মৃতিচিহ্ন');
  }

  @override
  Widget build(BuildContext context) {
    final tourName = _tourData?['name'] as String? ?? (_tourGroup?.name ?? 'ট্যুর ডিজিটাল স্মৃতিমালা');

    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: const Text('Digital Scrapbook & Magazine',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'স্মৃতিচিহ্ন শেয়ার করুন',
            onPressed: _shareScrapbookSummary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  // Magazine Cover Section
                  _buildMagazineCover(tourName),

                  const SizedBox(height: 20),

                  // Key Highlights Metrics Grid
                  _buildMetricsGrid(),

                  const SizedBox(height: 20),

                  // Memory Highlights Section
                  _buildHighlightsSection(),

                  const SizedBox(height: 20),

                  // Tour Honor Roll
                  _buildHonorRoll(),

                  const SizedBox(height: 24),

                  // Share & Save Souvenir Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('ডিজিটাল স্মৃতিচিহ্ন শেয়ার করুন', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _shareScrapbookSummary,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMagazineCover(String tourName) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8D4B00), Color(0xFF3E1F00), Color(0xFF1A0C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'স্মৃতিচিহ্ন ও ভ্রমণ স্মারক ২০২৬',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            tourName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tourGroup != null
                ? '${DateFormat('d MMM yyyy').format(_tourGroup!.startDate)} – ${DateFormat('d MMM yyyy').format(_tourGroup!.endDate)} • ${_tourGroup!.durationText}'
                : 'ভ্রমণ স্মৃতিচিহ্ন ও ফ্যামিলি ম্যাগাজিন',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CoverBadge(icon: Icons.directions_bus, label: '${_tourGroup?.originCity ?? "যাত্রা"} পরিবহন'),
              _CoverBadge(icon: Icons.hotel, label: '${_tourGroup?.destination ?? "ট্যুর"} আবাসন'),
              _CoverBadge(icon: Icons.explore_rounded, label: '${_tourGroup?.destination ?? "স্পট"} ভ্রমণ'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'মোট পরিভ্রমণ',
            value: '~৮২০ কি.মি.',
            icon: Icons.route,
            color: Colors.tealAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            title: 'ট্যুর পার্টিসিপ্যান্ট',
            value: '${_members.isEmpty ? 36 : _members.length} জন',
            icon: Icons.groups,
            color: Colors.amber,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            title: 'ট্যুর ব্যাপ্তিকাল',
            value: _tourGroup?.durationText ?? '৫ দিন ৪ রাত',
            icon: Icons.calendar_month,
            color: Colors.blueAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(title, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightsSection() {
    final highlights = [
      {'title': 'বঙ্গবন্ধু যমুনা সেতু পারাপার', 'desc': 'রাতে যমুনা নদীর শীতল বাতাস ও ৪.৮ কি.মি. দীর্ঘ মেগা ব্রিজ অতিক্রম।', 'icon': '🌉'},
      {'title': 'শেরপুর ফুড ভিলেজ প্লাস', 'desc': 'বগুড়ার বিখ্যাত মিষ্টি দই ও রাতের হাইওয়ে বিরতি।', 'icon': '🍲'},
      {'title': 'ইনানী প্রবাল সৈকত ও পাথুরে রূপ', 'desc': 'স্বচ্ছ শান্ত পানি এবং প্রবাল পাথরের প্রাকৃতিক স্বর্গরাজ্য।', 'icon': '🪨'},
      {'title': 'হিমছড়ি ঝর্ণা ও মেরিন ড্রাইভ', 'desc': 'একপাশে আকাশচুম্বী সবুজ পাহাড়, অন্যপাশে নীল সমুদ্রের রোমাঞ্চকর ড্রাইভ।', 'icon': '🌊'},
      {'title': 'সুগন্ধা সৈকতে সূর্যাস্ত ও ফ্যামিলি মিলনমেলা', 'desc': 'পরিবারের সবাই মিলে লাল টুকটুকে সূর্যাস্ত দর্শন ও ফটোসেশন।', 'icon': '🌅'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.stars, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'ট্যুরের অবিস্মরণীয় মুহূর্তমালা (Highlights)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...highlights.map((h) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h['icon']!, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(h['desc']!, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHonorRoll() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF142428),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.military_tech, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'ট্যুর পরিচালনা ও কৃতজ্ঞতা স্বীকার (Honor Roll)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '• ট্যুর লিডার ও প্রধান সমন্বয়ক: সার্বিক দিকনির্দেশনা ও রুট পরিকল্পনা\n'
            '• কোষাধ্যক্ষ ও হিসাবরক্ষক: স্প্লিটওয়াইজ স্বচ্ছ তহবিল ব্যবস্থাপনা\n'
            '• পরিবারবর্গ: স্বতঃস্ফূর্ত অংশগ্রহণ ও একাত্মতা\n'
            'সকলের আন্তরিক সহযোগিতায় ট্যুরটি সফল ও আনন্দময় হয়েছে।',
            style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _CoverBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CoverBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.amber, size: 14),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
