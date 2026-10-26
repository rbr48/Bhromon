import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/models/tour_post_models.dart';
import 'package:share_plus/share_plus.dart';

class TourScrapbookScreen extends StatefulWidget {
  final String tourId;

  const TourScrapbookScreen({super.key, required this.tourId});

  @override
  State<TourScrapbookScreen> createState() => _TourScrapbookScreenState();
}

class _TourScrapbookScreenState extends State<TourScrapbookScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;
  StreamSubscription<TourGroup?>? _groupSub;
  List<TourMember> _members = const [];
  List<TourPostItem> _posts = const [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadScrapbookData();
    _watchGroup();
  }

  void _watchGroup() {
    _groupSub?.cancel();
    _groupSub = _repository.watchGroup(widget.tourId).listen((g) {
      if (mounted) setState(() => _tourGroup = g);
    });
  }

  /// Everything the scrapbook shows comes from the tour itself: the group, its
  /// members and its posts. Nothing is invented when the data is missing.
  Future<void> _loadScrapbookData() async {
    try {
      final members = await _repository.watchMembers(widget.tourId).first;
      final posts =
          await _repository.watchPosts(widget.tourId, limit: 60).first;
      if (!mounted) return;
      setState(() {
        _members = members;
        _posts = posts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError =
            'স্ক্র্যাপবুক লোড করা যায়নি। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।';
      });
    }
  }

  void _shareScrapbookSummary() {
    final tourName = _tourGroup?.name ?? 'ফ্যামিলি ট্যুর স্মৃতিমালা';
    final datesStr = _tourGroup != null
        ? '${DateFormat('d MMM yyyy').format(_tourGroup!.startDate)} – ${DateFormat('d MMM yyyy').format(_tourGroup!.endDate)}'
        : 'ট্যুর সময়কাল';
    final durationStr = _tourGroup?.durationText ?? '';
    final dest = _tourGroup?.destination ?? 'কক্সবাজার';
    final origin = _tourGroup?.originCity ?? 'যাত্রা স্থান';

    final shareText = '''
📖 $tourName — ডিজিটাল স্ক্র্যাপবুক ও স্মরণিকা
✨ ভ্রমণকাল: $datesStr ($durationStr)
🚌 যাত্রাপথ: $origin ➔ $dest
🏨 গন্তব্য: $dest
👥 মোট পরিভ্রমণকারী: ${_members.length} জন সদস্য

✨ স্মরণীয় দর্শনীয় স্থানসমূহ:
${(_tourGroup?.allSpots.take(5) ?? [
              'প্রধান দর্শনীয় স্পট',
              'হোটেল ও রিসোর্ট'
            ]).map((s) => '• $s').join('\n')}

ভ্রমণে Bhromon অ্যাপের মাধ্যমে সংরক্ষিত অবিস্মরণীয় স্মৃতিমালা ❤️
''';
    // ignore: deprecated_member_use
    Share.share(shareText, subject: '$tourName ডিজিটাল স্মৃতিচিহ্ন');
  }

  @override
  Widget build(BuildContext context) {
    final tourName = _tourGroup?.name ?? 'ট্যুর ডিজিটাল স্মৃতিমালা';

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
          ? const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                )
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
                          label: const Text('ডিজিটাল স্মৃতিচিহ্ন শেয়ার করুন',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
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
        border:
            Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 12, offset: Offset(0, 6)),
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
              style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 11),
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
          const Divider(color: Colors.white54),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CoverBadge(
                  icon: Icons.directions_bus,
                  label: '${_tourGroup?.originCity ?? "যাত্রা"} পরিবহন'),
              _CoverBadge(
                  icon: Icons.hotel,
                  label: '${_tourGroup?.destination ?? "ট্যুর"} আবাসন'),
              _CoverBadge(
                  icon: Icons.explore_rounded,
                  label: '${_tourGroup?.destination ?? "স্পট"} ভ্রমণ'),
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
            title: 'স্মৃতি পোস্ট',
            value: '${_posts.length} টি',
            icon: Icons.photo_library,
            color: Colors.tealAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            title: 'ট্যুর পার্টিসিপ্যান্ট',
            value: '${_members.length} জন',
            icon: Icons.groups,
            color: Colors.amber,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            title: 'ট্যুর ব্যাপ্তিকাল',
            value: _tourGroup?.durationText ?? '—',
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
            child: Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(title,
                style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  /// Recent photo and reel posts from the tour, newest first.
  Widget _buildHighlightsSection() {
    final highlights = _posts.where((p) => p.hasRemoteMedia).take(6).toList();

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
                'ট্যুরের অবিস্মরণীয় মুহূর্তমালা (Highlights)',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (highlights.isEmpty)
            const Text(
              'এখনও কোনো ছবি বা রিলস যুক্ত হয়নি। ইনস্টাফিড থেকে প্রথম পোস্ট করুন।',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          else
            for (final post in highlights)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.isReel ? '🎬' : '📸',
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.caption.isEmpty
                                ? post.authorName
                                : post.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                          Text(
                            [
                              post.authorName,
                              if (post.location.isNotEmpty) post.location,
                            ].join(' • '),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
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
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}
