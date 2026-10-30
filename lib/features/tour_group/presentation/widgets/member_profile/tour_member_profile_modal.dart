import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/date_codec.dart';
import '../../../domain/models/expense_models.dart';
import '../../../domain/models/logistics_models.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/models/tour_post_models.dart';
import '../../../domain/services/trip_ledger_engine.dart';
import '../instafeed/instafeed_image_viewer_modal.dart';
import '../instafeed/instafeed_reels_modal.dart';
import '../instafeed/reel_thumbnail_preview.dart';
import '../instafeed/tour_safe_network_image.dart';

/// The modern, Instagram/Family Bhromon-style Tour Member Profile Modal.
/// Displays animated story-ring avatar, bio note, 4 quick metrics (Posts,
/// Likes, Tagged, Ledger Balance), logistics chips (Room, Bus Seat, Blood Group),
/// story category filters, achievements showcase, and a 4-tab media gallery.
class TourMemberProfileModal extends StatefulWidget {
  final String tourId;
  final String memberEmail;
  final String? memberName;
  final String? memberPhoto;
  final String? seatNumber;
  final String? roomNumber;
  final String? bloodGroup;
  final String? statusNote;
  final int? familyCount;
  final List<TourMember>? members;
  final List<TourPostItem>? posts;
  final List<BusSeat>? seats;
  final List<HotelRoom>? rooms;
  final List<ExpenseItem>? expenses;
  final List<TransferItem>? transfers;

  const TourMemberProfileModal({
    super.key,
    required this.tourId,
    required this.memberEmail,
    this.memberName,
    this.memberPhoto,
    this.seatNumber,
    this.roomNumber,
    this.bloodGroup,
    this.statusNote,
    this.familyCount,
    this.members,
    this.posts,
    this.seats,
    this.rooms,
    this.expenses,
    this.transfers,
  });

  static Future<void> show(
    BuildContext context, {
    required String tourId,
    required String memberEmail,
    String? memberName,
    String? memberPhoto,
    String? seatNumber,
    String? roomNumber,
    String? bloodGroup,
    String? statusNote,
    int? familyCount,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: TourMemberProfileModal(
          tourId: tourId,
          memberEmail: memberEmail,
          memberName: memberName,
          memberPhoto: memberPhoto,
          seatNumber: seatNumber,
          roomNumber: roomNumber,
          bloodGroup: bloodGroup,
          statusNote: statusNote,
          familyCount: familyCount,
        ),
      ),
    );
  }

  @override
  State<TourMemberProfileModal> createState() => _TourMemberProfileModalState();
}

class _TourMemberProfileModalState extends State<TourMemberProfileModal> {
  final TourGroupRepository _repo = TourGroupRepository();
  AudioPlayer? _audioPlayer;

  // Tabs: 'posts' | 'reels' | 'tagged' | 'info'
  String _activeTab = 'posts';

  // Category filters: 'all' | 'beach' | 'food' | 'journey' | 'sunset' | 'hotel' | 'hangout'
  String _activeCategory = 'all';

  bool _isMuted = true;
  String? _note;
  String? _bloodGroup;
  String? _phone;

  StreamSubscription<dynamic>? _profileSub;

