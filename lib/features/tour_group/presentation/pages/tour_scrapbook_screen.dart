import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/localization/app_localizations.dart';
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
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadScrapbookData();
    _watchGroup();
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    super.dispose();
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
        _loadFailed = true;
      });
    }
  }

  String? get _dateRange {
    final group = _tourGroup;
    if (group == null) return null;
    final format = DateFormat('d MMM yyyy');
    return '${format.format(group.startDate)} – ${format.format(group.endDate)}';
  }

  void _shareScrapbookSummary() {
    final l10n = context.l10n;
    final group = _tourGroup;
    final tourName = group?.name ?? l10n.translate('scrap_default_name');
    final spots = group?.allSpots.take(5).toList() ??
        [
          l10n.translate('scrap_spot_main'),
          l10n.translate('scrap_spot_hotels'),
        ];

    final shareText = l10n.translate('scrap_share_text', args: {
      'name': tourName,
      'dates': _dateRange ?? l10n.translate('scrap_dates_unknown'),
      'duration': group?.durationText ?? '',
      'origin': group?.originCity ?? l10n.translate('scrap_origin_unknown'),
      'destination':
          group?.destination ?? l10n.translate('scrap_destination_unknown'),
      'members': l10n.number(_members.length),
      'spots': spots.map((s) => '• $s').join('\n'),
    });
    // ignore: deprecated_member_use
    Share.share(shareText,
        subject: l10n.translate('scrap_share_subject', args: {
          'name': tourName,
        }));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tourName = _tourGroup?.name ?? l10n.translate('scrap_default_name');

    return Scaffold(
      backgroundColor: const Color(0xFF0F1A1C),
      appBar: AppBar(
        title: Text(l10n.translate('scrap_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF142428),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: l10n.translate('scrap_share'),
            onPressed: _shareScrapbookSummary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent))
          : _loadFailed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.translate('scrap_load_failed'),
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
                          label: Text(l10n.translate('scrap_share_button'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
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
    final l10n = context.l10n;
    final group = _tourGroup;
    final year = (group?.startDate ?? DateTime.now()).year;
    final origin = group?.originCity ?? l10n.translate('scrap_origin_unknown');
    final destination =
        group?.destination ?? l10n.translate('scrap_destination_unknown');

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
            child: Text(
              l10n.translate('scrap_badge_year',
                  args: {'year': l10n.number(year)}),
              style: const TextStyle(
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
            group != null
                ? '$_dateRange • ${group.durationText}'
                : l10n.translate('scrap_cover_subtitle'),
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
                  label: l10n.translate('scrap_badge_transport',
                      args: {'origin': origin})),
              _CoverBadge(
                  icon: Icons.hotel,
                  label: l10n.translate('scrap_badge_stay',
                      args: {'destination': destination})),
              _CoverBadge(
                  icon: Icons.explore_rounded,
                  label: l10n.translate('scrap_badge_explore',
                      args: {'destination': destination})),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: l10n.translate('scrap_metric_posts'),
            value: l10n.translate('scrap_posts_count',
                args: {'count': l10n.number(_posts.length)}),
            icon: Icons.photo_library,
            color: Colors.tealAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            title: l10n.translate('scrap_metric_members'),
            value: l10n.translate('scrap_members_count',
                args: {'count': l10n.number(_members.length)}),
            icon: Icons.groups,
            color: Colors.amber,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            title: l10n.translate('scrap_metric_duration'),
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
    final l10n = context.l10n;
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
          Row(
            children: [
              const Icon(Icons.stars, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('scrap_highlights'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (highlights.isEmpty)
            Text(
              l10n.translate('scrap_no_highlights'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
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
    final l10n = context.l10n;
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
          Row(
            children: [
              const Icon(Icons.military_tech, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('scrap_honor_roll'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.translate('scrap_honor_text'),
            style: const TextStyle(
                color: Colors.white70, fontSize: 11, height: 1.5),
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
