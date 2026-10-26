import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/expense_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/models/tour_post_models.dart';
import '../../domain/services/scrapbook_engine.dart';
import '../widgets/scrapbook/scrapbook_magazine.dart';

/// The tour's magazine. This screen loads the tour, its members, posts and
/// ledger; [ScrapbookMagazine] lays them out as pages.
class TourScrapbookScreen extends StatefulWidget {
  final String tourId;

  const TourScrapbookScreen({super.key, required this.tourId});

  /// How many of the newest posts the magazine reads.
  static const postLimit = 300;

  @override
  State<TourScrapbookScreen> createState() => _TourScrapbookScreenState();
}

class _TourScrapbookScreenState extends State<TourScrapbookScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  TourGroup? _tourGroup;
  StreamSubscription<TourGroup?>? _groupSub;
  List<TourMember> _members = const [];
  List<TourPostItem> _posts = const [];
  List<ExpenseItem> _expenses = const [];
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

  /// Everything the magazine shows comes from the tour itself: the group, its
  /// members, its posts and its ledger. Nothing is invented when data is
  /// missing. The ledger is optional: if it cannot be read, the money figures
  /// are left out rather than failing the whole magazine.
  Future<void> _loadScrapbookData() async {
    try {
      final members = await _repository.watchMembers(widget.tourId).first;
      final posts = await _repository
          .watchPosts(widget.tourId, limit: TourScrapbookScreen.postLimit)
          .first;
      var expenses = const <ExpenseItem>[];
      try {
        expenses = await _repository.watchExpenses(widget.tourId).first;
      } catch (e) {
        debugPrint('Scrapbook: ledger not available: $e');
      }
      if (!mounted) return;
      setState(() {
        _members = members;
        _posts = posts;
        _expenses = expenses;
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

  void _shareScrapbookSummary() {
    final l10n = context.l10n;
    final group = _tourGroup;
    final tourName = group?.name ?? l10n.translate('scrap_default_name');
    final spots = group?.allSpots.take(5).toList() ??
        [
          l10n.translate('scrap_spot_main'),
          l10n.translate('scrap_spot_hotels'),
        ];
    final format = DateFormat('d MMM yyyy');

    final shareText = l10n.translate('scrap_share_text', args: {
      'name': tourName,
      'dates': group == null
          ? l10n.translate('scrap_dates_unknown')
          : '${format.format(group.startDate)} – ${format.format(group.endDate)}',
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

    return Scaffold(
      backgroundColor: const Color(0xFF15110D),
      appBar: AppBar(
        title: Text(l10n.translate('scrap_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF15110D),
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
              child: CircularProgressIndicator(color: Color(0xFFE8B04B)))
          : _loadFailed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.translate('scrap_load_failed'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                )
              : ScrapbookMagazine(
                  issue: ScrapbookIssue.build(
                    posts: _posts,
                    members: _members,
                    expenses: _expenses,
                    days: _tourGroup?.daysList ?? const [],
                  ),
                  posts: _posts,
                  group: _tourGroup,
                  travellers: _members.length,
                  myEmail: _repository.currentEmail,
                  onShareText: _shareScrapbookSummary,
                ),
    );
  }
}