  @override
  void initState() {
    super.initState();
    _note = widget.statusNote;
    _bloodGroup = widget.bloodGroup;
    _loadExtraProfileData();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _loadExtraProfileData() async {
    if (widget.members != null) return;
    try {
      // Profiles cannot be searched by email. The member's row in this tour gives
      // the uid, and the profile opens by that.
      final row = await FirebaseFirestore.instance
          .collection('memberships')
          .where('tourId', isEqualTo: widget.tourId)
          .where('email', isEqualTo: normalizeEmail(widget.memberEmail))
          .limit(1)
          .get();
      final uid = row.docs.isEmpty
          ? ''
          : (row.docs.first.data()['uid'] as String? ?? '');
      if (uid.isEmpty) return;
      final snap = await FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(uid)
          .get();

      if (snap.exists && mounted) {
        final data = snap.data() ?? const <String, dynamic>{};
        setState(() {
          _bloodGroup ??= data['bloodGroup'] as String?;
          _note ??= data['statusNote'] as String? ?? data['note'] as String?;
          _phone ??= data['phone'] as String?;
        });
      }
    } catch (_) {}
  }

  bool get _isMe {
    final me = _repo.currentEmail.trim().toLowerCase();
    return me.isNotEmpty && me == widget.memberEmail.trim().toLowerCase();
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    setState(() => _isMuted = !_isMuted);
    if (!_isMuted) {
      // Play a short pleasant travel tone if available
      try {
        _audioPlayer ??= AudioPlayer();
        _audioPlayer?.setVolume(0.5);
      } catch (_) {}
    }
  }

  void _shareProfile(AppLocalizations l10n, String name, String handle) {
    final text = '$name (@$handle) — Bhromon Traveler\nhttps://app.bhromon.fun';
    SharePlus.instance.share(ShareParams(text: text));
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.translate('prof_copied_link')),
        backgroundColor: AppColors.mintGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openDirectChat(BuildContext context, TourMember member) {
    final me = _repo.currentEmail;
    final myUid = _repo.currentUid.isNotEmpty ? _repo.currentUid : me;
    final remoteId = (member.uid != null && member.uid!.isNotEmpty)
        ? member.uid!
        : member.email;
    if (remoteId.isEmpty) return;

    final uids = [myUid, remoteId]..sort();
    final chatId = uids.join('_');
    Navigator.pop(context);
    GoRouter.of(context).push(
      '/chat/$chatId',
      extra: {
        'otherUid': remoteId,
        'sharedTourId': widget.tourId,
        'otherEmail': widget.memberEmail,
      },
    );
  }

  Future<void> _editNote(BuildContext context) async {
    if (!_isMe) return;
    final l10n = context.l10n;
    final ctrl = TextEditingController(text: _note ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B3326),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: AppColors.mintGreen),
            const SizedBox(width: 8),
            Text(l10n.translate('prof_note'),
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLength: 80,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.translate('prof_note_hint'),
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.mintGreen)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('tour_cancel'),
                style: const TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(l10n.translate('prof_save_note'),
                style: const TextStyle(
                    color: AppColors.darkGreen, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() => _note = result.isEmpty ? null : result);
      // Persist to user's explorer profile
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('explorer_profiles')
              .doc(user.uid)
              .set({'statusNote': result}, SetOptions(merge: true));
        }
      } catch (_) {}
    }
  }

  Future<void> _editBloodGroup(BuildContext context) async {
    if (!_isMe) return;
    final l10n = context.l10n;
    const groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
    String chosen = _bloodGroup ?? 'O+';

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1B3326),
          title: Row(
            children: [
              const Icon(Icons.bloodtype_rounded, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(l10n.translate('prof_blood_group'),
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: DropdownButtonFormField<String>(
            initialValue: groups.contains(chosen) ? chosen : 'O+',
            dropdownColor: const Color(0xFF14241B),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.mintGreen)),
            ),
            items: [
              for (final g in groups)
                DropdownMenuItem(value: g, child: Text(g)),
            ],
            onChanged: (v) {
              if (v != null) setDialog(() => chosen = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.translate('tour_cancel'),
                  style: const TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
              onPressed: () => Navigator.pop(ctx, chosen),
              child: Text(l10n.translate('tour_save'),
                  style: const TextStyle(
                      color: AppColors.darkGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _bloodGroup = result);
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('explorer_profiles')
              .doc(user.uid)
              .set({'bloodGroup': result}, SetOptions(merge: true));
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxCardWidth = screenWidth > 640 ? 560.0 : screenWidth * 0.94;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxCardWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F1B24),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: widget.members != null
                ? _buildDirectModalBody(l10n, widget.members!)
                : StreamBuilder<List<TourMember>>(
                    stream: _repo.watchMembers(widget.tourId),
                    builder: (context, membersSnap) {
                      final members = membersSnap.data ?? [];
                      final member = members.firstWhere(
                        (m) =>
                            normalizeEmail(m.email) ==
                            normalizeEmail(widget.memberEmail),
                        orElse: () => TourMember(
                          tourId: widget.tourId,
                          email: widget.memberEmail,
                          displayName: widget.memberName ?? 'Traveler',
                          photoUrl: widget.memberPhoto,
                          role: TourRole.member,
                          status: TourMemberStatus.active,
                          joinedAt: DateTime.now(),
                          familyCount: widget.familyCount ?? 1,
                        ),
                      );

                      return StreamBuilder<List<TourPostItem>>(
                        stream: _repo.watchPosts(widget.tourId),
                        builder: (context, postsSnap) {
                          final allPosts = postsSnap.data ?? [];
                          final normTarget = normalizeEmail(widget.memberEmail);

                          // User posts & reels
                          final authorPosts = allPosts
                              .where((p) =>
                                  normalizeEmail(p.authorEmail) == normTarget)
                              .toList();
                          final authorReels = authorPosts
                              .where((p) =>
                                  p.videoUrl != null && p.videoUrl!.isNotEmpty)
                              .toList();
                          final taggedPosts = allPosts
                              .where((p) => p.tags
                                  .map(normalizeEmail)
                                  .contains(normTarget))
                              .toList();

                          final totalLikes = authorPosts.fold<int>(
                              0, (sumLikes, p) => sumLikes + p.likes.length);

                          return StreamBuilder<List<BusSeat>>(
                            stream: _repo.watchBusSeats(widget.tourId),
                            builder: (context, seatsSnap) {
                              final seatList = seatsSnap.data ?? [];
                              final matchingSeat = seatList.firstWhere(
                                (s) =>
                                    normalizeEmail(
                                        s.assignedMemberEmail ?? '') ==
                                    normTarget,
                                orElse: () => const BusSeat(seatNumber: ''),
                              );
                              final seat = widget.seatNumber ??
                                  (matchingSeat.seatNumber.isNotEmpty
                                      ? matchingSeat.seatNumber
                                      : '');

                              return StreamBuilder<List<HotelRoom>>(
                                stream: _repo.watchHotelRooms(widget.tourId),
                                builder: (context, roomsSnap) {
                                  final roomList = roomsSnap.data ?? [];
                                  final matchingRoom = roomList.firstWhere(
                                    (r) => r.assignedMemberEmails
                                        .map(normalizeEmail)
                                        .contains(normTarget),
                                    orElse: () => const HotelRoom(
                                      id: '',
                                      roomNumber: '',
                                      title: '',
                                    ),
                                  );
                                  final room = widget.roomNumber ??
                                      (matchingRoom.roomNumber.isNotEmpty
                                          ? matchingRoom.roomNumber
                                          : '');

                                  return StreamBuilder<List<ExpenseItem>>(
                                    stream: _repo.watchExpenses(widget.tourId),
                                    builder: (context, expSnap) {
                                      final expenses = expSnap.data ?? [];
                                      return StreamBuilder<List<TransferItem>>(
                                        stream:
                                            _repo.watchTransfers(widget.tourId),
                                        builder: (context, xferSnap) {
                                          final transfers = xferSnap.data ?? [];
                                          final ledger =
                                              TripLedgerEngine.computeLedger(
                                            members: members
                                                .map((m) => LedgerMemberInput(
                                                      id: normalizeEmail(
                                                          m.email),
                                                      name: m.displayName,
                                                      familyCount:
                                                          m.familyCount,
                                                    ))
                                                .toList(),
                                            expenses: expenses,
                                            transfers: transfers,
                                          );
                                          final memberRow =
                                              ledger.rows.firstWhere(
                                            (r) =>
                                                normalizeEmail(r.id) ==
                                                normTarget,
                                            orElse: () => const LedgerMemberRow(
                                              id: '',
                                              name: '',
                                              familyCount: 1,
                                              depositPaisa: 0,
                                              directPaidPaisa: 0,
                                              contributedPaisa: 0,
                                              sharePaisa: 0,
                                              netPaisa: 0,
                                            ),
                                          );

                                          return _buildModalBody(
                                            l10n: l10n,
                                            member: member,
                                            seat: seat,
                                            room: room,
                                            balancePaisa: memberRow.netPaisa,
                                            posts: authorPosts,
                                            reels: authorReels,
                                            tagged: taggedPosts,
                                            likesCount: totalLikes,
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectModalBody(
      AppLocalizations l10n, List<TourMember> members) {
    final normTarget = normalizeEmail(widget.memberEmail);
    final member = members.firstWhere(
      (m) => normalizeEmail(m.email) == normTarget,
      orElse: () => TourMember(
        tourId: widget.tourId,
        email: widget.memberEmail,
        displayName: widget.memberName ?? 'Traveler',
        photoUrl: widget.memberPhoto,
        role: TourRole.member,
        status: TourMemberStatus.active,
        joinedAt: DateTime.now(),
        familyCount: widget.familyCount ?? 1,
      ),
    );
    final allPosts = widget.posts ?? [];
    final authorPosts = allPosts
        .where((p) => normalizeEmail(p.authorEmail) == normTarget)
        .toList();
    final authorReels = authorPosts
        .where((p) => p.videoUrl != null && p.videoUrl!.isNotEmpty)
        .toList();
    final taggedPosts = allPosts
        .where((p) => p.tags.map(normalizeEmail).contains(normTarget))
        .toList();
    final totalLikes =
        authorPosts.fold<int>(0, (sumLikes, p) => sumLikes + p.likes.length);

    final seatList = widget.seats ?? [];
    final matchingSeat = seatList.firstWhere(
      (s) => normalizeEmail(s.assignedMemberEmail ?? '') == normTarget,
      orElse: () => const BusSeat(seatNumber: ''),
    );
    final seat = widget.seatNumber ??
        (matchingSeat.seatNumber.isNotEmpty ? matchingSeat.seatNumber : '');

    final roomList = widget.rooms ?? [];
    final matchingRoom = roomList.firstWhere(
      (r) => r.assignedMemberEmails.map(normalizeEmail).contains(normTarget),
      orElse: () => const HotelRoom(id: '', roomNumber: '', title: ''),
    );
    final room = widget.roomNumber ??
        (matchingRoom.roomNumber.isNotEmpty ? matchingRoom.roomNumber : '');

    final expenses = widget.expenses ?? [];
    final transfers = widget.transfers ?? [];
    final ledger = TripLedgerEngine.computeLedger(
      members: members
          .map((m) => LedgerMemberInput(
                id: normalizeEmail(m.email),
                name: m.displayName,
                familyCount: m.familyCount,
              ))
          .toList(),
      expenses: expenses,
      transfers: transfers,
    );
    final memberRow = ledger.rows.firstWhere(
      (r) => normalizeEmail(r.id) == normTarget,
      orElse: () => const LedgerMemberRow(
        id: '',
        name: '',
        familyCount: 1,
        depositPaisa: 0,
        directPaidPaisa: 0,
        contributedPaisa: 0,
        sharePaisa: 0,
        netPaisa: 0,
      ),
    );

    return _buildModalBody(
      l10n: l10n,
      member: member,
      seat: seat,
      room: room,
      balancePaisa: memberRow.netPaisa,
      posts: authorPosts,
      reels: authorReels,
      tagged: taggedPosts,
      likesCount: totalLikes,
    );
  }

  Widget _buildModalBody({
    required AppLocalizations l10n,
    required TourMember member,
    required String seat,
    required String room,
    required int balancePaisa,
    required List<TourPostItem> posts,
    required List<TourPostItem> reels,
    required List<TourPostItem> tagged,
    required int likesCount,
  }) {
    final handle = member.displayName.replaceAll(' ', '_');

    // Achievements calculation
    final achievements = <({String title, IconData icon, Color color})>[
      if (posts.length >= 3)
        (
          title: l10n.translate('prof_achieve_photographer'),
          icon: Icons.camera_alt_rounded,
          color: Colors.blueAccent,
        ),
      if (reels.isNotEmpty)
        (
          title: l10n.translate('prof_achieve_reels_director'),
          icon: Icons.movie_creation_rounded,
          color: Colors.purpleAccent,
        ),
      (
        title: l10n.translate('prof_achieve_star_traveler'),
        icon: Icons.star_rounded,
        color: AppColors.gold,
      ),
      if (_bloodGroup != null && _bloodGroup!.isNotEmpty)
        (
          title: l10n.translate('prof_achieve_life_saver'),
          icon: Icons.favorite_rounded,
          color: Colors.redAccent,
        ),
      if (room.isNotEmpty)
        (
          title: l10n.translate('prof_achieve_explorer'),
          icon: Icons.hotel_rounded,
          color: AppColors.mintGreen,
        ),
      if (balancePaisa > 0)
        (
          title: l10n.translate('prof_achieve_top_spender'),
          icon: Icons.account_balance_wallet_rounded,
          color: Colors.amber,
        ),
    ];

    return Column(
      children: [
        // 1. Header Bar: @handle, Sound toggle, Share, Close
        _buildHeaderBar(l10n, member.displayName, handle),

        // Scrollable profile contents
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // 2. Avatar with Story Gradient Ring & 4 Metrics
              _buildAvatarAndStats(
                l10n: l10n,
                member: member,
                postsCount: posts.length,
                likesCount: likesCount,
                taggedCount: tagged.length,
                balancePaisa: balancePaisa,
              ),
              const SizedBox(height: 14),

              // 3. Name, Role Pill & Logistics Chips (Room, Bus Seat, Blood Group)
              _buildIdentityAndBadges(
                l10n: l10n,
                member: member,
                seat: seat,
                room: room,
              ),
              const SizedBox(height: 16),

              // 4. Action Buttons (Edit Profile / Send Message + Share)
              _buildActionButtons(l10n, member, handle),
              const SizedBox(height: 18),

              // 5. Story Category Circles (হাইজলাইটস / ক্যাটাগরি)
              _buildCategoryCircles(l10n),
              const SizedBox(height: 18),

              // 6. Achievements Showcase (অর্জনের শোকেস)
              if (achievements.isNotEmpty) ...[
                _buildAchievementsShowcase(l10n, achievements),
                const SizedBox(height: 18),
              ],

              // 7. 4-Tab Navigation Bar (পোস্ট, রিলস, ট্যাগড, তথ্য)
              _buildTabSelector(
                l10n: l10n,
                postsCount: posts.length,
                reelsCount: reels.length,
                taggedCount: tagged.length,
              ),
              const SizedBox(height: 14),

              // 8. Tab Content (3-Column Media Grid or Info Card)
              _buildTabContent(
                l10n: l10n,
                member: member,
                seat: seat,
                room: room,
                posts: posts,
                reels: reels,
                tagged: tagged,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Top Header Bar
  // ---------------------------------------------------------------------------
  Widget _buildHeaderBar(AppLocalizations l10n, String name, String handle) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '@$handle',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _isMuted ? Colors.white38 : AppColors.mintGreen,
              size: 20,
            ),
            tooltip: _isMuted ? 'Sound on' : 'Mute',
            onPressed: _toggleMute,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined,
                color: Colors.white70, size: 20),
            tooltip: l10n.translate('prof_share'),
            onPressed: () => _shareProfile(l10n, name, handle),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: Colors.white70, size: 22),
            tooltip: l10n.translate('tour_cancel'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Avatar & 4 Quick Stats Row
  // ---------------------------------------------------------------------------
  Widget _buildAvatarAndStats({
    required AppLocalizations l10n,
    required TourMember member,
    required int postsCount,
    required int likesCount,
    required int taggedCount,
    required int balancePaisa,
  }) {
    // Format balance properly: +150৳, -50৳, or 0৳ (No NaN)
    final String balanceText;
    final Color balanceColor;
    if (balancePaisa > 0) {
      balanceText = '+${TripLedgerEngine.formatTaka(balancePaisa)}';
      balanceColor = AppColors.mintGreen;
    } else if (balancePaisa < 0) {
      balanceText = '-${TripLedgerEngine.formatTaka(balancePaisa.abs())}';
      balanceColor = Colors.orangeAccent;
    } else {
      balanceText = '০৳';
      balanceColor = Colors.white70;
    }

    return Row(
      children: [
        // Avatar + Status Note
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status Note bubble above avatar
            GestureDetector(
              onTap: () => _editNote(context),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.mintGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isMe && _note == null)
                      const Icon(Icons.add,
                          size: 11, color: AppColors.mintGreen),
                    Text(
                      _note ?? l10n.translate('prof_note_add'),
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            // Gradient ring around avatar
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFF58529),
                    Color(0xFFFEDA77),
                    Color(0xFFDD2A7B),
                    Color(0xFF8134AF),
                    Color(0xFF515BD4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFDD2A7B).withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFF0F1B24),
                backgroundImage: member.photoUrl != null
                    ? NetworkImage(member.photoUrl!)
                    : null,
                child: member.photoUrl == null
                    ? Text(
                        member.displayName.isNotEmpty
                            ? member.displayName[0].toUpperCase()
                            : 'M',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(width: 18),

        // 4 Quick Stats (Posts, Likes, Tagged, Balance)
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatColumn(l10n.number(postsCount),
                  l10n.translate('prof_posts'), Colors.white),
              _buildStatColumn(l10n.number(likesCount),
                  l10n.translate('prof_likes'), const Color(0xFFFF5252)),
              _buildStatColumn(l10n.number(taggedCount),
                  l10n.translate('prof_tagged'), Colors.white70),
              _buildStatColumn(
                  balanceText, l10n.translate('prof_balance'), balanceColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatColumn(String value, String label, Color valueColor) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Name, Role Pill & Logistics Chips
  // ---------------------------------------------------------------------------
  Widget _buildIdentityAndBadges({
    required AppLocalizations l10n,
    required TourMember member,
    required String seat,
    required String room,
  }) {
    final roleText = switch (member.role) {
      TourRole.owner => l10n.translate('prof_role_owner'),
      TourRole.admin => l10n.translate('prof_role_admin'),
      _ => l10n.translate('prof_role_member'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                member.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.mintGreen.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.mintGreen.withValues(alpha: 0.4)),
              ),
              child: Text(
                roleText,
                style: const TextStyle(
                  color: AppColors.mintGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Detail chips row (Room, Bus Seat, Blood Group)
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (room.isNotEmpty)
              _buildDetailChip(
                icon: Icons.hotel_rounded,
                text: room.startsWith('রুম') || room.startsWith('Room')
                    ? room
                    : '${l10n.translate('prof_hotel_room')} $room',
                color: Colors.amberAccent,
              ),
            if (seat.isNotEmpty)
              _buildDetailChip(
                icon: Icons.directions_bus_rounded,
                text: seat.startsWith('সিট') || seat.startsWith('Seat')
                    ? seat
                    : '${l10n.translate('prof_transport_seat')} $seat',
                color: Colors.cyanAccent,
              ),
            GestureDetector(
              onTap: () => _editBloodGroup(context),
              child: _buildDetailChip(
                icon: Icons.bloodtype_rounded,
                text: _bloodGroup != null && _bloodGroup!.isNotEmpty
                    ? _bloodGroup!
                    : (_isMe
                        ? '+ ${l10n.translate('prof_blood_group')}'
                        : 'O+'),
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Action Buttons Row (Edit Profile / Message + Share)
  // ---------------------------------------------------------------------------
  Widget _buildActionButtons(
      AppLocalizations l10n, TourMember member, String handle) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1B3326),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white12),
              ),
            ),
            onPressed: () {
              if (_isMe) {
                _editNote(context);
              } else {
                _openDirectChat(context, member);
              }
            },
            icon: Icon(
              _isMe ? Icons.edit_rounded : Icons.chat_bubble_outline_rounded,
              size: 15,
              color: AppColors.mintGreen,
            ),
            label: Text(
              _isMe
                  ? l10n.translate('prof_edit')
                  : l10n.translate('prof_send_message'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white12),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _shareProfile(l10n, member.displayName, handle),
            icon: const Icon(Icons.share_outlined, size: 14),
            label: Text(
              l10n.translate('prof_share'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Story Category Circles (হাইজলাইটস / ক্যাটাগরি)
  // ---------------------------------------------------------------------------
  Widget _buildCategoryCircles(AppLocalizations l10n) {
    final categories = [
      (
        id: 'all',
        label: l10n.translate('prof_all_posts'),
        icon: Icons.wb_sunny_rounded,
        color: AppColors.gold,
      ),
      (
        id: 'beach',
        label: l10n.translate('prof_cat_beach'),
        icon: Icons.beach_access_rounded,
        color: Colors.lightBlueAccent,
      ),
      (
        id: 'food',
        label: l10n.translate('prof_cat_food'),
        icon: Icons.restaurant_rounded,
        color: Colors.orangeAccent,
      ),
      (
        id: 'journey',
        label: l10n.translate('prof_cat_journey'),
        icon: Icons.directions_bus_rounded,
        color: AppColors.mintGreen,
      ),
      (
        id: 'sunset',
        label: l10n.translate('prof_cat_sunset'),
        icon: Icons.wb_twilight_rounded,
        color: Colors.deepOrangeAccent,
      ),
      (
        id: 'hotel',
        label: l10n.translate('prof_cat_hotel'),
        icon: Icons.hotel_rounded,
        color: Colors.pinkAccent,
      ),
      (
        id: 'hangout',
        label: l10n.translate('prof_cat_hangout'),
        icon: Icons.celebration_rounded,
        color: Colors.purpleAccent,
      ),
    ];

    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final cat = categories[i];
          final isSelected = _activeCategory == cat.id;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _activeCategory = cat.id);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? cat.color : Colors.white24,
                      width: isSelected ? 2.2 : 1.0,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: isSelected
                        ? cat.color.withValues(alpha: 0.25)
                        : const Color(0xFF182630),
                    child: Icon(cat.icon,
                        size: 20,
                        color: isSelected ? cat.color : Colors.white70),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  cat.label,
                  style: TextStyle(
                    color: isSelected ? cat.color : Colors.white60,
                    fontSize: 10,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Achievements Showcase (অর্জনের শোকেস)
  // ---------------------------------------------------------------------------
  Widget _buildAchievementsShowcase(
    AppLocalizations l10n,
    List<({String title, IconData icon, Color color})> list,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events_rounded,
                size: 16, color: AppColors.gold),
            const SizedBox(width: 6),
            Text(
              '${l10n.translate('prof_achievements')} (${l10n.number(list.length)})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final a = list[i];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF14241B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: a.color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.icon, size: 14, color: a.color),
                    const SizedBox(width: 6),
                    Text(
                      a.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 4-Tab Navigation Selector
  // ---------------------------------------------------------------------------
  Widget _buildTabSelector({
    required AppLocalizations l10n,
    required int postsCount,
    required int reelsCount,
    required int taggedCount,
  }) {
    final tabs = [
      (
        id: 'posts',
        label:
            '${l10n.translate('prof_tab_posts')} (${l10n.number(postsCount)})',
        icon: Icons.grid_on_rounded,
      ),
      (
        id: 'reels',
        label:
            '${l10n.translate('prof_tab_reels')} (${l10n.number(reelsCount)})',
        icon: Icons.video_collection_rounded,
      ),
      (
        id: 'tagged',
        label:
            '${l10n.translate('prof_tab_tagged')} (${l10n.number(taggedCount)})',
        icon: Icons.sell_rounded,
      ),
      (
        id: 'info',
        label: l10n.translate('prof_tab_info'),
        icon: Icons.info_outline_rounded,
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          for (final t in tabs)
            Expanded(
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _activeTab = t.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _activeTab == t.id
                            ? AppColors.mintGreen
                            : Colors.transparent,
                        width: 2.2,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        t.icon,
                        size: 18,
                        color: _activeTab == t.id
                            ? AppColors.mintGreen
                            : Colors.white38,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        t.label,
                        style: TextStyle(
                          color: _activeTab == t.id
                              ? Colors.white
                              : Colors.white54,
                          fontSize: 10,
                          fontWeight: _activeTab == t.id
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab Content View (3-Column Grid or Info Tab)
  // ---------------------------------------------------------------------------
  Widget _buildTabContent({
    required AppLocalizations l10n,
    required TourMember member,
    required String seat,
    required String room,
    required List<TourPostItem> posts,
    required List<TourPostItem> reels,
    required List<TourPostItem> tagged,
  }) {
    switch (_activeTab) {
      case 'reels':
        if (reels.isEmpty) {
          return _buildEmptyState(
              Icons.slow_motion_video_rounded, l10n.translate('prof_no_reels'));
        }
        return _buildMediaGrid(reels);

      case 'tagged':
        if (tagged.isEmpty) {
          return _buildEmptyState(
              Icons.sell_outlined, l10n.translate('prof_no_tagged'));
        }
        return _buildMediaGrid(tagged);

      case 'info':
        return _buildInfoTab(l10n, member, seat, room);

      case 'posts':
      default:
        // Filter posts by category if selected
        final filtered = _activeCategory == 'all'
            ? posts
            : posts.where((p) {
                final text = '${p.caption} ${p.location}'.toLowerCase();
                return switch (_activeCategory) {
                  'beach' => text.contains('beach') ||
                      text.contains('বিচ') ||
                      text.contains('সৈকত'),
                  'food' => text.contains('food') ||
                      text.contains('খাবার') ||
                      text.contains('মাছ'),
                  'journey' => text.contains('bus') ||
                      text.contains('বাস') ||
                      text.contains('জার্নি') ||
                      text.contains('যাত্রা'),
                  'sunset' => text.contains('sunset') ||
                      text.contains('সানসেট') ||
                      text.contains('সূর্যাস্ত'),
                  'hotel' => text.contains('hotel') ||
                      text.contains('হোটেল') ||
                      text.contains('রুম'),
                  'hangout' => text.contains('fun') ||
                      text.contains('আড্ডা') ||
                      text.contains('গান'),
                  _ => true,
                };
              }).toList();

        if (filtered.isEmpty) {
          return _buildEmptyState(
              Icons.photo_library_outlined, l10n.translate('prof_no_posts'));
        }
        return _buildMediaGrid(filtered);
    }
  }

  Widget _buildMediaGrid(List<TourPostItem> list) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemBuilder: (context, i) {
        final post = list[i];
        final isVideo = post.videoUrl != null && post.videoUrl!.isNotEmpty;
        final hasImages = post.images.isNotEmpty;
        final isMultiImage = post.images.length > 1;
        final thumb = post.coverUrl ?? (hasImages ? post.images.first : null);

        return GestureDetector(
          onTap: () {
            if (isVideo) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => InstafeedReelsModal(
                    repository: _repo,
                    tourId: widget.tourId,
                    reels: list,
                    initialIndex: i,
                  ),
                ),
              );
            } else if (hasImages) {
              InstafeedImageViewerModal.show(
                context,
                repository: _repo,
                tourId: widget.tourId,
                post: post,
                initialIndex: 0,
              );
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb != null)
                TourSafeNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  placeholder: Container(color: Colors.black26),
                  errorWidget: Container(
                    color: const Color(0xFF14241B),
                    child: const Icon(Icons.photo, color: Colors.white24),
                  ),
                )
              else if (isVideo)
                ReelThumbnailPreview(videoUrl: post.videoUrl!)
              else
                Container(
                  color: const Color(0xFF14241B),
                  child: const Icon(Icons.photo, color: Colors.white24),
                ),

              // Badges
              if (isVideo)
                const Positioned(
                  top: 5,
                  right: 5,
                  child: Icon(Icons.play_arrow_rounded,
                      size: 18, color: Colors.white),
                )
              else if (isMultiImage)
                const Positioned(
                  top: 5,
                  right: 5,
                  child: Icon(Icons.collections_rounded,
                      size: 14, color: Colors.white),
                ),

              // Like count on bottom
              if (post.likes.isNotEmpty)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite,
                          size: 10, color: Colors.redAccent),
                      const SizedBox(width: 2),
                      Text(
                        '${post.likes.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoTab(
    AppLocalizations l10n,
    TourMember member,
    String seat,
    String room,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.email_outlined,
            label: l10n.translate('prof_info_email'),
            value: member.email,
          ),
          const Divider(color: Colors.white10, height: 20),
          if (_phone != null && _phone!.isNotEmpty) ...[
            _buildInfoRow(
              icon: Icons.phone_outlined,
              label: l10n.translate('prof_info_phone'),
              value: _phone!,
            ),
            const Divider(color: Colors.white10, height: 20),
          ],
          _buildInfoRow(
            icon: Icons.bloodtype_outlined,
            label: l10n.translate('prof_blood_group'),
            value: _bloodGroup ?? 'O+',
            valueColor: Colors.redAccent,
          ),
          const Divider(color: Colors.white10, height: 20),
          _buildInfoRow(
            icon: Icons.hotel_outlined,
            label: l10n.translate('prof_hotel_room'),
            value: room.isNotEmpty ? room : l10n.translate('ig_not_assigned'),
            valueColor: Colors.amberAccent,
          ),
          const Divider(color: Colors.white10, height: 20),
          _buildInfoRow(
            icon: Icons.directions_bus_outlined,
            label: l10n.translate('prof_transport_seat'),
            value: seat.isNotEmpty ? seat : l10n.translate('ig_not_assigned'),
            valueColor: Colors.cyanAccent,
          ),
          const Divider(color: Colors.white10, height: 20),
          _buildInfoRow(
            icon: Icons.family_restroom_rounded,
            label: l10n.translate('prof_info_family'),
            value: '${l10n.number(member.familyCount)} জন',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white54),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.white24),
            const SizedBox(height: 10),
            Text(message,
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
